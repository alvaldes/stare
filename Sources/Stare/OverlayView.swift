import AppKit
import StareCore

/// Draws one display's marks and turns mouse and keyboard input into a
/// `DrawingSession`. Coordinates are top-left origin, local to the display.
final class OverlayView: NSView {
    let state: EditorState
    private(set) var session = DrawingSession()
    var onEscape: (() -> Void)?
    /// Reports a committed mark so the controller can undo across displays.
    var onCommit: ((Stroke) -> Void)?
    /// Command-Z is global: the controller owns the undo history.
    var onUndo: (() -> Void)?
    /// Shift-Command-Z is global for the same reason.
    var onRedo: (() -> Void)?
    /// Marks removed by the eraser, so the undo history can drop them too.
    var onErase: (([UUID]) -> Void)?
    /// Asks for a capture: nil means the whole display, a rect means that area.
    var onCaptureRequest: ((CGRect?) -> Void)?
    /// Latest live frames per display, owned by the controller. Blur marks
    /// paint the real screen content from here; nil in headless renders.
    weak var liveFrameSource: LiveFrameSource?
    /// Which display this view draws, so the frame source can be queried.
    var displayID: CGDirectDisplayID = 0
    /// Blur marks appear and disappear through several paths (drag, commit,
    /// undo, erase, clear); the live frame source needs a signal each time.
    var onBlurMarksChanged: (() -> Void)?

    static let textFont = NSFont.systemFont(ofSize: 20, weight: .regular)
    /// The pointer highlight is a thick translucent band with bright edges and a
    /// soft glow, sized from preferences.
    static let pointerGlowMultiplier: CGFloat = 1.9
    static let pointerBandRatio: CGFloat = 0.26
    private static let eraserRadius: CGFloat = 8

    private var textField: NSTextField?
    private var laserTimer: Timer?
    private var pointerLocation: CGPoint?
    private var isSelectingArea = false
    private var selectionOrigin: CGPoint?
    private var selectionRect: CGRect?
    private var lastPointerChange = Date()
    /// Pointer mode paints only the highlight: no marks, no frame, no hint.
    var showsOnlyPointer = false {
        didSet { needsDisplay = true }
    }

    /// Bounds of committed marks, computed once, so a redraw never rebuilds a
    /// path just to decide whether a stroke is visible.
    private var committedBounds: [UUID: CGRect] = [:]
    private var lastDragPoint: CGPoint?
    private var lastStraight = false
    private var lastInputTimestamp: TimeInterval = 0

    init(frame: NSRect, state: EditorState, onEscape: @escaping () -> Void) {
        self.state = state
        self.onEscape = onEscape
        super.init(frame: frame)
        // No layer backing: a stroke is a handful of paths, and direct drawing
        // into the window's backing store avoids a Core Animation transaction
        // per mouse event.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OverlayView is created in code only")
    }

