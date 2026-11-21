import AppKit
import StareCore

/// Draws one display's marks and turns mouse and keyboard input into a
/// `DrawingSession`. Coordinates are top-left origin, local to the display.
/// The whiteboard subclass swaps the coordinate origin for the page's pan
/// offset through the `panOffset` hook and paints its own background, so both
/// layers share one input path.
class OverlayView: NSView {
    let state: EditorState
    var session = DrawingSession()
    var onEscape: (() -> Void)?
    /// Reports a committed mark so the controller can undo across displays.
    /// Reports a committed mark so the controller can undo across displays.
    var onCommit: ((Stroke) -> Void)?
    /// Command-Z is global: the controller owns the undo history.
    var onUndo: (() -> Void)?
    /// Shift-Command-Z is global for the same reason.
    var onRedo: (() -> Void)?
    /// Marks removed by the eraser, so the undo history can drop them too.
    var onErase: (([UUID]) -> Void)?
    /// A committed transform of an existing mark (move, scale, rotate), so the
    /// global history records it in real order: one drag is one undo step.
    var onTransform: ((Stroke) -> Void)?
    /// A mark deleted with the cursor, so the global history can hand it to
    /// the owning display's redo stack.
    var onDelete: ((UUID) -> Void)?
    /// This view selected a mark: the controller clears the selection on every
    /// other display, so at most one mark is selected in the whole app.
    var onSelectionChanged: ((UUID) -> Void)?
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
    /// The whiteboard bridge: every session mutation is handed to the board so
    /// its pages stay authoritative. Nil in the plain overlay.
    var boardSink: ((DrawingSession) -> Void)?

    /// Page-space hook: view space minus this offset equals page space, so
    /// stroke points stored in page space keep their position on screen. Zero
    /// in the plain overlay, the current page's offset on the whiteboard.
    var panOffset: CGSize { .zero }

