import AppKit
import StareCore

/// Draws one display's marks and turns mouse and keyboard input into a
/// `DrawingSession`. Coordinates are top-left origin, local to the display.
/// The whiteboard subclass swaps the coordinate origin for the page's pan
/// offset through the `panOffset` hook and paints its own background, so both
/// layers share one input path.
class OverlayView: NSView {
    let state: EditorState
    /// The session is also *replaced* whole (the boot-scoped restore on
    /// re-entry and after a relaunch, `OverlayController.restoreDrawingSessions`),
    /// and that path bypasses every incremental mutation below that calls
    /// `noteBlurInterestChanged` explicitly. The observer is the one funnel that
    /// cannot miss a restore: any new session — restored, cleared, page-swapped
    /// — re-reports blur interest here, so a restored blur mark starts capturing
    /// frames again instead of painting the neutral fallback.
    var session = DrawingSession() {
        didSet { noteBlurInterestChanged() }
    }
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
    /// A committed group move (T6b/S8): every mark of a multi-selection moved
    /// together in one drag. The session journalled the batch, so the global
    /// history records it as ONE entry — one ⌘Z returns every mark, ⇧⌘Z moves
    /// them again.
    var onBatchTransform: (([Stroke]) -> Void)?
    /// A mark deleted with the cursor, so the global history can hand it to
    /// the owning display's redo stack.
    var onDelete: ((UUID) -> Void)?
    /// Escape with nothing selected: clears this layer's marks (the whiteboard's
    /// current page) and stays in drawing mode. The clear goes into the global
    /// history as one undoable step (T4/S5), so the controller routes it and
    /// a later Command-Z can restore everything it removed.
    var onClearMarks: (() -> Void)?
    /// This view selected a mark: the controller clears the selection on every
    /// other display, so at most one mark is selected in the whole app.
    var onSelectionChanged: ((UUID) -> Void)?
    /// Asks for a capture: nil means the whole display, a rect means that area.
    var onCaptureRequest: ((CGRect?) -> Void)?
    /// Asks to capture the front window only, the mark space of this display
    /// included. Separate from `onCaptureRequest` because the target is not a
    /// rectangle the user dragged: it is whatever window the server puts first.
    var onCaptureWindowRequest: (() -> Void)?
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

    /// The page this display's edits belong to in the global history: nil on
    /// the plain overlay, which has no pages. The whiteboard's current page
    /// index rides on the clear and batch-move entries (T4/S5, T6b/S8), so
    /// undo and redo reach the page the change happened on instead of
    /// whichever page the display happens to present when the entry pops.
    var historyPage: Int? { nil }

    /// Page-space hook: view space minus this offset equals page space, so
    /// stroke points stored in page space keep their position on screen. Zero
    /// in the plain overlay, the current page's offset on the whiteboard.
    var panOffset: CGSize { .zero }

    /// Page-space hook: 1 everywhere but the whiteboard, which shows the
    /// current page's zoom (T5/S5).
    var zoom: CGFloat { 1 }

    /// The one mapping between page space and view space this layer draws
    /// with: `view = (page − offset) × zoom`, straight from StareCore — the
    /// arithmetic never spreads through the view.
    var viewTransform: BoardTransform {
        BoardTransform(offset: panOffset, zoom: zoom)
    }

    /// Converts a view point into page space, the space stroke points live in.
    func pagePoint(_ viewPoint: CGPoint) -> CGPoint {
        viewTransform.point(toPage: viewPoint)
    }

    /// Converts a page-space point back into view space.
    func viewPoint(fromPage point: CGPoint) -> CGPoint {
        viewTransform.point(fromPage: point)
    }

    /// Converts a page-space rect into view space, for dirty rectangles.
    func viewRect(fromPage rect: CGRect) -> CGRect {
        viewTransform.rect(fromPage: rect)
    }

    /// Converts a view rect into page space — what a screen region covers in
    /// page space, for culling and the dot grid.
    func pageRect(fromView rect: CGRect) -> CGRect {
        viewTransform.rect(toPage: rect)
    }

    /// Notifies the whiteboard bridge that the session changed.
    func noteSessionChanged() {
        boardSink?(session)
    }

    /// Reports a committed batch transform (T6b/S8). A hook rather than the
    /// property itself so the whiteboard can record the page the move
    /// happened on before the report leaves; the base path is exactly the
    /// controller's wiring call.
    func noteBatchCommitted(_ strokes: [Stroke]) {
        onBatchTransform?(strokes)
    }

    static let textFont = NSFont.systemFont(ofSize: 20, weight: .regular)
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

    /// The marks this view has selected, primary first. One mark from a plain
    /// click; the array grows when a marquee (T6/S8) selects several or ⇧
    /// adds one. `selectedMarkID` stays the primary the single-mark chrome and
    /// the drag act on; when the array holds several, the chrome draws only
    /// each mark's box and drags still address the primary alone.
    private(set) var selectedMarkIDs: [UUID] = []

    /// The primary selected mark, if any. At most one display holds a selection
    /// in the whole app: selecting reports through `onSelectionChanged` so the
    /// controller clears the selection on every other display.
    var selectedMarkID: UUID? { selectedMarkIDs.first }
    /// The drag in progress on the selected mark. Every frame transforms the
    /// untouched snapshot into a preview; the session is journalled exactly
    /// once, on mouse up, so one drag is one undo step.
    private var selectionDrag: SelectionDrag?