    // Top-left origin, so stroke points map directly onto screen and capture
    // coordinates without a flip.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The panel must take key status on click so tool keys and Escape work
    /// while the app itself never shows a window or a Dock icon.
    override var needsPanelToBecomeKey: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
        )
    }

    /// `.activeAlways` keeps the tool cursor working even when the app is not the
    /// active one, which cursor rectangles alone do not allow.
    override func cursorUpdate(with event: NSEvent) {
        cursorForTool.set()
    }

    /// Each tool shouts what it does: text wants an I-beam, drawing tools want a
    /// crosshair.
    private var cursorForTool: NSCursor {
        state.tool == .text ? .iBeam : .crosshair
    }

    override func mouseEntered(with event: NSEvent) {
        cursorForTool.set()
    }

    override func mouseMoved(with event: NSEvent) {
        // Re-assert the tool cursor on every move: cursor rectangles only fire
        // when the pointer crosses a boundary, which is why the cursor used to
        // change only after jumping to another display.
        cursorForTool.set()
    }

    override func mouseExited(with event: NSEvent) {
        guard let previous = pointerLocation else { return }
        pointerLocation = nil
        setNeedsDisplay(pointerRect(around: previous))
    }

    // MARK: - Session

    var isEmpty: Bool { session.isEmpty }

    /// The session fades laser marks using the user's configured lifetime.
    func syncPreferences() {
        session.laserLifetime = state.laserLifetime
        window?.invalidateCursorRects(for: self)
        cursorForTool.set()
    }

    func clear() {
        session.clear()
        committedBounds.removeAll()
        finishTextEditing(commit: false)
        stopLaserTimer()
        noteBlurInterestChanged()
        needsDisplay = true
    }

    /// Discards the mark being dragged, if any.
    @discardableResult
    func discardActiveMark() -> Bool {
        guard session.active != nil else { return false }
        session.undo()
        noteBlurInterestChanged()
        needsDisplay = true
        return true
    }

    /// Puts a specific mark back, used by the global redo history. It only takes
    /// the mark the session undid last, so a global order that drifted cannot
    /// resurrect the wrong mark.
    @discardableResult
    func redoMark(id: UUID) -> Bool {
        guard session.undoneStrokes.last?.id == id, session.redo() else { return false }
        noteBlurInterestChanged()
        needsDisplay = true
        return true
    }

    /// Removes a specific committed mark, used by the global undo history.
    @discardableResult
    func removeMark(id: UUID) -> Bool {
        guard session.remove(id: id) else { return false }
        committedBounds.removeValue(forKey: id)
        noteBlurInterestChanged()
        needsDisplay = true
        return true
    }

    // MARK: - Live blur

    /// Live frames are only worth capturing while a blur mark is visible on
    /// this display, committed or being dragged.
    var hasLiveBlurMarks: Bool {
        session.active?.tool == .blur || session.strokes.contains { $0.tool == .blur }
    }

    /// A new live frame arrived: repaint the blur marks only. A frame cannot
    /// change anything else, so canvases without blur marks never redraw.
    func invalidateLiveBlurMarks() {
        guard hasLiveBlurMarks else { return }
        for stroke in session.strokes where stroke.tool == .blur {
            setNeedsDisplay(stroke.bounds)
        }
        if let active = session.active, active.tool == .blur {
            setNeedsDisplay(active.bounds)
        }
    }

    /// Tells the frame source that blur interest may have changed; this is
    /// also what stops its timer when the last blur mark disappears.
    private func noteBlurInterestChanged() {
        onBlurMarksChanged?()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        // The window under the pointer owns the keyboard so tool keys always
        // apply to the display being drawn on.
        window?.makeKey()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        lastDragPoint = point
        lastStraight = false
        lastInputTimestamp = event.timestamp
        Diag.log("mouseDown \(Int(point.x)),\(Int(point.y)) tool=\(state.tool.rawValue)")

        if isSelectingArea {
            selectionOrigin = point
            selectionRect = CGRect(origin: point, size: .zero)
            needsDisplay = true
            return
        }

        switch state.tool {
        case .eraser:
            finishPendingTextEditing()
            erase(at: point)
            return
        case .text:
            beginTextEditing(at: point)
            return
        default:
            // A mark of another tool must not leave a text editor behind: it
            // would keep its field as a subview and swallow what is underneath.
            finishPendingTextEditing()
        }

        session.begin(at: point, tool: state.tool, ink: state.ink)
        if state.tool.isTransient { startLaserTimer() }
        noteBlurInterestChanged()
        setNeedsDisplay(dirtyRect(around: point, other: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        if isSelectingArea {
            let point = convert(event.locationInWindow, from: nil)
            guard let origin = selectionOrigin else { return }
            selectionRect = PathBuilder.normalizedRect(from: origin, to: point)
            needsDisplay = true
            return
        }

        if state.tool == .eraser {
            lastDragPoint = convert(event.locationInWindow, from: nil)
            erase(at: lastDragPoint ?? .zero)
            return
        }

        let shift = event.modifierFlags.contains(.shift)
        let point = adjusted(convert(event.locationInWindow, from: nil), shift: shift)
        let straight = straightConstraint(shift)
        let previousPoint = lastDragPoint
        // A shape or a line is defined by its endpoints, so its whole preview
        // changes on every move: invalidating only the last segment leaves the
        // previous previews painted, which is what looked like a dashed trail.
        let previousShapeBounds = state.tool.usesEndpointsOnly ? session.active?.bounds : nil

        lastDragPoint = point
        lastInputTimestamp = event.timestamp
        session.extend(to: point, straight: straight)

        if let previousShapeBounds, let currentShapeBounds = session.active?.bounds {
            setNeedsDisplay(previousShapeBounds.union(currentShapeBounds).insetBy(dx: -4, dy: -4))
        } else if state.tool.usesEndpointsOnly || straight != lastStraight {
            lastStraight = straight
            needsDisplay = true
        } else {
            setNeedsDisplay(dirtyRect(around: point, other: previousPoint))
        }
    }

    /// Shift means a straight line for freehand tools and a square or circle for
    /// shapes.
    private func adjusted(_ point: CGPoint, shift: Bool) -> CGPoint {
        guard shift, state.tool == .rectangle || state.tool == .ellipse,
              let start = session.active?.points.first else { return point }
        return PathBuilder.squareConstraint(from: start, to: point)
    }

    private func straightConstraint(_ shift: Bool) -> Bool {
        guard shift else { return false }
        return state.tool == .pen || state.tool == .highlighter
    }

    override func mouseUp(with event: NSEvent) {
        if isSelectingArea {
            let rect = selectionRect
            isSelectingArea = false
            selectionOrigin = nil
            selectionRect = nil
            needsDisplay = true
            if let rect, rect.width >= 4, rect.height >= 4 {
                onCaptureRequest?(rect)
            } else {
                Diag.log("capture area too small, ignored")
            }
            return
        }

        // Click tools are committed by their own path: numbered steps when
        // placed, text when the editor confirms. Committing here would close the
        // text mark the click just opened.
        guard !state.tool.isClickTool else { return }

        let shift = event.modifierFlags.contains(.shift)
        let point = adjusted(convert(event.locationInWindow, from: nil), shift: shift)
        session.extend(to: point, straight: straightConstraint(shift))
        session.commit()
        if let committed = session.strokes.last {
            committedBounds[committed.id] = committed.bounds
            onCommit?(committed)
        }
        lastDragPoint = nil
        lastStraight = false
        Diag.log("commit strokes=\(session.strokes.count)")
        // Full redraw: the first mark also removes the armed frame at the edges.
        needsDisplay = true
        noteBlurInterestChanged()
    }

    // MARK: - Area selection

    private func beginAreaSelection() {
        finishPendingTextEditing()
        isSelectingArea = true
        selectionOrigin = nil
        selectionRect = nil
        needsDisplay = true
        Diag.log("area selection started")
    }

    private func cancelAreaSelection() {
        isSelectingArea = false
        selectionOrigin = nil
        selectionRect = nil
        needsDisplay = true
        Diag.log("area selection cancelled")
    }

    private func drawSelection(in context: CGContext) {
        guard isSelectingArea else { return }

        guard let rect = selectionRect, rect.width > 0, rect.height > 0 else {
            context.setFillColor(CGColor(gray: 0, alpha: 0.18))
            context.fill(bounds)
            return
        }

        let shroud = CGMutablePath()
        shroud.addRect(bounds)
        shroud.addRect(rect)
        context.setFillColor(CGColor(gray: 0, alpha: 0.32))
        context.addPath(shroud)
        context.fillPath(using: .evenOdd)

        context.setStrokeColor(state.ink.cgColor(alpha: 0.95))
        context.setLineWidth(2)
        context.addRect(rect)
        context.strokePath()
    }

    // MARK: - Eraser

    private func erase(at point: CGPoint) {
        let removed = session.erase(at: point, radius: Self.eraserRadius)
        guard !removed.isEmpty else { return }
        for id in removed { committedBounds.removeValue(forKey: id) }
        onErase?(removed)
        noteBlurInterestChanged()
        Diag.log("erase count=\(removed.count) remaining=\(session.strokes.count)")
        needsDisplay = true
    }

    // MARK: - Text

    private func beginTextEditing(at point: CGPoint) {
        finishTextEditing(commit: true)
        session.begin(at: point, tool: .text, ink: state.ink)

        let field = NSTextField(frame: CGRect(x: point.x, y: point.y, width: 320, height: 30))
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Self.textFont
        field.textColor = NSColor(cgColor: state.ink.cgColor()) ?? .white
        field.delegate = self
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        Diag.log("text editing started")
    }

    /// Confirms whatever is open in the text editor. Called when the tool
    /// changes or another mark starts, so an unfinished text can never linger.
    func finishPendingTextEditing() {
        finishTextEditing(commit: true)
    }

    /// Confirms or discards the text mark in progress. Empty text never becomes
    /// a mark: a stray click must not leave an invisible box behind.
    ///
    /// `typed` must come from the field editor while it is live: the cell behind
    /// an editing NSTextField is not guaranteed to hold the latest keystrokes.
    private func finishTextEditing(commit: Bool, text: String? = nil) {
        guard let field = textField else { return }
        let typed = text ?? field.currentEditor()?.string ?? field.stringValue
        Diag.log(
            "text finish commit=\(commit) explicit=\(text != nil) chars=\(typed.count) active=\(session.active?.tool.rawValue ?? "nil") strokes=\(session.strokes.count)"
        )
        textField = nil
        field.removeFromSuperview()

        guard session.active?.tool == .text else {
            needsDisplay = true
            return
        }

        if commit, !typed.isEmpty {
            let size = (typed as NSString).size(withAttributes: [.font: Self.textFont])
            session.setActiveText(typed, size: size)
            session.commit()
            if let committed = session.strokes.last {
                committedBounds[committed.id] = committed.bounds
                onCommit?(committed)
            }
        } else {
            session.undo()
        }

        window?.makeFirstResponder(self)
        needsDisplay = true
        Diag.log("text editing finished commit=\(commit) strokes=\(session.strokes.count)")
    }

    // MARK: - Laser

    private func startLaserTimer() {
        guard laserTimer == nil else { return }
        laserTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            _ = self.session.pruneTransient(now: now)
            self.needsDisplay = true
            if !self.session.strokes.contains(where: { $0.tool.isTransient }) {
                self.stopLaserTimer()
            }
        }
    }

    private func stopLaserTimer() {
        laserTimer?.invalidate()
        laserTimer = nil
    }

    // MARK: - Cursor frame

    /// The frame is a mode, not a mark: it follows the pointer and is never
    /// captured as a drawing.
    /// One tracking tick from the controller's timer, used in pointer mode where
    /// the window ignores mouse events and therefore receives none.
    func followPointerFromScreen() {
        guard showsOnlyPointer, let window else { return }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        updatePointer(to: convert(windowPoint, from: nil))
    }

    func syncPointerFromScreen() {
        guard showsOnlyPointer, let window else {
            if pointerLocation != nil {
                pointerLocation = nil
                needsDisplay = true
            }
            return
        }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        updatePointer(to: convert(windowPoint, from: nil))
    }

    private func updatePointer(to point: CGPoint) {
        let previous = pointerLocation
        guard previous != point else { return }
        pointerLocation = point
        lastPointerChange = Date()
        var rect = pointerRect(around: point)
        if let previous { rect = rect.union(pointerRect(around: previous)) }
        setNeedsDisplay(rect)
    }

    private func pointerRect(around point: CGPoint) -> CGRect {
        let radius = state.pointerSize / 2 * Self.pointerGlowMultiplier + 12
        return CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    }

    /// Small rect covering the last input segment, so a drag never rebuilds the
    /// whole path of the mark in progress.
    private func dirtyRect(around point: CGPoint, other: CGPoint?) -> CGRect {
        let padding = state.tool == .highlighter ? 14.0 : 6.0
        var rect = CGRect(x: point.x, y: point.y, width: 0, height: 0)
        if let other {
            rect = rect.union(CGRect(x: other.x, y: other.y, width: 0, height: 0))
        }
        return rect.insetBy(dx: -padding, dy: -padding)
    }

    /// Milliseconds between the input event and the frame that paints it.
    private func notePaintLatency() {
        guard lastInputTimestamp > 0 else { return }
        let delta = (ProcessInfo.processInfo.systemUptime - lastInputTimestamp) * 1000
        Diag.log("paintDeltaMs=\(String(format: "%.1f", delta))")
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            if isSelectingArea {
                cancelAreaSelection()
                return
            }
            onEscape?()
            return
        }

        let characters = event.charactersIgnoringModifiers ?? ""

        if event.modifierFlags.contains(.command) {
            if characters.lowercased() == "z" {
                if event.modifierFlags.contains(.shift) {
                    if let onRedo {
                        onRedo()
                    } else {
                        session.redo()
                        needsDisplay = true
                    }
                } else if let onUndo {
                    onUndo()
                } else {
                    session.undo()
                    needsDisplay = true
                }
                return
            }
            super.keyDown(with: event)
            return
        }

        if let character = characters.first {
            switch ShortcutRouter.resolve(character) {
            case .tool(let tool):
                state.tool = tool
                return
            case .ink(let ink):
                state.ink = ink
                return
            case .none:
                break
            }
            if character.lowercased() == "s" {
                if event.modifierFlags.contains(.shift) {
                    beginAreaSelection()
                } else {
                    onCaptureRequest?(nil)
                }
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Drawing mode hint

    private var hintUntil: Date?
    private var hintMessage = ""

    /// Drawing mode is an invisible layer by design, so the first moment of the
    /// session needs a visible signal: a pill that names the way out.
    func showIntroHint() {
        showHint(
            "Drawing · esc to clear · \(HotkeyDefaults.pinDisplayName) pin · \(HotkeyDefaults.displayName) exit",
            seconds: 2.2
        )
    }

    /// Same pill, used for things the user must know without a dialog: a missing
    /// permission, for instance, must never interrupt what they are doing.
    func showHint(_ message: String, seconds: TimeInterval) {
        hintMessage = message
        hintUntil = Date().addingTimeInterval(seconds)
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.hintUntil = nil
            self?.needsDisplay = true
        }
        Diag.log("hint: \(message)")
    }

    /// A thick translucent band with a bright edge on both sides and a soft
    /// glow, the way the reference app reads on video. The pointer stays visible
    /// in the middle: nothing is hidden, only framed.
    private func drawCursorFrame(in context: CGContext) {
        // Pointer highlight is its own mode; it is never part of drawing.
        guard showsOnlyPointer, let point = pointerLocation else { return }

        let radius = state.pointerSize / 2
        let band = radius * Self.pointerBandRatio
        let alpha = idleAlpha
        let squircle = state.pointerShape == "squircle"

        if state.pointerGlow {
            let glowColours = [
                state.ink.cgColor(alpha: 0.26 * alpha),
                state.ink.cgColor(alpha: 0.10 * alpha),
                state.ink.cgColor(alpha: 0),
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: glowColours,
                locations: [0, 0.55, 1]
            ) {
                context.drawRadialGradient(
                    gradient,
                    startCenter: point,
                    startRadius: radius - band,
                    endCenter: point,
                    endRadius: radius * Self.pointerGlowMultiplier,
                    options: []
                )
            }
        }

        // Ring by construction: fill the outer shape with the band colour, then
        // punch the middle out. Even-odd on a rounded rect left the interior
        // painted, which read as a dark disc instead of a ring.
        context.saveGState()
        context.setFillColor(state.ink.cgColor(alpha: 0.55 * alpha))
        context.addPath(shapePath(centre: point, radius: radius, squircle: squircle))
        context.fillPath()
        context.setBlendMode(.clear)
        context.addPath(shapePath(centre: point, radius: radius - band, squircle: squircle))
        context.fillPath()
        context.restoreGState()

        // Bright edges on both boundaries.
        context.setStrokeColor(state.ink.cgColor(alpha: 0.95 * alpha))
        context.setLineWidth(2)
        context.addPath(shapePath(centre: point, radius: radius, squircle: squircle))
        context.strokePath()
        context.addPath(shapePath(centre: point, radius: radius - band, squircle: squircle))
        context.strokePath()
    }

    /// Fades the highlight down when the pointer has been still, so a shared
    /// screen is not permanently framed.
    private var idleAlpha: CGFloat {
        guard state.pointerFadeWhenIdle, showsOnlyPointer else { return 1 }
        let idle = Date().timeIntervalSince(lastPointerChange)
        guard idle > 1.2 else { return 1 }
        let progress = min(1, (idle - 1.2) / 0.8)
        return 1 - 0.75 * progress
    }

    private func shapePath(centre: CGPoint, radius: CGFloat, squircle: Bool) -> CGPath {
        let rect = CGRect(
            x: centre.x - radius,
            y: centre.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        guard squircle else {
            let path = CGMutablePath()
            path.addEllipse(in: rect)
            return path
        }
        let corner = radius * 0.62
        return CGPath(
            roundedRect: rect,
            cornerWidth: corner,
            cornerHeight: corner,
            transform: nil
        )
    }

    private func drawHint() {
        guard let until = hintUntil, Date() < until else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let text = hintMessage as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let padding = CGSize(width: 18, height: 10)
        let pill = CGRect(
            x: (bounds.midX - (textSize.width + padding.width * 2) / 2).rounded(),
            y: 28,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )

        context.setFillColor(CGColor(gray: 0, alpha: 0.74))
        context.addPath(
            CGPath(
                roundedRect: pill,
                cornerWidth: pill.height / 2,
                cornerHeight: pill.height / 2,
                transform: nil
            )
        )
        context.fillPath()

        text.draw(
            at: CGPoint(x: pill.minX + padding.width, y: pill.minY + padding.height),
            withAttributes: attributes
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if showsOnlyPointer {
            drawCursorFrame(in: context)
            return
        }

        let now = Date()
        for stroke in session.strokes where stroke.tool.isTransient {
            render(stroke, in: context, now: now)
        }

        for stroke in session.strokes where !stroke.tool.isTransient {
            let box = committedBounds[stroke.id] ?? {
                let computed = stroke.bounds
                committedBounds[stroke.id] = computed
                return computed
            }()
            guard box.intersects(dirtyRect) else { continue }
            render(stroke, in: context)
        }

        if let active = session.active {
            render(active, in: context)
        }

        notePaintLatency()

        drawDrawingFrame(in: context)
        drawSelection(in: context)
        drawHint()
    }

    /// A thin frame in the current ink marks every armed display for the whole
    /// drawing session, so it is always clear which screens will take a mark.
    private func drawDrawingFrame(in context: CGContext) {
        guard state.showArmedFrame else { return }
        let rect = bounds.insetBy(dx: 3, dy: 3)
        context.setStrokeColor(state.ink.cgColor(alpha: 0.45))
        context.setLineWidth(3)
        context.addPath(
            CGPath(
                roundedRect: rect,
                cornerWidth: 10,
                cornerHeight: 10,
                transform: nil
            )
        )
        context.strokePath()
    }

    private func render(_ stroke: Stroke, in context: CGContext, now: Date = Date()) {
        if stroke.tool == .text {
            drawText(stroke)
            return
        }
        if stroke.tool == .blur {
            drawBlur(stroke, in: context)
            return
        }
        MarkRenderer.draw(
            stroke: stroke,
            in: context,
            opacity: stroke.opacity(at: now, laserLifetime: session.laserLifetime)
        )
        if stroke.tool == .number {
            drawStepNumber(stroke)
        }
    }

    /// T5/S3, live blur: a blur mark shows the real screen content underneath,
    /// gaussian blurred, from the latest live frame. The frame is in display
    /// pixels while this view is in points, and `BlurEffect` works in image
    /// pixels with a bottom-left origin while this view is flipped, so the
    /// crop rect is converted and the image unmirrored inside the mark's
    /// rectangle — the same arrangement the capture compositor uses. With no
    /// frame yet (the first instants of a drag, or Screen Recording denied) a
    /// neutral translucent fill with a thin border still shows where the mark
    /// is, and nothing crashes or paints garbage.
    private func drawBlur(_ stroke: Stroke, in context: CGContext) {
        guard let first = stroke.points.first, let last = stroke.points.last else { return }
        let rect = PathBuilder.normalizedRect(from: first, to: last)
        guard rect.width > 0, rect.height > 0 else { return }

        if let frame = liveFrameSource?.frame(for: displayID), bounds.width > 0 {
            // Scale derived from the frame, never hardcoded: image pixels per point.
            let scale = CGFloat(frame.width) / max(bounds.width, 1)
            let pixelRect = CGRect(
                x: rect.minX * scale,
                // Bottom-left pixel origin under a top-left view origin.
                y: CGFloat(frame.height) - rect.maxY * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
            if let blurred = BlurEffect.crop(
                frame,
                pixelRect: pixelRect,
                radius: BlurEffect.defaultRadius * scale
            ) {
                // The crop may cover less than the full rect when the mark
                // reaches past the frame: draw it at the intersection, clipped
                // to the mark. The context is flipped for overlay space, so an
                // image drawn plainly would land upside down; unflip it inside
                // the rectangle.
                let landed = pixelRect.intersection(
                    CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
                )
                let viewRect = CGRect(
                    x: landed.minX / scale,
                    y: (CGFloat(frame.height) - landed.maxY) / scale,
                    width: landed.width / scale,
                    height: landed.height / scale
                )
                context.saveGState()
                context.clip(to: rect)
                context.translateBy(x: viewRect.minX, y: viewRect.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(blurred, in: CGRect(origin: .zero, size: viewRect.size))
                context.restoreGState()
                return
            }
        }

        // Fallback: no frame yet, or Screen Recording denied.
        context.saveGState()
        context.setFillColor(CGColor(gray: 0.5, alpha: 0.3))
        context.fill(rect)
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.7))
        context.setLineWidth(2)
        context.addRect(rect.insetBy(dx: 1, dy: 1))
        context.strokePath()
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.setLineWidth(1)
        context.addRect(rect.insetBy(dx: 2, dy: 2))
        context.strokePath()
        context.restoreGState()
    }

    private func drawText(_ stroke: Stroke) {
        guard let text = stroke.text, !text.isEmpty, let origin = stroke.points.first else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.textFont,
            .foregroundColor: NSColor(cgColor: stroke.ink.cgColor()) ?? .white,
        ]
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private func drawStepNumber(_ stroke: Stroke) {
        guard let number = stroke.stepNumber, let center = stroke.points.first else { return }

        let text = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: Self.numberColour(for: stroke.ink),
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            withAttributes: attributes
        )
    }

    static func numberColour(for ink: Ink) -> NSColor {
        switch ink {
        case .yellow, .white: .black
        default: .white
        }
    }
}

extension OverlayView: NSTextFieldDelegate {
    /// Return confirms the text mark, Escape cancels it without leaving drawing
    /// mode.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        Diag.log("text command \(selector) chars=\(textView.string.count)")
        if selector == #selector(NSResponder.insertNewline(_:)) {
            finishTextEditing(commit: true, text: textView.string)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            finishTextEditing(commit: false)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView
        // Clicking away confirms, the same as typing Return.
        finishTextEditing(commit: true, text: editor?.string)
    }
}
