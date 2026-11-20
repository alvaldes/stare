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
    /// Marks removed by the eraser, so the undo history can drop them too.
    var onErase: (([UUID]) -> Void)?
    /// M leaves drawing mode for the click-through pointer highlight.
    var onPointerToggle: (() -> Void)?

    static let textFont = NSFont.systemFont(ofSize: 20, weight: .regular)
    static let cursorFrameDiameter: CGFloat = 40
    private static let eraserRadius: CGFloat = 8

    private var textField: NSTextField?
    private var laserTimer: Timer?
    private var pointerLocation: CGPoint?
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
        updatePointer(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        guard state.showCursorFrame else { return }
        updatePointer(to: convert(event.locationInWindow, from: nil))
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
        cursorForTool.set()
    }

    func clear() {
        session.clear()
        committedBounds.removeAll()
        finishTextEditing(commit: false)
        stopLaserTimer()
        needsDisplay = true
    }

    /// Discards the mark being dragged, if any.
    @discardableResult
    func discardActiveMark() -> Bool {
        guard session.active != nil else { return false }
        session.undo()
        needsDisplay = true
        return true
    }

    /// Removes a specific committed mark, used by the global undo history.
    @discardableResult
    func removeMark(id: UUID) -> Bool {
        guard session.remove(id: id) else { return false }
        committedBounds.removeValue(forKey: id)
        needsDisplay = true
        return true
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

        switch state.tool {
        case .eraser:
            erase(at: point)
            return
        case .text:
            beginTextEditing(at: point)
            return
        default:
            break
        }

        session.begin(at: point, tool: state.tool, ink: state.ink)
        if state.tool.isTransient { startLaserTimer() }
        setNeedsDisplay(dirtyRect(around: point, other: nil))
    }

    override func mouseDragged(with event: NSEvent) {
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
    }

    // MARK: - Eraser

    private func erase(at point: CGPoint) {
        let removed = session.erase(at: point, radius: Self.eraserRadius)
        guard !removed.isEmpty else { return }
        for id in removed { committedBounds.removeValue(forKey: id) }
        onErase?(removed)
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

    /// Confirms or discards the text mark in progress. Empty text never becomes
    /// a mark: a stray click must not leave an invisible box behind.
    ///
    /// `typed` must come from the field editor while it is live: the cell behind
    /// an editing NSTextField is not guaranteed to hold the latest keystrokes.
    private func finishTextEditing(commit: Bool, text: String? = nil) {
        guard let field = textField else { return }
        let typed = text ?? field.currentEditor()?.string ?? field.stringValue
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
        guard let window else { return }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        updatePointer(to: convert(windowPoint, from: nil))
    }

    func syncPointerFromScreen() {
        guard state.showCursorFrame, let window else {
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
        var rect = pointerRect(around: point)
        if let previous { rect = rect.union(pointerRect(around: previous)) }
        setNeedsDisplay(rect)
    }

    private func pointerRect(around point: CGPoint) -> CGRect {
        let radius = Self.cursorFrameDiameter / 2 + 8
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
            onEscape?()
            return
        }

        let characters = event.charactersIgnoringModifiers ?? ""

        if event.modifierFlags.contains(.command) {
            if characters.lowercased() == "z" {
                if let onUndo {
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
            if let tool = ToolShortcut.tool(for: character) {
                state.tool = tool
                return
            }
            if let digit = character.wholeNumberValue, let ink = Ink.ink(forNumber: digit) {
                state.ink = ink
                return
            }
            if character.lowercased() == "m" {
                onPointerToggle?()
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Drawing mode hint

    private var hintUntil: Date?

    /// Drawing mode is an invisible layer by design, so the first moment of the
    /// session needs a visible signal: a pill that names the way out.
    func showIntroHint() {
        hintUntil = Date().addingTimeInterval(2.2)
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.hintUntil = nil
            self?.needsDisplay = true
        }
    }

    private func drawCursorFrame(in context: CGContext) {
        guard state.showCursorFrame, let point = pointerLocation else { return }
        let radius = Self.cursorFrameDiameter / 2
        context.setStrokeColor(state.ink.cgColor(alpha: 0.9))
        context.setLineWidth(3)
        context.addEllipse(
            in: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        context.strokePath()
    }

    private func drawHint() {
        guard let until = hintUntil, Date() < until else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let text = "Drawing · esc to clear · \(HotkeyDefaults.displayName) to exit" as NSString
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
        MarkRenderer.draw(
            stroke: stroke,
            in: context,
            opacity: stroke.opacity(at: now, laserLifetime: session.laserLifetime)
        )
        if stroke.tool == .number {
            drawStepNumber(stroke)
        }
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