    /// The marquee drag (T6/S8): a select-tool drag that began on empty canvas
    /// selects every mark it intersects when it ends. The origin and the live
    /// rect are view space; `marqueeAdditive` remembers ⇧ at drag start. Nil
    /// origin means no marquee runs and the rect never draws.
    private var marqueeOrigin: CGPoint?
    private var marqueeRect: CGRect?
    private var marqueeAdditive = false
    /// Untouched drag-start snapshot the preview is transformed from.
    private var selectionOriginal: Stroke?
    /// The transformed mark drawn live on top during a drag.
    private var selectionPreview: Stroke?
    /// Group move (T6b/S8): the untouched snapshots of every selected mark,
    /// non-empty only while a group move drag runs on a multi-selection. Each
    /// frame translates them all by the same delta; the session is journalled
    /// exactly once, as one batch, on mouse up.
    private var groupOriginals: [Stroke] = []
    /// The translated previews matching `groupOriginals`, same order.
    private var groupPreviews: [Stroke] = []

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
        guard !selectedMarkIDs.isEmpty || selectionDrag != nil || selectionOriginal != nil
            || selectionPreview != nil || marqueeOrigin != nil else { return }
        selectedMarkIDs = []
        selectionDrag = nil
        selectionOriginal = nil
        selectionPreview = nil
        groupOriginals = []
        groupPreviews = []
        marqueeOrigin = nil
        marqueeRect = nil
        marqueeAdditive = false
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
        reassertCursor()
    }

    /// The cursor an active canvas gesture (pan, zoom) shows instead of the
    /// tool cursor (S3). Nil in the plain overlay and whenever no gesture
    /// runs; the board view sets it at gesture start and clears it on every
    /// exit path (drag end, space release, scroll end, view disappearing).
    /// While set, every cursor re-assertion below shows it, so moving the
    /// pointer mid-gesture never flashes the tool cursor back.
    var gestureCursor: NSCursor? { nil }

    /// The cursor this layer shows right now: the gesture cursor while a
    /// gesture runs, the tool cursor otherwise.
    func reassertCursor() {
        (gestureCursor ?? cursorForTool).set()
    }

    /// Each tool shouts what it does (T2/S2): the pure per-tool choice is
    /// `Tool.cursor` in StareCore; this serves the matching `NSCursor`.
    private var cursorForTool: NSCursor {
        Self.cursor(for: state.tool.cursor)
    }

    /// The role → `NSCursor` mapping, `internal` so the self test exercises
    /// the real path the canvas shows. System cursors where one genuinely
    /// does the tool's job: the arrow for the edit cursor, the I-beam for
    /// text, the pointing hand for the click-to-place numbered badge, and the
    /// crosshair — the drafting cursor — for the straight line alone. Every
    /// other role is a small glyph drawn here, centred on the hotspot: a
    /// white core over a dark outline reads on light and on dark canvases,
    /// and no new asset files exist. The glyph for each role is schematic —
    /// it says the tool's shape, not the toolbar's exact SF Symbol — which is
    /// the documented "dentro de lo posible" trade (see `ToolCursor`).
    static func cursor(for role: ToolCursor) -> NSCursor {
        switch role {
        case .editArrow: .arrow
        case .textIBeam: .iBeam
        case .numberHand: .pointingHand
        case .lineCrosshair: .crosshair
        case .penNib: glyphCursors[role] ?? .crosshair
        case .markerChisel: glyphCursors[role] ?? .crosshair
        case .arrowHead: glyphCursors[role] ?? .crosshair
        case .rectangleFrame: glyphCursors[role] ?? .crosshair
        case .ellipseRing: glyphCursors[role] ?? .crosshair
        case .laserSpark: glyphCursors[role] ?? .crosshair
        case .eraserBlock: glyphCursors[role] ?? .crosshair
        case .blurDots: glyphCursors[role] ?? .crosshair
        }
    }

    /// The drawn cursors, built once. The fallback is unreachable: the
    /// dictionary covers every glyph role the switch above asks for.
    private static let glyphCursors: [ToolCursor: NSCursor] = {
        var cursors: [ToolCursor: NSCursor] = [:]
        for role in ToolCursor.allCases {
            let cursor = ToolGlyphCursor.cursor(for: role)
            if let cursor { cursors[role] = cursor }
        }
        return cursors
    }()

    override func mouseEntered(with event: NSEvent) {
        reassertCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        // Re-assert the cursor on every move: cursor rectangles only fire
        // when the pointer crosses a boundary, which is why the cursor used to
        // change only after jumping to another display. A gesture cursor (S3)
        // wins while it is set.
        reassertCursor()
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
        reassertCursor()
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

    /// The Escape clear (T4/S5): the whole layer goes as ONE undoable step of
    /// the global history — the session journals the batch, so a later
    /// Command-Z restores the exact marks and Shift-Command-Z clears them
    /// again. An empty layer reports false and adds no history step.
    @discardableResult
    func clearForUndo() -> Bool {
        let removedAny = session.clearForUndo()
        committedBounds.removeAll()
        clearSelection()
        finishTextEditing(commit: false)
        stopLaserTimer()
        noteBlurInterestChanged()
        noteSessionChanged()
        needsDisplay = true
        return removedAny
    }

    /// Drops selected ids that are no longer in the session, keeping the
    /// primary consistent — a history jump or an erase must not leave handles
    /// pointing at marks that are gone. A still-live selection just shrinks.
    private func pruneSelection() {
        let live = Set(session.strokes.map(\.id))
        let kept = selectedMarkIDs.filter { live.contains($0) }
        guard kept != selectedMarkIDs else { return }
        selectedMarkIDs = kept
        needsDisplay = true
    }

    /// Restores a selection snapshot taken before a page-routed history op
    /// borrowed another page's session (T4/S5, T6b/S8): the presented page's
    /// selection must survive the borrow untouched, and the setter is kept
    /// controllable here instead of being opened up wholesale.
    func restoreSelection(_ ids: [UUID]) {
        selectedMarkIDs = ids
    }

    /// Global undo of the Escape clear (T4/S5): the batch the clear removed
    /// comes back exactly as it was. The guard keeps the global order and the
    /// session's journal from drifting — a popped clear entry can never undo
    /// a different change than the one it names.
    @discardableResult
    func undoClearedMarks() -> Bool {
        guard session.canUndoClear, session.undo() else { return false }
        pruneSelection()
        noteBlurInterestChanged()
        noteSessionChanged()
        needsDisplay = true
        return true
    }

    /// Global redo of the Escape clear (T4/S5): the restored batch goes away
    /// again, with the same session agreement as the undo side.
    @discardableResult
    func redoClearedMarks() -> Bool {
        guard session.canRedoClear, session.redo() else { return false }
        noteBlurInterestChanged()
        noteSessionChanged()
        needsDisplay = true
        return true
    }

    /// Global undo of the group move (T6b/S8): the batch the drag moved comes
    /// back in one step. The guard keeps the global order and the session's
    /// journal from drifting — a popped batch entry can never undo a different
    /// change than the one it names, just like the clear entry above.
    @discardableResult
    func undoBatchMove() -> Bool {
        guard session.canUndoBatchMove, session.undo() else { return false }
        pruneSelection()
        committedBounds.removeAll()
        noteBlurInterestChanged()
        noteSessionChanged()
        needsDisplay = true
        return true
    }

    /// Global redo of the group move (T6b/S8): the undone batch moves again,
    /// with the same session agreement as the undo side.
    @discardableResult
    func redoBatchMove() -> Bool {
        guard session.canRedoBatchMove, session.redo() else { return false }
        committedBounds.removeAll()
        noteBlurInterestChanged()
        noteSessionChanged()
        needsDisplay = true
        return true
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
        pruneSelection()
        committedBounds.removeValue(forKey: id)
        noteBlurInterestChanged()
        noteSessionChanged()
        needsDisplay = true
        return true
    }

    /// ⌫ with a selection: every selected mark goes away through
    /// `remove(id:)`, so the session's redo journal holds them and the global
    /// history can restore each one.
    @discardableResult
    func deleteSelectedMark() -> Bool {
        var removed: [UUID] = []
        for id in selectedMarkIDs {
            guard session.strokes.contains(where: { $0.id == id }), session.remove(id: id) else { continue }
            committedBounds.removeValue(forKey: id)
            onDelete?(id)
            removed.append(id)
        }
        guard !removed.isEmpty else { return false }
        pruneSelection()
        noteBlurInterestChanged()
        noteSessionChanged()
        needsDisplay = true
        Diag.log("delete mark count=\(removed.count) ids=\(removed.prefix(3).map { $0.uuidString.prefix(8) }.joined(separator: ","))")
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
            beginSelection(
                at: point,
                viewPoint: viewPoint,
                shift: event.modifierFlags.contains(.shift)
            )
            return
        default:
            // A mark of another tool must not leave a text editor behind: it
            // would keep its field as a subview and swallow what is underneath.
            finishPendingTextEditing()
        }

        let placed = session.begin(at: point, tool: state.tool, ink: state.ink)
        if state.tool.isTransient { startLaserTimer() }
        noteBlurInterestChanged()
        noteSessionChanged()
        if state.tool.commitsImmediately {
            // A numbered step commits inside `begin`, so `mouseUp` never runs
            // for it. The badge is wider than the small drag dirty band: it has
            // to be invalidated at its own display bounds here, or only the
            // band around the click point repaints and the badge shows as a
            // clipped square without its digit until the next full redraw.
            committedBounds[placed.id] = placed.displayBounds
            setNeedsDisplay(viewRect(fromPage: placed.displayBounds))
            // And the commit has to reach the global history exactly once,
            // through the same report a drag-committed mark makes at mouse up
            // (mouseUp never runs for a click tool, so this cannot double):
            // one ⌘Z removes exactly this badge and ⇧⌘Z brings it back.
            onCommit?(placed)
        } else {
            setNeedsDisplay(dirtyRect(around: viewPoint, other: nil))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isSelectingArea {
            let point = convert(event.locationInWindow, from: nil)
            guard let origin = selectionOrigin else { return }
            selectionRect = AreaSelectionGeometry.rect(
                from: origin,
                to: point,
                square: event.modifierFlags.contains(.shift),
                bounds: bounds
            )
            needsDisplay = true
            return
        }

        // Editing an existing mark: the handle decides, the preview follows.
        // A marquee drag (T6/S8) only grows its own rectangle, never a preview.
        if state.tool == .select {
            if marqueeOrigin != nil {
                updateMarquee(at: convert(event.locationInWindow, from: nil))
                return
            }
            if selectionDrag != nil {
                updateSelectionPreview(at: pagePoint(convert(event.locationInWindow, from: nil)))
                return
            }
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
            if let rect, AreaSelectionGeometry.isCaptureWorthy(rect) {
                onCaptureRequest?(rect)
            } else {
                Diag.log("capture area too small, ignored")
            }
            return
        }

        // Editing a mark: the pointer's final position is applied before the
        // preview is journalled exactly once, so one drag is one undo step,
        // never one per mouse event. A marquee drag ends by selecting what its
        // rectangle intersects (T6/S8).
        if state.tool == .select {
            if marqueeOrigin != nil {
                finishMarqueeSelection(at: convert(event.locationInWindow, from: nil))
            } else {
                updateSelectionPreview(at: pagePoint(convert(event.locationInWindow, from: nil)))
                commitSelectionDrag()
            }
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

    /// Selection geometry reached by the pointer answers with screen-sized
    /// reach: the hit radius and handle size are view points, so they map into
    /// page space through the layer's own transform.
    private var selectionReach: CGFloat { viewTransform.pageLength(Self.selectionHitRadius) }
    private var selectionHandleSize: CGFloat { viewTransform.pageLength(MarkSelection.defaultHandleSize) }

    /// Which handle a page-space point grabs: the handle size and the rotation
    /// knob's offset are measured in screen points and mapped through the
    /// layer's own transform, so what a click hits is exactly what the chrome
    /// draws.

    /// Page-space size of a view-space length, shared by the eraser and the
    /// chrome (1 in the plain overlay, 1/zoom on the board).
    var pageLengthForScreen: CGFloat { viewTransform.pageLength(1) }

    /// The rotation knob's offset above the box, in page units: the number the
    /// chrome draws with and the number a click grabs with must be this same
    /// value. Dividing the screen offset by the zoom keeps the knob at a
    /// constant screen distance from the box, like every other piece of chrome.
    var selectionRotationHandleOffset: CGFloat {
        viewTransform.pageLength(MarkSelection.defaultRotationHandleOffset)
    }

    /// A click with the edit cursor. With ⇧ held: the topmost mark under the
    /// pointer toggles in or out of the selection (T6/S8), and an empty canvas
    /// starts an additive marquee. Without ⇧: a handle of the already selected
    /// mark wins, then the topmost mark under the pointer (newest first) arms
    /// its move drag right away — select-and-move is one gesture — and empty
    /// canvas starts the marquee selection instead, so a drag over an area
    /// selects every mark it intersects when it ends. A marquee that never
    /// decides at the start: the selection only changes at release.
    private func beginSelection(at point: CGPoint, viewPoint: CGPoint, shift: Bool) {
        if shift {
            // ⇧ on a mark toggles it; ⇧ on empty canvas arms an additive
            // marquee. The selection only grows or shrinks one step here.
            if let hit = session.strokes.last(where: {
                $0.isSelectedByCursor(at: point, radius: selectionReach)
            }) {
                var selection = MarkMultiSelection(ids: selectedMarkIDs)
                selection.toggle(hit.id)
                selectedMarkIDs = selection.ids
                if let primary = selection.first { onSelectionChanged?(primary) }
                needsDisplay = true
            } else {
                beginMarquee(at: viewPoint, additive: true)
            }
            return
        }

        if let id = selectedMarkID, let selected = session.strokes.first(where: { $0.id == id }) {
            if let handle = MarkSelection(stroke: selected).handle(
                at: point,
                handleSize: selectionHandleSize,
                rotationHandleOffset: selectionRotationHandleOffset
            ) {
                startSelectionDrag(handle, on: selected, at: point)
                return
            }
        }

        guard let hit = session.strokes.last(where: {
            $0.isSelectedByCursor(at: point, radius: selectionReach)
        }) else {
            // Empty canvas: the drag decides — a grown marquee selects what it
            // intersects (T6/S8), a release without growth is today's plain
            // click that gives the selection up.
            beginMarquee(at: viewPoint, additive: false)
            return
        }
        var selection = MarkMultiSelection(ids: selectedMarkIDs)
        if !selection.contains(hit.id) {
            // A mark outside the selection: today's behaviour — the selection
            // collapses to it, and the drag moves it alone.
            selection.replace(with: hit.id)
            selectedMarkIDs = selection.ids
            onSelectionChanged?(hit.id)
        }
        // A mark already part of a multi-selection starts the group move, not
        // a collapse (T6b/S8): only dashed boxes are visible there, so the
        // body alone is grabbed — resize and rotation are one-mark edits.
        let handle: MarkHandle = selection.count > 1
            ? .body
            : MarkSelection(stroke: hit).handle(
                at: point,
                handleSize: selectionHandleSize,
                rotationHandleOffset: selectionRotationHandleOffset
            ) ?? .body
        startSelectionDrag(handle, on: hit, at: point)
    }

    // MARK: - Marquee selection (T6/S8)

    /// Arms the selection marquee: the selection itself only changes when the
    /// drag ends, so a marquee that intersects nothing leaves it as it was.
    private func beginMarquee(at viewPoint: CGPoint, additive: Bool) {
        marqueeOrigin = viewPoint
        marqueeAdditive = additive
        marqueeRect = CGRect(origin: viewPoint, size: .zero)
        needsDisplay = true
        Diag.log("marquee \(additive ? "additive" : "replace") started")
    }

    /// Grows the live marquee rectangle and repaints the band it moved across.
    private func updateMarquee(at viewPoint: CGPoint) {
        guard let origin = marqueeOrigin else { return }
        let previous = marqueeRect
        marqueeRect = PathBuilder.normalizedRect(from: origin, to: viewPoint)
        var dirty = (previous ?? marqueeRect!).union(marqueeRect!)
        dirty = dirty.insetBy(dx: -4, dy: -4)
        setNeedsDisplay(dirty)
    }

    /// Ends the marquee: the drag's view-space rectangle maps into page space
    /// through the layer's own transform, so on a panned or zoomed board it
    /// selects exactly the marks under what the user drew over (T6/S8). A drag
    /// that never grew is a plain click on empty canvas — today's behaviour:
    /// the selection is given up. A grown marquee that intersects nothing
    /// changes nothing at all, and the move drags never run here, so nothing
    /// is moved and no history step is added.
    private func finishMarqueeSelection(at endView: CGPoint) {
        guard let origin = marqueeOrigin else { return }
        let additive = marqueeAdditive
        let rect = PathBuilder.normalizedRect(from: origin, to: endView)
        marqueeOrigin = nil
        marqueeRect = nil
        marqueeAdditive = false
        needsDisplay = true

        guard rect.width >= 4, rect.height >= 4 else {
            // A click, not a marquee: give the selection up, the way an empty
            // click always did.
            clearSelection()
            return
        }
        let pageRect = viewTransform.rect(toPage: rect)
        let intersected = MarkMultiSelection.ids(intersectingMarquee: pageRect, in: session.strokes)
        guard !intersected.isEmpty else {
            // A marquee over nothing moves nothing and leaves the selection
            // exactly as it was — no history step, no drag.
            Diag.log("marquee empty, selection kept")
            return
        }
        var selection = MarkMultiSelection(ids: selectedMarkIDs)
        let before = selection
        if additive { selection.add(intersected) } else { selection.replace(with: intersected) }
        selectedMarkIDs = selection.ids
        if before != selection, let primary = selection.first {
            onSelectionChanged?(primary)
        }
        Diag.log("marquee selected=\(selection.ids.count) additive=\(additive)")
        needsDisplay = true
    }

    /// Arms the drag the grabbed handle asks for. The mark's untouched
    /// snapshot is kept: every preview frame transforms it from scratch, which
    /// is what makes a drag idempotent.
    private func startSelectionDrag(_ handle: MarkHandle, on stroke: Stroke, at point: CGPoint) {
        selectionOriginal = stroke
        selectionPreview = nil
        groupOriginals = []
        groupPreviews = []
        switch handle {
        case .body:
            selectionDrag = .move(start: point)
            // T6b/S8: a move on a multi-selection drags every member. A
            // single selected mark keeps today's one-mark path untouched —
            // the group arrays stay empty and the drag commits through
            // the same `replace` it always did.
            if selectedMarkIDs.count > 1 {
                groupOriginals = selectedMarkIDs.compactMap { id in
                    session.strokes.first(where: { $0.id == id })
                }
            }
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
            let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
            selectionPreview = MarkTransform.translated(original, by: delta)
            // T6b/S8: every member of the group follows the same delta, from
            // its own untouched snapshot.
            if !groupOriginals.isEmpty {
                groupPreviews = groupOriginals.map { MarkTransform.translated($0, by: delta) }
            }
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
        let group = groupOriginals
        defer {
            selectionDrag = nil
            selectionOriginal = nil
            selectionPreview = nil
            groupOriginals = []
            groupPreviews = []
            needsDisplay = true
        }
        // Group move (T6b/S8): the whole multi-selection is replaced through
        // the session's batch op — ONE journal op — and the selection stays
        // exactly as it was. The controller turns the callback into ONE
        // global-history entry, so ⌘Z returns every mark and ⇧⌘Z moves them
        // again.
        if group.count > 1 {
            guard groupPreviews.count == group.count,
                  groupPreviews != group,
                  session.replaceBatch(groupPreviews) else { return }
            for stroke in groupPreviews {
                committedBounds[stroke.id] = stroke.displayBounds
            }
            noteBlurInterestChanged()
            noteSessionChanged()
            noteBatchCommitted(groupPreviews)
            Diag.log("transform batch count=\(groupPreviews.count)")
            return
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

    /// The selection marquee (T6/S8): a thin accent rectangle over the drag it
    /// belongs to, with no fill — the marks under it stay visible. It draws only
    /// while a select-tool drag is actually running, never otherwise.
    private func drawMarquee(in context: CGContext) {
        guard state.tool == .select, marqueeOrigin != nil, let rect = marqueeRect,
              rect.width > 0, rect.height > 0 else { return }
        context.setStrokeColor(CGColor(srgbRed: 0.25, green: 0.55, blue: 1, alpha: 0.9))
        context.setLineWidth(1)
        context.addRect(rect)
        context.strokePath()
    }

    // MARK: - Eraser

    private func erase(at point: CGPoint) {
        // The eraser is a screen-sized circle: at any zoom it erases what is
        // under the pointer, so its page-space radius follows the zoom.
        let removed = session.erase(at: point, radius: Self.eraserRadius * pageLengthForScreen)
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
            // The field is a view-space editor: its measured size is screen
            // points, while the text mark stores page-space points.
            session.setActiveText(
                typed,
                size: CGSize(width: size.width / zoom, height: size.height / zoom)
            )
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

    /// The invalidation rect comes from the appearance itself
    /// (`PointerHighlightRenderer.extent`), never from local constants, so it
    /// always covers whatever the renderer paints for the chosen style.
    private func pointerRect(around point: CGPoint, scale: CGFloat = 1) -> CGRect {
        let appearance = state.pointerStyle.appearance(ink: state.ink)
        return PointerHighlightRenderer
            .extent(for: appearance, pulseScale: scale)
            .offsetBy(dx: point.x, dy: point.y)
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
            // With marks selected, Escape first gives the selection up instead
            // of clearing, so one stray click never costs the session.
            if !selectedMarkIDs.isEmpty {
                clearSelection()
                return
            }
            // The drawing hint promises "esc to clear": clear this layer's
            // marks and keep drawing — the hint stays up and the next stroke
            // can be drawn right away. Leaving drawing mode stays on ⌥⇧A and
            // the Done button, never on Escape.
            onClearMarks?()
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

        // ⌥S captures the front window. Checked before the tool router so a
        // rebound tool key can never shadow the capture keys.
        if characters.lowercased() == "s", event.modifierFlags.contains(.option) {
            onCaptureWindowRequest?()
            return
        }

        if let character = characters.first {
            // Routing goes through the live tool-shortcut map (T8/S6): a
            // shortcut edited in Settings routes here too.
            switch state.shortcutRouter.resolve(character) {
            case .tool(let tool):
                state.tool = tool
                // The pointer may be resting: the new tool's cursor (T2/S2)
                // must show now, not only after the next mouse move.
                reassertCursor()
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
    /// glow, drawn by the one production renderer (`PointerHighlightRenderer`)
    /// from the `PointerStyle` chosen in Settings and the current ink, so the
    /// overlay and the Settings preview draw identical pixels. The idle fade
    /// is folded in here as a context alpha around the renderer call; the
    /// renderer itself knows nothing about fading. A style whose click
    /// animation is rotate turns the shape with the same pulse envelope:
    /// each unit of pulse scale past 1 turns it
    /// `clickRotateRadiansPerScale` radians, so the pulse's peak (1.35×)
    /// turns it ≈0.42 rad ≈ 24° and it returns to rest with the pulse.
    private func drawCursorFrame(in context: CGContext) {
        // Pointer highlight is its own mode; it is never part of drawing.
        guard showsOnlyPointer, let point = pointerLocation else { return }

        let style = state.pointerStyle
        let appearance = style.appearance(ink: state.ink)
        // The pulse grows and settles even while the pointer stands still, so
        // the rotation rides the same envelope as the scale animation.
        // Rotate tilts the shape and leaves the size alone: a rotate click that
        // also grew read as a jump next to the reference, where the shape only
        // turns. Scale keeps the pulse's growth and never turns.
        let tilts = style.clickAnimation == .rotate
        let pulseScale: CGFloat = tilts ? 1 : pointerPulseScale
        let rotation: CGFloat = tilts
            ? (pointerPulseScale - 1) * Self.clickRotateRadiansPerScale
            : 0
        let alpha = idleAlpha
        guard alpha < 1 else {
            PointerHighlightRenderer.draw(
                in: context,
                center: point,
                appearance: appearance,
                pulseScale: pulseScale,
                rotation: rotation
            )
            return
        }
        context.saveGState()
        context.setAlpha(alpha)
        PointerHighlightRenderer.draw(
            in: context,
            center: point,
            appearance: appearance,
            pulseScale: pulseScale,
            rotation: rotation
        )
        context.restoreGState()
    }

    /// Radians of click-rotate turn per unit of pulse scale past 1: the peak
    /// pulse (1.35×) turns the shape ≈0.21 rad ≈ 12°, the tilt the reference
    /// shows, while the size stays where the user put it.
    private static let clickRotateRadiansPerScale: CGFloat = 0.6

    /// Fades the highlight down when the pointer has been still, so a shared
    /// screen is not permanently framed.
    private var idleAlpha: CGFloat {
        guard state.pointerFadeWhenIdle, showsOnlyPointer else { return 1 }
        let idle = Date().timeIntervalSince(lastPointerChange)
        guard idle > 1.2 else { return 1 }
        let progress = min(1, (idle - 1.2) / 0.8)
        return 1 - 0.75 * progress
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

        drawBackground(in: context, dirty: dirtyRect)
        drawMarks(in: context, dirty: dirtyRect)

        notePaintLatency()

        drawDrawingFrame(in: context)
        drawSelection(in: context)
        drawMarquee(in: context)
        drawSelectedMarkChrome(in: context)
        drawHint()
    }

    /// The layer under the marks. Empty in the transparent overlay; the
    /// whiteboard paints the current page's background and its dot grid here —
    /// both only inside the dirty rect, so a per-frame paint stays cheap.
    func drawBackground(in context: CGContext, dirty dirtyRect: NSRect) {}

    /// Every mark on the layer, in page space, translated by the pan offset.
    /// `dirtyRect` is in view space; the context is shifted so page-space
    /// points land where the user sees them, which is what makes panning and
    /// display changes never move stored marks.
    func drawMarks(in context: CGContext, dirty dirtyRect: NSRect) {
        let transform = viewTransform
        let pageDirty = transform.rect(toPage: dirtyRect)
        context.saveGState()
        context.concatenate(transform.cgAffineTransform)
        let now = Date()
        for stroke in session.strokes where stroke.tool.isTransient {
            render(stroke, in: context, now: now)
        }

        for stroke in session.strokes where !stroke.tool.isTransient {
            // The live preview of a transform takes over: the mark is drawn
            // transformed on top instead of both versions at once.
            if let preview = selectionPreview, stroke.id == preview.id { continue }
            if !groupPreviews.isEmpty, groupPreviews.contains(where: { $0.id == stroke.id }) { continue }
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
        if let preview = selectionPreview, !groupPreviews.contains(where: { $0.id == preview.id }) {
            render(preview, in: context)
        }
        for preview in groupPreviews {
            render(preview, in: context)
        }
        context.restoreGState()
    }

    /// The selection chrome over the selected mark: a dashed box, four corner
    /// squares and the rotation knob, following the mark as it now looks
    /// (preview included). View chrome only — it never enters the session, so
    /// a capture never contains it and `committedBounds` never grows for it.
    /// With several marks selected (T6/S8) each one gets its dashed box, while
    /// the handles and the rotation knob only draw for a single selection —
    /// resize and rotation are one-mark edits.
    private func drawSelectedMarkChrome(in context: CGContext) {
        guard state.tool == .select, let primary = selectedMarkID, !selectedMarkIDs.isEmpty else { return }
        let multi = selectedMarkIDs.count > 1
        guard let stroke = selectionPreview ?? session.strokes.first(where: { $0.id == primary }) else { return }

        let selection = MarkSelection(stroke: stroke)
        let accent = CGColor(srgbRed: 0.25, green: 0.55, blue: 1, alpha: 1)
        let transform = viewTransform

        context.saveGState()
        // Chrome geometry is page space — the same space the marks live in —
        // but every stroke of it sizes itself in view points divided back into
        // page units, so the handles keep their on-screen size at any zoom:
        // they neither shrink to nothing when zoomed out nor grow when zoomed
        // in. The mark's geometry scales; the chrome does not.
        context.concatenate(transform.cgAffineTransform)
        let unit = transform.pageLength(1)

        context.saveGState()
        context.concatenate(
            Stroke.rotationTransform(around: selection.anchor, by: selection.rotation)
        )
        context.setStrokeColor(accent)
        context.setLineWidth(1.5 * unit)
        context.setLineDash(phase: 0, lengths: [5 * unit, 4 * unit])
        context.addRect(selection.unrotatedBounds)
        context.strokePath()
        context.restoreGState()

        // Several selected: dashed boxes around every other mark too, no
        // handles — a drag can still only move the primary.
        if multi {
            for id in selectedMarkIDs.dropFirst() {
                // During a group move (T6b/S8) a member's box follows its
                // live preview, never the stale committed geometry.
                guard let other = groupPreviews.first(where: { $0.id == id })
                    ?? session.strokes.first(where: { $0.id == id }) else { continue }
                let box = MarkSelection(stroke: other)
                context.saveGState()
                context.setStrokeColor(accent)
                context.setLineWidth(1.5 * unit)
                context.setLineDash(phase: 0, lengths: [5 * unit, 4 * unit])
                context.addRect(box.unrotatedBounds)
                context.strokePath()
                context.restoreGState()
            }
            context.restoreGState()
            return
        }

        for (handle, point) in selection.handlePoints(
            rotationHandleOffset: selectionRotationHandleOffset
        ) {
            if handle == .rotation {
                let radius = 5 * unit
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                context.setStrokeColor(accent)
                context.setLineWidth(1.5 * unit)
                context.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                context.strokePath()
            } else {
                let half = 4 * unit
                let square = CGRect(x: point.x - half, y: point.y - half, width: half * 2, height: half * 2)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(square)
                context.setStrokeColor(accent)
                context.setLineWidth(1.5 * unit)
                context.stroke(square)
            }
        }
        context.restoreGState()
    }

    /// Which preference decides the frame at this layer's edges: the drawing
    /// overlay follows the drawing frame, the whiteboard its own border
    /// preference (S2) — the two are never coupled.
    var showsEdgeFrame: Bool { state.showArmedFrame }

    /// A thin frame in the current ink marks every armed display for the whole
    /// drawing session, so it is always clear which screens will take a mark.
    func drawDrawingFrame(in context: CGContext) {
        guard showsEdgeFrame else { return }
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

    /// The image a blur mark diffuses, with its pixels per view point. The
    /// drawing overlay reads the display's latest live frame — the real screen
    /// pixels under the transparent layer (T5/S3). The whiteboard overrides
    /// this: its blur diffs the board's own content (S1). Nil draws the
    /// neutral fallback patch (no frame yet, or Screen Recording denied).
    func blurSource(for stroke: Stroke) -> (image: CGImage, pixelsPerPoint: CGFloat)? {
        guard let frame = liveFrameSource?.frame(for: displayID), bounds.width > 0 else { return nil }
        return (frame, CGFloat(frame.width) / max(bounds.width, 1))
    }

    /// Live blur: a blur mark shows the content underneath it, gaussian
    /// blurred, from the image `blurSource` provides. That image covers view
    /// space while the mark's stored points are page space, so on a panned
    /// page the crop reads the region the board shows the patch at
    /// (`pagePoint - offset`) — the same placement the capture compositor
    /// produces. With no source (the first instants of a drag, or Screen
    /// Recording denied) a neutral translucent fill with a thin border still
    /// shows where the mark is, and nothing crashes or paints garbage.
    private func drawBlur(_ stroke: Stroke, in context: CGContext) {
        guard let first = stroke.points.first, let last = stroke.points.last else { return }
        let rect = PathBuilder.normalizedRect(from: first, to: last)
        guard rect.width > 0, rect.height > 0 else { return }

        // The mark's points are page space; the source image is view space.
        let transform = viewTransform
        let viewRect = transform.rect(fromPage: rect)

        if let source = blurSource(for: stroke) {
            let image = source.image
            let scale = source.pixelsPerPoint
            let pixelRect = CGRect(
                x: viewRect.minX * scale,
                // Bottom-left pixel origin under a top-left view origin.
                y: CGFloat(image.height) - viewRect.maxY * scale,
                width: viewRect.width * scale,
                height: viewRect.height * scale
            )
            if let blurred = BlurEffect.crop(
                image,
                pixelRect: pixelRect,
                radius: BlurEffect.defaultRadius * scale
            ) {
                // The crop may cover less than the full rect when the mark
                // reaches past the image: draw it at the intersection, clipped
                // to the mark. The context is flipped for overlay space, so an
                // image drawn plainly would land upside down; unflip it inside
                // the rectangle. The context draws in page space, so the
                // landed view rect is placed back at its page position.
                let landed = pixelRect.intersection(
                    CGRect(x: 0, y: 0, width: image.width, height: image.height)
                )
                let landedView = CGRect(
                    x: landed.minX / scale,
                    y: (CGFloat(image.height) - landed.maxY) / scale,
                    width: landed.width / scale,
                    height: landed.height / scale
                )
                let landedPage = transform.rect(toPage: landedView)
                context.saveGState()
                context.clip(to: rect)
                context.translateBy(x: landedPage.minX, y: landedPage.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(blurred, in: CGRect(origin: .zero, size: landedPage.size))
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

// MARK: - Tool glyph cursors (T2/S2)

/// The cursors no system shape can claim: a 16-pt image per glyph role, drawn
/// here instead of shipped as assets. Every glyph is centred on the hotspot,
/// so the mark still lands exactly under the pointer regardless of how the
/// image coordinate system faces, and is stroked dark-first-white-on-top so
/// it reads on a light and on a dark canvas. System-cursor roles answer nil:
/// `OverlayView.cursor(for:)` serves those straight from AppKit.
private enum ToolGlyphCursor {
    /// Canvas every glyph is drawn on, and the hotspot at its centre.
    private static let canvasSide: CGFloat = 16

    static func cursor(for role: ToolCursor) -> NSCursor? {
        let image = NSImage(size: NSSize(width: canvasSide, height: canvasSide), flipped: true) { _ in
            draw(role)
            return true
        }
        let centre = canvasSide / 2
        return NSCursor(image: image, hotSpot: CGPoint(x: centre, y: centre))
    }

    private static func draw(_ role: ToolCursor) {
        switch role {
        case .penNib: drawPencilNib()
        case .markerChisel: drawChiselTip()
        case .arrowHead: drawArrowHead()
        case .rectangleFrame: outline(NSBezierPath(rect: NSRect(x: 4.2, y: 4.2, width: 7.6, height: 7.6)))
        case .ellipseRing: outline(NSBezierPath(ovalIn: NSRect(x: 4.0, y: 4.0, width: 8.0, height: 8.0)))
        case .laserSpark: drawSpark()
        case .eraserBlock: drawEraserBlock()
        case .blurDots: drawDotGrid()
        case .editArrow, .textIBeam, .numberHand, .lineCrosshair:
            break // system roles: AppKit answers, nothing to draw
        }
    }

    // MARK: The shared read-on-both-themes trick

    /// Strokes the path twice: thick in dark first — the outline that keeps
    /// the glyph readable on a light background — then thin in white on top
    /// for a dark background. One path, one pass per theme trick.
    private static func outline(_ path: NSBezierPath, dark: NSColor = .black, light: NSColor = .white) {
        let outline = path.copy() as! NSBezierPath
        for stroke in [outline, path] {
            stroke.lineCapStyle = .round
            stroke.lineJoinStyle = .round
        }
        outline.lineWidth = 3.0
        dark.setStroke()
        outline.stroke()
        path.lineWidth = 1.25
        light.setStroke()
        path.stroke()
    }

    /// A filled dot: a larger dark disc with the light core on top — a fill
    /// cannot use the thick-outline trick, so the shape is built from two
    /// concentric circles instead.
    private static func dot(centre: NSPoint, radius: CGFloat) {
        NSColor.black.setFill()
        circle(centre: centre, radius: radius + 0.9).fill()
        NSColor.white.setFill()
        circle(centre: centre, radius: radius).fill()
    }

    private static func line(_ from: NSPoint, _ to: NSPoint) {
        outline(NSBezierPath(points: from, to: to))
    }

    // MARK: The glyphs

    /// Freehand ink: a pencil-like nib, tip pointing down-left, body to the
    /// top-right — the silhouette says "draws a stroke".
    private static func drawPencilNib() {
        let nib = NSBezierPath()
        nib.move(to: NSPoint(x: 4.8, y: 11.2)) // the tip
        nib.line(to: NSPoint(x: 3.8, y: 10.2))
        nib.line(to: NSPoint(x: 11.0, y: 3.4))
        nib.line(to: NSPoint(x: 13.0, y: 5.0))
        nib.line(to: NSPoint(x: 5.8, y: 12.2))
        nib.close()
        outline(nib)
    }

    /// The highlighter's flat swab: a wide chisel, narrow at the handle and
    /// flat and broad at the far edge.
    private static func drawChiselTip() {
        let chisel = NSBezierPath()
        chisel.move(to: NSPoint(x: 6.0, y: 4.4))
        chisel.line(to: NSPoint(x: 10.0, y: 4.4))
        chisel.line(to: NSPoint(x: 12.2, y: 11.6))
        chisel.line(to: NSPoint(x: 3.8, y: 11.6))
        chisel.close()
        outline(chisel)
    }

    /// The straight arrow mark: a diagonal shaft with an open head, the same
    /// up-right silhouette the mark itself draws.
    private static func drawArrowHead() {
        line(NSPoint(x: 4.6, y: 11.4), NSPoint(x: 11.4, y: 4.6)) // shaft
        let head = NSBezierPath()
        head.move(to: NSPoint(x: 6.6, y: 4.6))
        head.line(to: NSPoint(x: 11.4, y: 4.6))
        head.line(to: NSPoint(x: 11.4, y: 9.4))
        outline(head)
    }

    /// The laser: one bright dot with rays, the transient trail's spark.
    private static func drawSpark() {
        dot(centre: NSPoint(x: 8, y: 8), radius: 1.7)
        line(NSPoint(x: 8, y: 2.4), NSPoint(x: 8, y: 4.4)) // north
        line(NSPoint(x: 8, y: 11.6), NSPoint(x: 8, y: 13.6)) // south
        line(NSPoint(x: 2.4, y: 8), NSPoint(x: 4.4, y: 8)) // west
        line(NSPoint(x: 11.6, y: 8), NSPoint(x: 13.6, y: 8)) // east
    }

    /// The eraser: a slanted block with its felt-and-holder dividing line.
    private static func drawEraserBlock() {
        let block = NSBezierPath()
        block.move(to: NSPoint(x: 3.8, y: 11.2))
        block.line(to: NSPoint(x: 8.8, y: 6.2))
        block.line(to: NSPoint(x: 12.2, y: 9.6))
        block.line(to: NSPoint(x: 7.2, y: 14.6))
        block.close()
        outline(block)
        line(NSPoint(x: 5.5, y: 12.9), NSPoint(x: 10.5, y: 7.9)) // divider
    }

    /// The blur: a small grid of soft dots, the frosted patch it paints.
    private static func drawDotGrid() {
        let spacing: CGFloat = 3.0
        for x in stride(from: 5.0, to: 11.5, by: spacing) {
            for y in stride(from: 5.0, to: 11.5, by: spacing) {
                dot(centre: NSPoint(x: x, y: y), radius: 1.2)
            }
        }
    }

    // MARK: Path helpers

    private static func circle(centre: NSPoint = NSPoint(x: 8, y: 8), radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    }
}

extension NSBezierPath {
    fileprivate convenience init(points: NSPoint, to: NSPoint) {
        self.init()
        move(to: points)
        line(to: to)
    }
}