    /// Converts a view point into page space, the space stroke points live in.
    func pagePoint(_ viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: viewPoint.x + panOffset.width, y: viewPoint.y + panOffset.height)
    }

    /// Converts a page-space point back into view space.
    func viewPoint(fromPage point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - panOffset.width, y: point.y - panOffset.height)
    }

    /// Converts a page-space rect into view space, for dirty rectangles.
    func viewRect(fromPage rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -panOffset.width, dy: -panOffset.height)
    }

    /// Notifies the whiteboard bridge that the session changed.
    func noteSessionChanged() {
        boardSink?(session)
    }

    static let textFont = NSFont.systemFont(ofSize: 20, weight: .regular)
    /// The pointer highlight is a thick translucent band with bright edges and a
    /// soft glow, sized from preferences.
    static let pointerGlowMultiplier: CGFloat = 1.9
    static let pointerBandRatio: CGFloat = 0.26
    private static let eraserRadius: CGFloat = 8

    private var textField: NSTextField?
    private var laserTimer: Timer?
    private var pointerLocation: CGPoint?
    /// Current scale of the click pulse, shared by every display and pushed
    /// in by the controller's timer. 1 whenever nobody clicked.
    private var pointerPulseScale: CGFloat = 1
    private var isSelectingArea = false
    private var selectionOrigin: CGPoint?
    private var selectionRect: CGRect?
    private var lastPointerChange = Date()
    /// Pointer mode paints only the highlight: no marks, no frame, no hint.
    var showsOnlyPointer = false {
        didSet { needsDisplay = true }
    }

    /// Bounds of committed marks, computed once, so a redraw never rebuilds a
    /// path just to decide whether a stroke is visible. Page space, so the
    /// whiteboard clears it when the presented page changes. Rotated marks
    /// store their rotated bounds, which is what culling needs.
    var committedBounds: [UUID: CGRect] = [:]
    private var lastDragPoint: CGPoint?
    private var lastStraight = false
    private var lastInputTimestamp: TimeInterval = 0

    // MARK: - Mark selection (T11/S6)

    /// The mark this view has selected, if any. At most one mark is selected
    /// per app: selecting reports through `onSelectionChanged` so the
    /// controller clears the selection on every other display.
    private(set) var selectedMarkID: UUID?
    /// The drag in progress on the selected mark. Every frame transforms the
    /// untouched snapshot into a preview; the session is journalled exactly
    /// once, on mouse up, so one drag is one undo step.
    private var selectionDrag: SelectionDrag?
    /// Untouched drag-start snapshot the preview is transformed from.
    private var selectionOriginal: Stroke?
    /// The transformed mark drawn live on top during a drag.
    private var selectionPreview: Stroke?

    /// What a drag on the selected mark does. The handle decides: the body
    /// moves, a corner resizes uniformly, the knob rotates. The shape never
    /// changes — that is `MarkTransform`'s contract.
    private enum SelectionDrag {
        case move(start: CGPoint)
        case scale(handle: MarkHandle)
        case rotate(startAngle: CGFloat)
    }

    /// Extra reach when grabbing a mark with the cursor, so a click near a
    /// mark selects instead of missing.
    static let selectionHitRadius: CGFloat = 10

    /// Gives the selection up: no handles remain and no stale id survives a
    /// page change or a clear.
    func clearSelection() {
        guard selectedMarkID != nil || selectionDrag != nil || selectionOriginal != nil
            || selectionPreview != nil else { return }
        selectedMarkID = nil
        selectionDrag = nil
        selectionOriginal = nil
        selectionPreview = nil
        needsDisplay = true
    }

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

    /// Each tool shouts what it does: text wants an I-beam, the edit cursor
    /// wants an arrow, drawing tools want a crosshair.
    private var cursorForTool: NSCursor {
        switch state.tool {
        case .text: .iBeam
        case .select: .arrow
        default: .crosshair
        }
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
        setNeedsDisplay(pointerRect(around: previous, scale: pointerPulseScale))
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
        clearSelection()
        finishTextEditing(commit: false)
        stopLaserTimer()
        noteBlurInterestChanged()
        noteSessionChanged()
        needsDisplay = true
    }

    /// Discards the mark being dragged, if any.
    @discardableResult
    func discardActiveMark() -> Bool {
        guard session.active != nil else { return false }
        session.undo()
        noteBlurInterestChanged()
        noteSessionChanged()
        needsDisplay = true
        return true
    }

    /// Puts back the mark the global history undid on this display. The redo
    /// journal answers by id, so a transform undone here reapplies too — the
    /// old guard on `undoneStrokes` could not see transform entries.
    @discardableResult
    func redoMark(id: UUID) -> Bool {
        guard session.canRedo(markWithID: id), session.redo() else { return false }
        committedBounds.removeValue(forKey: id)
        noteBlurInterestChanged()
        noteSessionChanged()
        needsDisplay = true
        return true
    }

    /// Reverses the newest change to the mark with this id, used by the global
    /// undo history: a draw goes away, a transform restores its geometry. The
    /// guard keeps the global order and the session's journal from drifting —
    /// the controller only pops an entry when the session agrees it is next.
    @discardableResult
    func undoMark(id: UUID) -> Bool {
        guard session.canUndo(markWithID: id), session.undo() else { return false }
        if let selected = selectedMarkID, !session.strokes.contains(where: { $0.id == selected }) {
            clearSelection()
        }
        committedBounds.removeValue(forKey: id)
        noteBlurInterestChanged()
        noteSessionChanged()
        needsDisplay = true
        return true
    }

    /// ⌫ with a selection: the mark goes away through `remove(id:)`, so the
    /// session's redo journal holds it and the global history can restore it.
    @discardableResult
    func deleteSelectedMark() -> Bool {
        guard let id = selectedMarkID,
              session.strokes.contains(where: { $0.id == id }),
              session.remove(id: id) else { return false }
        clearSelection()
        committedBounds.removeValue(forKey: id)
        onDelete?(id)
        noteBlurInterestChanged()
        noteSessionChanged()
        needsDisplay = true
        Diag.log("delete mark id=\(id)")
        return true
    }

    /// Removes a specific committed mark, used by the global undo history.
    @discardableResult
    func removeMark(id: UUID) -> Bool {
        guard session.remove(id: id) else { return false }
        committedBounds.removeValue(forKey: id)
        noteBlurInterestChanged()
        noteSessionChanged()
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
    /// change anything else, so canvases without blur marks never redraw. The
    /// invalidation uses the rotated bounding box: a rotated blur patch draws
    /// outside its unrotated one, and repaintng only `bounds` would tear it.
    func invalidateLiveBlurMarks() {
        guard hasLiveBlurMarks else { return }
        for stroke in session.strokes where stroke.tool == .blur {
            setNeedsDisplay(stroke.displayBounds)
        }
        if let active = session.active, active.tool == .blur {
            setNeedsDisplay(active.displayBounds)
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
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = pagePoint(viewPoint)
        lastDragPoint = point
        lastStraight = false
        lastInputTimestamp = event.timestamp
        Diag.log("mouseDown \(Int(point.x)),\(Int(point.y)) tool=\(state.tool.rawValue)")

        if isSelectingArea {
            selectionOrigin = viewPoint
            selectionRect = CGRect(origin: viewPoint, size: .zero)
            needsDisplay = true
            return
        }

        switch state.tool {
        case .eraser:
            finishPendingTextEditing()
            erase(at: point)
            return
        case .text:
            beginTextEditing(at: point, viewPoint: viewPoint)
            return
        case .select:
            finishPendingTextEditing()
            beginSelection(at: point)
            return
        default:
            // A mark of another tool must not leave a text editor behind: it
            // would keep its field as a subview and swallow what is underneath.
            finishPendingTextEditing()
        }

        session.begin(at: point, tool: state.tool, ink: state.ink)
        if state.tool.isTransient { startLaserTimer() }
        noteBlurInterestChanged()
        noteSessionChanged()
        setNeedsDisplay(dirtyRect(around: viewPoint, other: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        if isSelectingArea {
            let point = convert(event.locationInWindow, from: nil)
            guard let origin = selectionOrigin else { return }
            selectionRect = PathBuilder.normalizedRect(from: origin, to: point)
            needsDisplay = true
            return
        }

        // Editing an existing mark: the handle decides, the preview follows.
        if state.tool == .select, selectionDrag != nil {
            updateSelectionPreview(at: pagePoint(convert(event.locationInWindow, from: nil)))
            return
        }

        if state.tool == .eraser {
            let viewPoint = convert(event.locationInWindow, from: nil)
            lastDragPoint = pagePoint(viewPoint)
            erase(at: lastDragPoint ?? .zero)
            return
        }

        let shift = event.modifierFlags.contains(.shift)
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = adjusted(pagePoint(viewPoint), shift: shift)
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
            let union = previousShapeBounds.union(currentShapeBounds).insetBy(dx: -4, dy: -4)
            setNeedsDisplay(viewRect(fromPage: union))
        } else if state.tool.usesEndpointsOnly || straight != lastStraight {
            lastStraight = straight
            needsDisplay = true
        } else {
            setNeedsDisplay(dirtyRect(around: viewPoint, other: previousPoint.map(viewPoint(fromPage:))))
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

        // Editing a mark: the pointer's final position is applied before the
        // preview is journalled exactly once, so one drag is one undo step,
        // never one per mouse event.
        if state.tool == .select {
            updateSelectionPreview(at: pagePoint(convert(event.locationInWindow, from: nil)))
            commitSelectionDrag()
            return
        }

        // Click tools are committed by their own path: numbered steps when
        // placed, text when the editor confirms. Committing here would close the
        // text mark the click just opened.
        guard !state.tool.isClickTool else { return }

        let shift = event.modifierFlags.contains(.shift)
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = adjusted(pagePoint(viewPoint), shift: shift)
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
        noteSessionChanged()
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

    // MARK: - Editing marks (T11/S6)

    /// A click with the edit cursor: a handle of the already selected mark
    /// wins, then the topmost mark under the pointer (newest first), then the
    /// selection is given up. A click that lands on a mark arms its drag right
    /// away, so select-and-move is one gesture.
    private func beginSelection(at point: CGPoint) {
        if let id = selectedMarkID, let selected = session.strokes.first(where: { $0.id == id }) {
            if let handle = MarkSelection(stroke: selected).handle(at: point) {
                startSelectionDrag(handle, on: selected, at: point)
                return
            }
        }

        guard let hit = session.strokes.last(where: {
            $0.isSelectedByCursor(at: point, radius: Self.selectionHitRadius)
        }) else {
            clearSelection()
            return
        }
        if selectedMarkID != hit.id {
            selectedMarkID = hit.id
            onSelectionChanged?(hit.id)
        }
        let handle = MarkSelection(stroke: hit).handle(at: point) ?? .body
        startSelectionDrag(handle, on: hit, at: point)
    }

    /// Arms the drag the grabbed handle asks for. The mark's untouched
    /// snapshot is kept: every preview frame transforms it from scratch, which
    /// is what makes a drag idempotent.
    private func startSelectionDrag(_ handle: MarkHandle, on stroke: Stroke, at point: CGPoint) {
        selectionOriginal = stroke
        selectionPreview = nil
        switch handle {
        case .body:
            selectionDrag = .move(start: point)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            selectionDrag = .scale(handle: handle)
        case .rotation:
            let anchor = stroke.anchor
            selectionDrag = .rotate(startAngle: atan2(point.y - anchor.y, point.x - anchor.x))
        }
    }

    /// One preview frame from the untouched snapshot.
    private func updateSelectionPreview(at point: CGPoint) {
        guard let drag = selectionDrag, let original = selectionOriginal else { return }
        switch drag {
        case let .move(start):
            selectionPreview = MarkTransform.translated(
                original,
                by: CGPoint(x: point.x - start.x, y: point.y - start.y)
            )
        case let .scale(handle):
            selectionPreview = MarkTransform.scaled(original, dragging: handle, to: point)
        case let .rotate(startAngle):
            let anchor = original.anchor
            let angle = atan2(point.y - anchor.y, point.x - anchor.x) - startAngle
            selectionPreview = MarkTransform.rotated(original, by: angle)
        }
        needsDisplay = true
    }

    /// Ends the drag: the preview replaces the committed mark exactly once, so
    /// the global history sees one transform, not one per mouse event.
    private func commitSelectionDrag() {
        defer {
            selectionDrag = nil
            selectionOriginal = nil
            selectionPreview = nil
            needsDisplay = true
        }
        guard let preview = selectionPreview, let original = selectionOriginal,
              preview != original, session.replace(preview) else {
            if selectionPreview != nil && session.strokes.first(where: { $0.id == selectedMarkID }) == nil {
                clearSelection()
            }
            return
        }
        committedBounds[preview.id] = preview.displayBounds
        onTransform?(preview)
        noteBlurInterestChanged()
        noteSessionChanged()
        Diag.log("transform \(preview.tool.rawValue) rotation=\(preview.rotation)")
    }

    /// Applies the mark's rotation about its anchor to a branch that draws its
    /// own geometry, the same rule the capture compositor uses.
    private func withMarkRotation(_ stroke: Stroke, in context: CGContext, _ body: () -> Void) {
        guard stroke.rotation != 0 else {
            body()
            return
        }
        context.saveGState()
        context.concatenate(Stroke.rotationTransform(around: stroke.anchor, by: stroke.rotation))
        body()
        context.restoreGState()
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
        noteSessionChanged()
        Diag.log("erase count=\(removed.count) remaining=\(session.strokes.count)")
        needsDisplay = true
    }

    // MARK: - Text

    private func beginTextEditing(at pagePoint: CGPoint, viewPoint: CGPoint) {
        finishTextEditing(commit: true)
        session.begin(at: pagePoint, tool: .text, ink: state.ink)

        let field = NSTextField(frame: CGRect(x: viewPoint.x, y: viewPoint.y, width: 320, height: 30))
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
        noteSessionChanged()
        Diag.log("text editing finished commit=\(commit) strokes=\(session.strokes.count)")
    }

    // MARK: - Laser

    private func startLaserTimer() {
        guard laserTimer == nil else { return }
        laserTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            if self.session.pruneTransient(now: now) {
                self.noteSessionChanged()
            }
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
    /// the window ignores mouse events and therefore receives none. `pulseScale`
    /// is the click pulse multiplier the controller computes for every display.
    func followPointerFromScreen(pulseScale: CGFloat = 1) {
        guard showsOnlyPointer, let window else { return }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        followPointer(at: convert(windowPoint, from: nil), pulseScale: pulseScale)
    }

    /// One tick with a known view point: the same pointer update the
    /// screen-following tick ends in, used where the pointer location comes
    /// from somewhere other than the mouse (the self test).
    func followPointer(at point: CGPoint, pulseScale: CGFloat = 1) {
        updatePointer(to: point, pulseScale: pulseScale)
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
        updatePointer(to: convert(windowPoint, from: nil), pulseScale: pointerPulseScale)
    }

    private func updatePointer(to point: CGPoint, pulseScale: CGFloat) {
        let previous = pointerLocation
        let previousScale = pointerPulseScale
        guard previous != point || previousScale != pulseScale else { return }
        pointerLocation = point
        pointerPulseScale = pulseScale
        // The pulse must not reset the idle fade: only movement does.
        if previous != point { lastPointerChange = Date() }
        // The pulse grows and settles even while the pointer stands still, so
        // both the previous and the current highlight area are invalidated.
        var rect = pointerRect(around: point, scale: pulseScale)
        if let previous {
            rect = rect.union(pointerRect(around: previous, scale: previousScale))
        }
        setNeedsDisplay(rect)
    }

    private func pointerRect(around point: CGPoint, scale: CGFloat = 1) -> CGRect {
        let radius = state.pointerSize / 2 * scale * Self.pointerGlowMultiplier + 12
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
            // With a mark selected, Escape first gives the selection up instead
            // of leaving drawing mode, so one stray click never costs the session.
            if selectedMarkID != nil {
                clearSelection()
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
                        noteSessionChanged()
                        needsDisplay = true
                    }
                } else if let onUndo {
                    onUndo()
                } else {
                    session.undo()
                    noteSessionChanged()
                    needsDisplay = true
                }
                return
            }
            super.keyDown(with: event)
            return
        }

        // ⌫ / Delete with the cursor: the selected mark goes away through the
        // session, so the global history sees the deletion like any other edit.
        if state.tool == .select, event.keyCode == 51 || event.keyCode == 117 {
            deleteSelectedMark()
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

        // The pulse scales the whole highlight — ring, glow, band and shape
        // — from one radius, so pointerSize, both shapes and the glow keep
        // their proportions and a resting highlight (scale 1) is unchanged.
        let radius = state.pointerSize / 2 * pointerPulseScale
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

        drawBackground(in: context)
        drawMarks(in: context, dirty: dirtyRect)

        notePaintLatency()

        drawDrawingFrame(in: context)
        drawSelection(in: context)
        drawSelectedMarkChrome(in: context)
        drawHint()
    }

    /// The layer under the marks. Empty in the transparent overlay; the
    /// whiteboard paints the current page's solid background here.
    func drawBackground(in context: CGContext) {}

    /// Every mark on the layer, in page space, translated by the pan offset.
    /// `dirtyRect` is in view space; the context is shifted so page-space
    /// points land where the user sees them, which is what makes panning and
    /// display changes never move stored marks.
    func drawMarks(in context: CGContext, dirty dirtyRect: NSRect) {
        let pageDirty = dirtyRect.offsetBy(dx: panOffset.width, dy: panOffset.height)
        context.saveGState()
        context.translateBy(x: -panOffset.width, y: -panOffset.height)
        let now = Date()
        for stroke in session.strokes where stroke.tool.isTransient {
            render(stroke, in: context, now: now)
        }

        for stroke in session.strokes where !stroke.tool.isTransient {
            // The live preview of a transform takes over: the mark is drawn
            // transformed on top instead of both versions at once.
            if let preview = selectionPreview, stroke.id == preview.id { continue }
            let box = committedBounds[stroke.id] ?? {
                let computed = stroke.displayBounds
                committedBounds[stroke.id] = computed
                return computed
            }()
            guard box.intersects(pageDirty) else { continue }
            render(stroke, in: context)
        }

        if let active = session.active {
            render(active, in: context)
        }
        if let preview = selectionPreview {
            render(preview, in: context)
        }
        context.restoreGState()
    }

    /// The selection chrome over the selected mark: a dashed box, four corner
    /// squares and the rotation knob, following the mark as it now looks
    /// (preview included). View chrome only — it never enters the session, so
    /// a capture never contains it and `committedBounds` never grows for it.
    private func drawSelectedMarkChrome(in context: CGContext) {
        guard state.tool == .select, let id = selectedMarkID else { return }
        guard let stroke = selectionPreview ?? session.strokes.first(where: { $0.id == id }) else { return }

        let selection = MarkSelection(stroke: stroke)
        let accent = CGColor(srgbRed: 0.25, green: 0.55, blue: 1, alpha: 1)

        context.saveGState()
        // Chrome geometry is page space, the same space the marks live in.
        context.translateBy(x: -panOffset.width, y: -panOffset.height)

        context.saveGState()
        context.concatenate(
            Stroke.rotationTransform(around: selection.anchor, by: selection.rotation)
        )
        context.setStrokeColor(accent)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.addRect(selection.unrotatedBounds)
        context.strokePath()
        context.restoreGState()

        for (handle, point) in selection.handlePoints(
            rotationHandleOffset: MarkSelection.defaultRotationHandleOffset
        ) {
            if handle == .rotation {
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                context.setStrokeColor(accent)
                context.setLineWidth(1.5)
                context.addEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                context.strokePath()
            } else {
                let square = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(square)
                context.setStrokeColor(accent)
                context.setLineWidth(1.5)
                context.stroke(square)
            }
        }
        context.restoreGState()
    }

    /// A thin frame in the current ink marks every armed display for the whole
    /// drawing session, so it is always clear which screens will take a mark.
    func drawDrawingFrame(in context: CGContext) {
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
            withMarkRotation(stroke, in: context) { drawText(stroke) }
            return
        }
        if stroke.tool == .blur {
            withMarkRotation(stroke, in: context) { drawBlur(stroke, in: context) }
            return
        }
        MarkRenderer.draw(
            stroke: stroke,
            in: context,
            opacity: stroke.opacity(at: now, laserLifetime: session.laserLifetime)
        )
        if stroke.tool == .number {
            withMarkRotation(stroke, in: context) { drawStepNumber(stroke) }
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
            .font: Self.textFont(for: stroke),
            .foregroundColor: NSColor(cgColor: stroke.ink.cgColor()) ?? .white,
        ]
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    /// The stroke's own `textSize` sets the font size (matching the capture
    /// compositor's rule): a scaled mark renders at the size its scaled box
    /// describes, and an unscaled mark measures back out to the editing font.
    static func textFont(for stroke: Stroke) -> NSFont {
        let base = OverlayStyle.textSize
        guard let text = stroke.text, !text.isEmpty,
              let size = stroke.textSize, size.width > 0
        else { return textFont }
        let width = (text as NSString).size(withAttributes: [.font: textFont]).width
        guard width > 0.001 else { return textFont }
        return NSFont.systemFont(ofSize: base * size.width / width, weight: .regular)
    }

    private func drawStepNumber(_ stroke: Stroke) {
        guard let number = stroke.stepNumber, let center = stroke.points.first else { return }

        let text = "\(number)" as NSString
        // The digit scales with the badge it sits on (advisory A).
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15 * stroke.badgeScale, weight: .semibold),
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
