import AppKit
import StareCore

/// The opaque whiteboard layer (T6/S3): pages with their own marks, background
/// colour and pan offset over an endless canvas. It reuses the overlay's whole
/// input path through the page-space hooks (`panOffset`, `pagePoint`), painting
/// only what differs: a solid background per page and the panned marks.
///
/// Stroke points are stored in page space (top-left origin, `CoordinateMapping`
/// conventions), so panning and display changes never move existing marks.
/// Every session change flows into `board` through the sink the base class
/// calls, so the board stays authoritative without write-back sync.
/// Not `final` so the self test can record the dirty rects the board's own
/// click path invalidates.
class WhiteboardView: OverlayView {
    /// The pages of this display; owned by the controller so they survive
    /// closing the board.
    let board: WhiteboardPages
    /// Page changes reach the toolbar's indicator through this.
    var onPageChanged: (() -> Void)?
    /// Structural page changes (⌘⌫ delete, ⌥← ⌥→ reorder) reach the
    /// controller through this as a mapping from each page's old index to its
    /// index after the change — nil when the page no longer exists — so the
    /// page-carrying history entries follow the pages they name instead of
    /// sliding onto a neighbour's slot (T4/S5, T6b/S8).
    var onPageStructureChanged: (((Int) -> Int?) -> Void)?
    /// Space is held: drags pan the canvas instead of drawing.
    private var isSpacePanning = false
    /// Middle-button drag pans the canvas too.
    private var isMiddlePanning = false
    private var lastPanPoint: CGPoint?
    /// ⌘ + scroll is zooming (S1/S3): a zoom cursor shows while the gesture
    /// runs and is cleared when it ends.
    private var isZoomScrolling = false
    /// The direction the last applied ⌘ + scroll step zoomed: its sign picks
    /// which magnifier cursor shows.
    private var lastZoomScrollDelta: CGFloat = 0
    /// The ⌘ + scroll gesture's own state machine (v0.5/S2): the direction
    /// lock and the momentum rejection live in `ScrollZoom.Gesture`
    /// (StareCore), and the view only consults it.
    private var scrollZoomGesture = ScrollZoom.Gesture()

    init(frame: NSRect, state: EditorState, board: WhiteboardPages, onEscape: @escaping () -> Void) {
        self.board = board
        super.init(frame: frame, state: state, onEscape: onEscape)
        boardSink = { [weak self] session in self?.board.adopt(session) }
        // A canvas can join a board that already has pages — a scope change
        // (S3) or a display change rebuilds the canvases while the board is
        // open, and reopening the board finds the session's pages. Present
        // what the board holds, never an empty page; later changes flow back
        // through the sink, so the page stays authoritative.
        session = board.currentPage.session
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WhiteboardView is created in code only")
    }

    /// The plain overlay has no pages — `historyPage` stays nil there. The
    /// whiteboard names whichever page is presented when an entry is created,
    /// which is where its clear or batch move happened.
    override var historyPage: Int? { board.currentIndex }

    /// The Escape clear (T4/S5) at the view layer: the clear is an edit of
    /// the page it happened on, so the redo history of the view's page records
    /// forks here too — the same rule the controller applies to its global
    /// redo order — and the clear is recorded on this page for the plain
    /// (bare-view) pop path. The controller's entry-driven routing carries
    /// the page itself and does not consult these records.
    override func clearForUndo() -> Bool {
        let page = board.currentIndex
        let removedAny = super.clearForUndo()
        guard removedAny else { return false }
        clearRedoPages.removeAll()
        batchRedoPages.removeAll()
        clearUndoPages.append(page)
        return true
    }

    /// A committed group move (T6b/S8) at the view layer: recorded on the
    /// page it happened on for the plain pop path, with the same redo fork
    /// the clear keeps.
    override func noteBatchCommitted(_ strokes: [Stroke]) {
        batchRedoPages.removeAll()
        clearRedoPages.removeAll()
        batchUndoPages.append(board.currentIndex)
        super.noteBatchCommitted(strokes)
    }

    override var panOffset: CGSize { board.currentPage.offset }

    /// T5/S5: the board shows the current page's zoom.
    override var zoom: CGFloat { board.currentPage.zoom }

    // MARK: - Blur of the board's own content (S1)

    /// A blur mark on the board diffs the board's own content: the page colour
    /// and the marks painted before it. It never shows the desktop behind the
    /// board, never reads live frames and never needs Screen Recording — the
    /// drawing overlay keeps reading the screen through the same tool, decided
    /// by which surface the mark lives on. The beneath image is composed
    /// exactly the way the board capture composes the page
    /// (`MarkCompositor.composite` with `diffusesContent` over the page's
    /// solid background, marks moved into view space by the pan), so the live
    /// view and the capture agree by construction, and the blur's crop is
    /// taken at the mark's place in draw order: marks painted after it are not
    /// in the image and stay sharp on top.
    override func blurSource(for stroke: Stroke) -> (image: CGImage, pixelsPerPoint: CGFloat)? {
        guard let image = boardContentBeneath(stroke) else { return nil }
        return (image, boardBlurScale)
    }

    /// View points to image pixels for the beneath image: the board window's
    /// backing scale, the same scale the page capture composes at.
    private var boardBlurScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    }

    /// The board never needs frames for its blur, so it never reports blur
    /// interest to the frame source (S1: no frames, no Screen Recording).
    override var hasLiveBlurMarks: Bool { false }

    private struct BeneathKey: Equatable {
        let strokes: [Stroke]
        let background: BoardBackground
        let isDark: Bool
        let transform: BoardTransform
        let scale: CGFloat
        let size: CGSize
        let imageID: UUID?
        let imageRect: CGRect?
    }

    /// Cache of the beneath image: dragging a blur mark repaints per frame,
    /// and the content beneath it only changes when the page's marks,
    /// background, pan, scale or size change — all of which are in the key.
    private var beneathCache: (key: BeneathKey, image: CGImage)?

    /// The page as it is rendered beneath `stroke`: page colour, the page's
    /// image layer (T2b/S2) and every committed mark before it in draw order
    /// (the mark being dragged sits above everything already committed). The
    /// layer is composited into the base before the marks, exactly the way the
    /// board capture does it, so the live view and the capture agree by
    /// construction and a blur mark diffuses the image the way it diffuses
    /// marks. The pan is applied here the same way the capture applies it, so
    /// the image covers view space and the view's crop lands where the board
    /// shows the patch.
    private func boardContentBeneath(_ stroke: Stroke) -> CGImage? {
        let committed = session.strokes
        let beneath: [Stroke]
        if let active = session.active, active.id == stroke.id {
            beneath = committed
        } else if let index = committed.firstIndex(where: { $0.id == stroke.id }) {
            beneath = Array(committed[..<index])
        } else {
            return nil
        }
        guard bounds.width >= 1, bounds.height >= 1 else { return nil }
        let scale = boardBlurScale
        let isDark = isDarkAppearance
        let page = board.currentPage
        let key = BeneathKey(
            strokes: beneath,
            background: page.background,
            isDark: isDark,
            transform: page.transform,
            scale: scale,
            size: bounds.size,
            // Identity and rect, never the pixels: the cache is compared per
            // paint, and CGImage equality is not per-frame work.
            imageID: page.image?.id,
            imageRect: page.image?.rect
        )
        if let cached = beneathCache, cached.key == key { return cached.image }
        guard let base = page.background.captureBase(
            width: Int(bounds.width * scale),
            height: Int(bounds.height * scale),
            isDark: isDark
        ) else { return nil }
        // The image layer is part of the content beneath every mark: into the
        // base, before the marks composite, exactly as the capture does it.
        let based = page.image?.composited(over: base, transform: page.transform, scale: scale) ?? base
        guard let image = MarkCompositor.composite(
            marks: beneath,
            over: based,
            scale: scale,
            diffusesContent: true,
            offset: page.offset,
            zoom: page.zoom
        ) else { return nil }
        beneathCache = (key, image)
        return image
    }

    // MARK: - Appearance (S4)

    /// Whether the effective appearance is dark: what a `.system` page colour
    /// resolves against. Exposed for the controller's capture path.
    var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// A page that follows the system changes colour with the theme: the
    /// repaint happens on the next frame, and the beneath-blur cache — keyed
    /// by the resolved colours of its time — cannot survive the flip.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        beneathCache = nil
        needsDisplay = true
    }

    // MARK: - Painting

    /// The page's solid base colour, then the Freeform-style dot grid (T6/S6):
    /// dots live in page space — they pan and zoom with the content — sit
    /// under every mark (this runs before `drawMarks`), and their colour reads
    /// on a white and a black page and on a system-following one. Only the
    /// dirty rect's dots are enumerated, so a per-frame paint stays cheap.
    /// Then the page's image layer (T2b/S2), above the colour and the grid and
    /// beneath the marks — content, not chrome.
    override func drawBackground(in context: CGContext, dirty dirtyRect: NSRect) {
        context.setFillColor(board.currentPage.background.cgColor(isDark: isDarkAppearance))
        context.fill(bounds)
        drawDotGrid(in: context, dirty: dirtyRect)
        drawPageImage(in: context)
    }

    /// The page's image layer in view space, through the page transform like
    /// the marks. The rect is drawn in the view's flipped space — and that is
    /// exactly why the pixels have to be unflipped first: the image comes
    /// top-down, so a plain `draw` lands it mirrored inside a correctly placed
    /// frame. The capture card and the editor's canvas undo the same flip.
    /// The dashed outline is the layer's selection chrome: view-only, never
    /// captured (the capture composites the layer through
    /// `BoardImage.composited`, not through this paint).
    private func drawPageImage(in context: CGContext) {
        guard let layer = board.currentPage.image else { return }
        let rect = layer.viewRect(for: viewTransform)
        guard rect.intersects(bounds) else { return }
        context.saveGState()
        context.translateBy(x: 0, y: rect.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -rect.midY)
        context.draw(layer.image, in: rect)
        context.restoreGState()
        if isBoardImageSelected {
            context.saveGState()
            context.setStrokeColor(CGColor(srgbRed: 0.25, green: 0.55, blue: 1, alpha: 1))
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.stroke(rect.insetBy(dx: -1, dy: -1))
            context.restoreGState()
        }
    }

    private func drawDotGrid(in context: CGContext, dirty dirtyRect: NSRect) {
        let transform = viewTransform
        let spacing = DotGrid.pageSpacing(atZoom: transform.zoom)
        let pageDirty = transform.rect(toPage: dirtyRect)
        let dots = DotGrid.dots(in: pageDirty, spacing: spacing)
        guard !dots.isEmpty else { return }
        // A dot is a screen-sized circle: same size at every zoom.
        let radius = transform.pageLength(DotGrid.dotRadius)
        let path = CGMutablePath()
        for dot in dots {
            path.addEllipse(in: CGRect(
                x: dot.x - radius,
                y: dot.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        context.saveGState()
        context.concatenate(transform.cgAffineTransform)
        context.setFillColor(CGColor(gray: 0.5, alpha: 0.3))
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }

    // MARK: - Border (S2)

    /// The border is the board's own preference (S2): it is decided here,
    /// independently of the drawing frame — it can be on while the drawing
    /// frame is off and the other way round.
    override var showsEdgeFrame: Bool { state.boardShowBorder }

    override func showIntroHint() {
        showHint(
            "Whiteboard · ⌘← ⌘→ pages · ⌘⌫ delete · ⌥← ⌥→ move · ⌘0 reset · ⌘+ ⌘− zoom · ⌘B background · space-drag pan · esc clear page",
            seconds: 3.2
        )
    }

    // MARK: - Pages

    /// › — one page on, creating past the last one with an inherited background.
    func selectNextPage() {
        board.adopt(session)
        let created = board.selectNext()
        loadCurrentPage()
        Diag.log("board next page=\(board.currentIndex + 1)/\(board.count) created=\(created)")
    }

    /// ‹ — one page back; at the first page the board stays put.
    func selectPreviousPage() {
        board.adopt(session)
        board.selectPrevious()
        loadCurrentPage()
        Diag.log("board previous page=\(board.currentIndex + 1)/\(board.count)")
    }

    /// ⌘⌫ — deletes the current page. The board never goes empty: with a single
    /// page the model refuses and the board stays as it was. Deleting reports
    /// its old→new index mapping to the controller, so page-carrying history
    /// entries follow their pages and the deleted page's entries leave the
    /// history instead of falling onto a neighbour's slot.
    @discardableResult
    func deleteCurrentPage() -> Bool {
        board.adopt(session)
        let deletedIndex = board.currentIndex
        let deleted = board.deleteCurrentPage()
        if deleted {
            loadCurrentPage()
            let mapping: (Int) -> Int? = { index in
                guard index != deletedIndex else { return nil }
                return index > deletedIndex ? index - 1 : index
            }
            onPageStructureChanged?(mapping)
            remapRecords(&clearUndoPages, mapping: mapping)
            remapRecords(&clearRedoPages, mapping: mapping)
            remapRecords(&batchUndoPages, mapping: mapping)
            remapRecords(&batchRedoPages, mapping: mapping)
        }
        Diag.log("board delete page deleted=\(deleted) pages=\(board.count) current=\(board.currentIndex + 1)")
        return deleted
    }

    /// ⌥← / ⌥→ — reorders: the current page swaps with its neighbour and stays
    /// current. Refused at the ends, exactly like ‹ at the first page. A move
    /// reports its old→new index mapping to the controller, so page-carrying
    /// history entries follow their pages through the swap.
    @discardableResult
    func moveCurrentPageLeft() -> Bool {
        board.adopt(session)
        let movedIndex = board.currentIndex
        let moved = board.moveCurrentPageLeft()
        if moved {
            loadCurrentPage()
            let mapping: (Int) -> Int? = { index in
                if index == movedIndex { return movedIndex - 1 }
                if index == movedIndex - 1 { return movedIndex }
                return index
            }
            onPageStructureChanged?(mapping)
            remapRecords(&clearUndoPages, mapping: mapping)
            remapRecords(&clearRedoPages, mapping: mapping)
            remapRecords(&batchUndoPages, mapping: mapping)
            remapRecords(&batchRedoPages, mapping: mapping)
        }
        Diag.log("board move left moved=\(moved) current=\(board.currentIndex + 1)/\(board.count)")
        return moved
    }

    @discardableResult
    func moveCurrentPageRight() -> Bool {
        board.adopt(session)
        let movedIndex = board.currentIndex
        let moved = board.moveCurrentPageRight()
        if moved {
            loadCurrentPage()
            let mapping: (Int) -> Int? = { index in
                if index == movedIndex { return movedIndex + 1 }
                if index == movedIndex + 1 { return movedIndex }
                return index
            }
            onPageStructureChanged?(mapping)
            remapRecords(&clearUndoPages, mapping: mapping)
            remapRecords(&clearRedoPages, mapping: mapping)
            remapRecords(&batchUndoPages, mapping: mapping)
            remapRecords(&batchRedoPages, mapping: mapping)
        }
        Diag.log("board move right moved=\(moved) current=\(board.currentIndex + 1)/\(board.count)")
        return moved
    }

    /// ⌘0 — resets the current page's pan and zoom together (T5/S5). The
    /// marks never move (their stored points are page space), so nothing else
    /// changes.
    func resetPageView() {
        board.resetView()
        needsDisplay = true
        Diag.log("board pan+zoom reset page=\(board.currentIndex + 1)")
    }

    // MARK: - The page image layer (T2b/S2)

    /// A capture picked in the history while the board is open: it becomes the
    /// current page's image layer, centred in the visible area and clamped by
    /// the model (`WhiteboardPages.paste`). The new layer takes the selection
    /// so ⌫ can act on it right away — the editor's paste convention.
    func pasteImage(_ image: CGImage) {
        let before = board.currentPage.image
        guard let layer = board.paste(image, inView: bounds) else {
            Diag.log("board image paste refused \(image.width)x\(image.height)")
            return
        }
        isBoardImageSelected = true
        imageGesture = nil
        needsDisplay = true
        Diag.log("board image pasted \(image.width)x\(image.height) rect=\(layer.rect) page=\(board.currentIndex + 1)")
        noteBoardImageEdit(before: before)
    }

    /// Whether the current page's image layer takes the keys and gestures.
    private var isBoardImageSelected = false

    /// Told after the current page's image layer changed (L8), with the
    /// placement before and after: nil→layer is a paste, layer→layer a move or
    /// a resize, layer→nil a delete or an Escape. The controller turns that
    /// into one step on the same undo stream the marks use.
    var onBoardImageEdited: ((BoardImage?, BoardImage?, Int) -> Void)?

    /// The layer as it was when the running gesture began, so a drag reports one
    /// edit (its start) instead of one per event.
    private var imageGestureStartLayer: BoardImage?

    /// Emits one image edit to the listener. Called at the END of an edit — a
    /// paste, a finished drag, a delete — never per mouse event.
    private func noteBoardImageEdit(before: BoardImage?) {
        onBoardImageEdited?(before, board.currentPage.image, board.currentIndex)
    }

    /// Puts a page's image layer back for the undo stream (L8), refreshing the
    /// paint and the selection it may no longer own.
    @discardableResult
    func restorePageImage(_ image: BoardImage?, onPage page: Int) -> Bool {
        guard board.restorePageImage(image, at: page) else { return false }
        isBoardImageSelected = false
        needsDisplay = true
        Diag.log("board image restored page=\(page + 1) present=\(image != nil)")
        return true
    }

    /// The running image gesture: the interior move-s, a corner grip resize-s
    /// — the capture editor's own ⌥ conventions, driven by the same grip and
    /// resize rules (`EditorCropRule`) the editor drives its layers with.
    private enum ImageGesture {
        /// `startPageRect` is the layer's placement when the drag began: a move
        /// is applied as an ABSOLUTE destination from it, never as a delta on
        /// top of the already-moved rect — doing the latter re-adds the whole
        /// travel on every event and the layer runs away from the pointer.
        case move(grab: CGPoint, startPageRect: CGRect)
        case resize(handle: CropHandle, startViewRect: CGRect)
    }

    private var imageGesture: ImageGesture?

    /// The page-space rect the gesture clamps against: the visible area where
    /// the drag began, held fixed so the layer can never land off it.
    private var imageGestureCanvas: CGRect = .zero

    /// A press with the select tool (V) over the layer claims it: the grip
    /// resize-s, the interior move-s, and the layer takes the selection so the
    /// keys can act on it. A click with no layer under it falls through to the
    /// tool's own behaviour, so selecting marks still works around it.
    private func grabBoardImage(at viewPoint: CGPoint) -> Bool {
        guard let layer = board.currentPage.image else { return false }
        let viewRect = layer.viewRect(for: viewTransform)
        let reach = EditorCropRule.defaultHandleReach
        guard viewRect.insetBy(dx: -reach, dy: -reach).contains(viewPoint) else { return false }
        isBoardImageSelected = true
        imageGestureStartLayer = layer
        imageGestureCanvas = viewTransform.rect(toPage: bounds)
        if let handle = EditorCropRule.handle(at: viewPoint, on: viewRect) {
            imageGesture = .resize(handle: handle, startViewRect: viewRect)
        } else {
            imageGesture = .move(
                grab: viewTransform.point(toPage: viewPoint),
                startPageRect: layer.rect
            )
        }
        needsDisplay = true
        return true
    }

    /// ⌫ / Delete with the layer selected (and no mark selection to take it
    /// first): the page's image layer goes away. The mark selection keeps its
    /// documented ⌫ behaviour whenever it exists.
    private func deleteBoardImageIfSelected() -> Bool {
        guard isBoardImageSelected, selectedMarkIDs.isEmpty else { return false }
        let before = board.currentPage.image
        guard board.removePageImage() else { return false }
        isBoardImageSelected = false
        needsDisplay = true
        Diag.log("board image deleted page=\(board.currentIndex + 1)")
        noteBoardImageEdit(before: before)
        return true
    }

    /// Escape (keyCode 53) after the overlay's own clear: the page's image
    /// layer leaves with the marks, so the hint's "esc clear page" is what the
    /// key actually does. Not journalled — the image lane's edits (⌫, ⌥-drag)
    /// are session values, not steps of the stroke journal.
    private func removePageImageOnEscape() {
        guard board.currentPage.image != nil else { return }
        let before = board.currentPage.image
        guard board.removePageImage() else { return }
        isBoardImageSelected = false
        needsDisplay = true
        Diag.log("board image cleared by esc page=\(board.currentIndex + 1)")
        noteBoardImageEdit(before: before)
    }

    // MARK: - Zooming (T5/S5)

    /// One zoom step from the keyboard: the same anchored zoom the pinch
    /// produces, with the multiplicative step and the pointer as the anchor.
    func zoomPageIn() {
        applyZoom(BoardTransform.zoomStep, anchoredAt: pointerAnchor())
    }

    func zoomPageOut() {
        applyZoom(1 / BoardTransform.zoomStep, anchoredAt: pointerAnchor())
    }

    /// The anchor a keyboard zoom uses: the pointer's view point — keys zoom
    /// where the user is looking — falling back to the view's centre when the
    /// pointer does not sit on this display's window.
    private func pointerAnchor() -> CGPoint {
        guard let window else { return CGPoint(x: bounds.midX, y: bounds.midY) }
        let location = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let anchor = convert(location, from: nil)
        return bounds.contains(anchor) ? anchor : CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// Zooms the current page by the multiplicative factor, anchored at the
    /// view point: the page point under the anchor never moves, so drawing and
    /// the dot grid follow the pointer at every zoom.
    func applyZoom(_ factor: CGFloat, anchoredAt anchor: CGPoint) {
        let changed = board.zoom(to: board.currentPage.zoom * factor, anchoredAt: anchor)
        guard changed else { return }
        needsDisplay = true
        Diag.log(
            "board zoom zoom=\(String(format: "%.2f", board.currentPage.zoom)) "
                + "offset=\(board.currentPage.offset) page=\(board.currentIndex + 1)"
        )
    }

    /// Trackpad pinch: magnification events carry a multiplicative factor
    /// around the pointer, exactly the app's anchoring rule.
    override func magnify(with event: NSEvent) {
        guard event.magnification != 0 else { return }
        applyZoom(1 + event.magnification, anchoredAt: convert(event.locationInWindow, from: nil))
    }

    /// ⌘B — the current page's background flips between white and black. A
    /// page that follows the system resolves against the appearance first, so
    /// the flip starts from the colour the user actually sees.
    func togglePageBackground() {
        board.toggleBackground(isDark: isDarkAppearance)
        needsDisplay = true
        Diag.log("board background=\(board.currentPage.background.rawValue)")
    }

    /// Stashes the live session into the board, used when the panel is torn
    /// down so the page keeps its marks for the session.
    func storeBoardState() {
        board.adopt(session)
    }

    private func loadCurrentPage() {
        // The presented page changed: nothing of the old page's selection may
        // survive, or handles would grab at marks that are not on the canvas —
        // and the image layer's selection and gesture die with it too, since
        // the layer itself stays on its own page.
        clearSelection()
        isBoardImageSelected = false
        imageGesture = nil
        session = board.currentPage.session
        committedBounds.removeAll()
        needsDisplay = true
        onPageChanged?()
    }

    // MARK: - Page-routed history ops (T4/S5, T6b/S8)

    /// The staleness cases a page-carrying history step can hit when it is
    /// routed:
    /// — the step names a page index the board no longer has: the page was
    ///   deleted (the controller's remap and this view's own remap already
    ///   took such records out — see `onPageStructureChanged`), or the board
    ///   was rebuilt with different pages (a canvas rebuild keeps the same
    ///   board object, so this only happens on a restored or foreign board).
    ///   Routing refuses and the caller's pop loop skips the step — no trap,
    ///   no wrong page.
    /// — the step's page was deleted and remapped away: such steps never
    ///   reach here, they left the history at the structural change.
    /// — the page's journal no longer holds the clear/batch the step names as
    ///   its newest live op: the session's own guard refuses (`canUndoClear`,
    ///   `canUndoBatchMove`, the redo variants), the pop loop skips it.
    /// — a hard clear wiped the page's session: the controller purged the
    ///   entries at clear time (`isWipedByHardClear`), so none remains.
    ///
    /// The undo and redo of a clear (T4/S5) and a group move (T6b/S8) land on
    /// the page the step names, whatever page the display presents now. The
    /// presented page is the fast path — the view's live session is that
    /// page's session. Any other page is borrowed through
    /// `borrowSession(onPage:)`, which restores the presented page and every
    /// piece of the view's presentational state afterwards.

    /// The pages, newest last, where this view's Escape clears and group
    /// moves happened and still wait at the view layer. The plain
    /// `undoClearedMarks()` / `undoBatchMove()` path — a pop with no entry to
    /// name the page, the way a bare view is driven — pops these to reach the
    /// page the newest step happened on, never the presented one. The
    /// controller's entry-driven routing (`onPage:` variants) bypasses them:
    /// its global order decides there, and the session's own journal guards
    /// refuse any record these stacks drift past, so a plain-path stack that
    /// an entry-driven pop already consumed can at worst return a no-op, and
    /// a draw-between records can only defer to the journal, never misroute.
    /// The stacks still mirror the live history rather than accumulating:
    /// the entry-driven routing pops the record whose page it acted on
    /// (`popRecord(onPage:)`), a structural change remaps them with the
    /// deleted pages' records gone, and a hard clear drops the wiped page's
    /// records (see `clear()`), so a bare pop never walks a record that is
    /// not backed by a live journal op — and never grows past the history.
    /// Internal (readable) for the tests, which assert the boundedness.
    private(set) var clearUndoPages: [Int] = []
    private(set) var clearRedoPages: [Int] = []
    private(set) var batchUndoPages: [Int] = []
    private(set) var batchRedoPages: [Int] = []

    /// The base ops of the global history at the view layer, against whatever
    /// session the view holds: what the plain OverlayView methods do. Both
    /// callers — the entry-driven `onPage:` variants and the record-driven
    /// overrides — go through these wrappers, so the record bookkeeping
    /// happens exactly once, at the call surface, and `super` is never
    /// reached from inside the borrowing closure.
    private func undoClearedMarksOnSession() -> Bool { super.undoClearedMarks() }
    private func redoClearedMarksOnSession() -> Bool { super.redoClearedMarks() }
    private func undoBatchMoveOnSession() -> Bool { super.undoBatchMove() }
    private func redoBatchMoveOnSession() -> Bool { super.redoBatchMove() }

    /// Runs a history op against the page the step names, never the page the
    /// display happens to present. The board's presented page moves to the
    /// routed page, the view's session loads it, the op runs and adopts its
    /// result back through the board sink (which writes `session` into
    /// `pages[currentIndex]` — the routed index while the borrow lasts), and
    /// the presented page, selection and bounds cache come back exactly as
    /// they were: the user never sees the other page and the presented page's
    /// state never changes. An index outside the board's pages is stale — the
    /// guard refuses and the caller's pop loop skips the step.
    private func borrowSession(onPage pageIndex: Int, _ operation: () -> Bool) -> Bool {
        guard pageIndex >= 0, pageIndex < board.count else { return false }
        guard pageIndex != board.currentIndex else { return operation() }
        let presentedIndex = board.currentIndex
        let presentedSelection = selectedMarkIDs
        let presentedBounds = committedBounds
        board.select(index: pageIndex)
        session = board.currentPage.session
        let routed = operation()
        board.select(index: presentedIndex)
        session = board.currentPage.session
        restoreSelection(presentedSelection)
        committedBounds = presentedBounds
        return routed
    }

    /// Undo of the clear the popped entry names, on the page it happened on
    /// (T4/S5): the entry-driven path. On success the record naming this page
    /// leaves the bare-path stack — the global pop consumed the newest live
    /// clear op of that page, exactly what the stack's last matching record
    /// names — so the stacks mirror the live history instead of accumulating
    /// every clear the board session ever performed. The journal guard still
    /// defends any residual drift: a record kept by mistake can at worst make
    /// a bare pop return a no-op.
    @discardableResult
    func undoClearedMarks(onPage pageIndex: Int) -> Bool {
        let routed = borrowSession(onPage: pageIndex, self.undoClearedMarksOnSession)
        if routed { popRecord(&clearUndoPages, onPage: pageIndex) }
        return routed
    }

    /// Redo of the clear the popped entry names, on the page it happened on
    /// (T4/S5): the entry-driven path, with the same record bookkeeping as
    /// the undo side above.
    @discardableResult
    func redoClearedMarks(onPage pageIndex: Int) -> Bool {
        let routed = borrowSession(onPage: pageIndex, self.redoClearedMarksOnSession)
        if routed { popRecord(&clearRedoPages, onPage: pageIndex) }
        return routed
    }

    /// Undo of the group move the popped entry names, on the page it happened
    /// on (T6b/S8): the entry-driven path, with the same record bookkeeping
    /// as the clear side above.
    @discardableResult
    func undoBatchMove(onPage pageIndex: Int) -> Bool {
        let routed = borrowSession(onPage: pageIndex, self.undoBatchMoveOnSession)
        if routed { popRecord(&batchUndoPages, onPage: pageIndex) }
        return routed
    }

    /// Redo of the group move the popped entry names, on the page it happened
    /// on (T6b/S8): the entry-driven path, with the same record bookkeeping
    /// as the clear side above.
    @discardableResult
    func redoBatchMove(onPage pageIndex: Int) -> Bool {
        let routed = borrowSession(onPage: pageIndex, self.redoBatchMoveOnSession)
        if routed { popRecord(&batchRedoPages, onPage: pageIndex) }
        return routed
    }

    /// Removes the last record naming `pageIndex` — the stack is ordered
    /// oldest first, so the last one is this page's newest pending clear (or
    /// batch move), which is the journal op the entry-driven routing just
    /// consumed. A page can hold several pending steps (clear, draw, clear),
    /// and each global pop retires exactly one of them.
    private func popRecord(_ pages: inout [Int], onPage pageIndex: Int) {
        if let index = pages.lastIndex(of: pageIndex) { pages.remove(at: index) }
    }

    /// Global undo of the Escape clear (T4/S5) through the view alone: the
    /// newest clear this view performed, on the page it happened on. Records
    /// whose page refuses — its journal no longer holds the clear as its
    /// newest live op — are skipped exactly like the controller's pop loop
    /// skips a stale entry, so a stale record can never mutate another page.
    @discardableResult
    override func undoClearedMarks() -> Bool {
        while let page = clearUndoPages.popLast() {
            guard borrowSession(onPage: page, self.undoClearedMarksOnSession) else { continue }
            clearRedoPages.append(page)
            return true
        }
        return false
    }

    /// Global redo of the Escape clear (T4/S5) through the view alone: the
    /// newest undone clear, back onto the page it happened on.
    @discardableResult
    override func redoClearedMarks() -> Bool {
        while let page = clearRedoPages.popLast() {
            guard borrowSession(onPage: page, self.redoClearedMarksOnSession) else { continue }
            clearUndoPages.append(page)
            return true
        }
        return false
    }

    /// Global undo of the group move (T6b/S8) through the view alone: the
    /// newest move this view performed, on the page it happened on, with the
    /// same skip-stale rule as the clear side.
    @discardableResult
    override func undoBatchMove() -> Bool {
        while let page = batchUndoPages.popLast() {
            guard borrowSession(onPage: page, self.undoBatchMoveOnSession) else { continue }
            batchRedoPages.append(page)
            return true
        }
        return false
    }

    /// Global redo of the group move (T6b/S8) through the view alone: the
    /// newest undone move, back onto the page it happened on.
    @discardableResult
    override func redoBatchMove() -> Bool {
        while let page = batchRedoPages.popLast() {
            guard borrowSession(onPage: page, self.redoBatchMoveOnSession) else { continue }
            batchUndoPages.append(page)
            return true
        }
        return false
    }

    /// Remaps the view's own page records through a structural page change,
    /// the same mapping the controller applies to its entries; records whose
    /// page no longer exists leave the stack safely.
    private func remapRecords(_ pages: inout [Int], mapping: (Int) -> Int?) {
        pages = pages.compactMap(mapping)
    }

    // MARK: - Gesture cursors (S3)

    /// The running gesture's cursor, shown instead of the tool cursor through
    /// the base class's cursor re-assertions (cursorUpdate, mouseMoved, …):
    /// closed hand while a pan drag runs, open hand while space is held, a
    /// zoom cursor while ⌘ + scroll runs. Derived from the gesture state, so
    /// every exit path (drag end, space release, scroll end, view
    /// disappearing) reverts it simply by clearing that state.
    override var gestureCursor: NSCursor? {
        if isPanning { return .closedHand }
        if isSpacePanning { return .openHand }
        if isZoomScrolling { return zoomScrollCursor }
        return nil
    }

    /// The zoom cursor while ⌘ + scroll runs. AppKit ships `NSCursor.zoomIn` /
    /// `.zoomOut` — the magnifier cursors — and they are used here rather
    /// than inventing art. The documented gap (S2's "dentro de lo posible"):
    /// AppKit has no dynamic in/out zoom cursor, so the sign of the event's
    /// delta picks which magnifier shows; a zero delta keeps the last one.
    private var zoomScrollCursor: NSCursor { lastZoomScrollDelta >= 0 ? .zoomIn : .zoomOut }

    // MARK: - Zooming with ⌘ + scroll (S1)

    /// ⌘ + scroll zooms the board through the one zoom model
    /// (`BoardTransform.zoomed(forScrollDelta:isZooming:anchoredAt:)` in
    /// StareCore), anchored at the pointer, and the gesture's own state
    /// machine (`ScrollZoom.Gesture`, v0.5/S2) decides what each event does:
    /// an event against the gesture's locked direction holds, momentum holds,
    /// and the delta stays raw — content-directed as AppKit reports it, never
    /// normalised across the natural-scrolling setting (see the
    /// "direction preserved" note in `ScrollZoom.Gesture`). Plain scroll
    /// without ⌘ never changes the zoom — the pure rule refuses it, and this
    /// handler returns without touching anything.
    override func scrollWheel(with event: NSEvent) {
        let zooming = event.modifierFlags.contains(.command)
        guard zooming || isZoomScrolling else {
            // A plain scroll is not a zoom gesture: hand it down the responder
            // chain untouched rather than swallowing it here.
            super.scrollWheel(with: event)
            return
        }
        defer {
            // The trackpad's closing events end the gesture — `.ended` when
            // the fingers lift, `.cancelled` when the system interrupts the
            // gesture — so the momentum events that follow and the next
            // gesture start from a released lock. AppKit's raw phase values
            // match `ScrollZoom.Phase` (probed: began 1, changed 4, ended 8,
            // cancelled 16), so the map below is a straight renumbering.
            if event.phase == .ended || event.phase == .cancelled { endZoomScroll() }
        }
        guard zooming else {
            // ⌘ let go mid-gesture: the gesture is over.
            endZoomScroll()
            return
        }
        let decision = scrollZoomGesture.decide(for: ScrollZoom.Event(
            deltaY: event.scrollingDeltaY,
            phase: ScrollZoom.Phase(rawValue: Int(event.phase.rawValue)) ?? .none,
            momentumPhase: ScrollZoom.MomentumPhase(rawValue: Int(event.momentumPhase.rawValue)) ?? .none
        ))
        guard case let .zoom(factor) = decision else {
            // The gesture's own rule rejects the event — momentum, or a delta
            // against the locked direction: nothing zooms, nothing changes.
            return
        }
        applyZoom(factor, anchoredAt: convert(event.locationInWindow, from: nil))
        isZoomScrolling = true
        lastZoomScrollDelta = factor > 1 ? 1 : -1
        reassertCursor()
    }

    private func endZoomScroll() {
        isZoomScrolling = false
        scrollZoomGesture = ScrollZoom.Gesture()
        reassertCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        // A phaseless mouse-wheel scroll has no end event: the pointer moving
        // again is what says the zoom gesture is over.
        if isZoomScrolling { endZoomScroll() }
        super.mouseMoved(with: event)
    }

    /// The view going away ends any gesture: nothing stale survives the board
    /// closing, so the next window shows its own cursor.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window == nil else { return }
        isSpacePanning = false
        isMiddlePanning = false
        lastPanPoint = nil
        isZoomScrolling = false
        scrollZoomGesture = ScrollZoom.Gesture()
        // The image layer's in-flight state dies with the window too.
        isBoardImageSelected = false
        imageGesture = nil
    }

    // MARK: - Panning the endless canvas

    private var isPanning: Bool { (isSpacePanning || isMiddlePanning) && lastPanPoint != nil }

    /// Shifts the current page's pan offset: the marks on screen shift by the
    /// opposite of `delta` and their stored points never change. The offset is
    /// page space, so a screen drag is divided by the zoom — panning keeps
    /// following the pointer at any zoom.
    func pan(byPointerDelta delta: CGSize) {
        board.pan(by: CGSize(width: -delta.width / zoom, height: -delta.height / zoom))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if isSpacePanning || event.buttonNumber == 2 {
            isMiddlePanning = event.buttonNumber == 2
            lastPanPoint = convert(event.locationInWindow, from: nil)
            reassertCursor() // pan drag starts → closed hand (S3)
            return
        }
        // The select tool (V) claims the page's image layer, the way the
        // editor's canvas does: the image is content you select and transform,
        // and it needs no modifier to remember (B4, the owner's second pass).
        if state.tool == .select, !event.modifierFlags.contains(.command) {
            if grabBoardImage(at: convert(event.locationInWindow, from: nil)) { return }
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanning {
            let point = convert(event.locationInWindow, from: nil)
            if let last = lastPanPoint {
                pan(byPointerDelta: CGSize(width: point.x - last.x, height: point.y - last.y))
            }
            lastPanPoint = point
            return
        }
        // The image gesture's live application: the whole drag is ONE value
        // change on the layer, applied per event and clamped by the model.
        if let gesture = imageGesture, board.currentPage.image != nil {
            let viewPoint = convert(event.locationInWindow, from: nil)
            switch gesture {
            case let .move(grab, startPageRect):
                // The pointer's page-space travel since the grab, applied to
                // the placement it started from: one point of travel is one
                // page point at any zoom, so the layer stays under the pointer.
                let pagePoint = viewTransform.point(toPage: viewPoint)
                let destination = startPageRect.offsetBy(
                    dx: pagePoint.x - grab.x,
                    dy: pagePoint.y - grab.y
                )
                board.placePageImage(at: destination, clampedTo: imageGestureCanvas)
            case let .resize(handle, startViewRect):
                // The resize runs in view space — the grip rules are the
                // editor's — and lands clamped in page space. Shift holds the
                // shape, the way it does everywhere the V tool resizes (B4).
                let region = event.modifierFlags.contains(.shift)
                    ? EditorCropRule.lockedRegion(
                        from: startViewRect, dragging: handle, to: viewPoint, in: bounds)
                    : EditorCropRule.region(
                        from: startViewRect, dragging: handle, to: viewPoint, in: bounds)
                board.placePageImage(at: viewTransform.rect(toPage: region), clampedTo: imageGestureCanvas)
            }
            needsDisplay = true
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if imageGesture != nil {
            // One edit per drag, reported with the placement it started from:
            // a move and a resize are single steps on the undo stream.
            let before = imageGestureStartLayer
            imageGestureStartLayer = nil
            // The gesture is over: the value change already sits on the layer
            // (applied live and clamped by the model). No journal step here —
            // see the undo note on `deleteBoardImageIfSelected`.
            imageGesture = nil
            needsDisplay = true
            noteBoardImageEdit(before: before)
            return
        }
        let wasPanning = isPanning
        if event.buttonNumber == 2 {
            isMiddlePanning = false
            lastPanPoint = nil
            if wasPanning { reassertCursor() } // drag end → open hand (space held) or the tool cursor
            return
        }
        lastPanPoint = nil
        if wasPanning { reassertCursor() }
        super.mouseUp(with: event)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Escape clears the PAGE, and the page's image layer is part of it.
        // The overlay's clear knows strokes only, so the layer used to survive
        // a gesture whose hint promises "esc clear page". A mark selection
        // still goes first — one stray click never costs the page — and, like
        // every other image-lane edit (⌫, ⌥-drag), removing the layer is not
        // journalled.
        if event.keyCode == 53 {
            let hadMarkSelection = !selectedMarkIDs.isEmpty
            super.keyDown(with: event)
            if !hadMarkSelection { removePageImageOnEscape() }
            return
        }
        // Space pans (the app-wide convention); holding it never draws.
        if event.keyCode == 49 {
            if !event.isARepeat {
                isSpacePanning = true
                reassertCursor() // space held → open hand (S3)
            }
            return
        }
        let modifiers = event.modifierFlags
        // ⌫ — with the page's image layer selected (and no mark selection to
        // take the key first), the layer goes away.
        if event.keyCode == 51 || event.keyCode == 117, deleteBoardImageIfSelected() { return }
        // ⌥← / ⌥→ reorder the current page inside the board.
        if modifiers.contains(.option), !modifiers.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "\u{F702}": // ⌥←
                moveCurrentPageLeft()
                return
            case "\u{F703}": // ⌥→
                moveCurrentPageRight()
                return
            default:
                break
            }
        }
        if modifiers.contains(.command), let characters = event.charactersIgnoringModifiers {
            switch characters {
            case "\u{F702}": // ⌘←
                selectPreviousPage()
                return
            case "\u{F703}": // ⌘→
                selectNextPage()
                return
            case "\u{7F}": // ⌘⌫
                deleteCurrentPage()
                return
            case "0": // ⌘0 — pan and zoom back together (T5/S5)
                resetPageView()
                return
            case "+", "=": // ⌘+ / ⌘=
                zoomPageIn()
                return
            case "-", "_": // ⌘−
                zoomPageOut()
                return
            case "b", "B": // ⌘B
                togglePageBackground()
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isSpacePanning = false
            // Space release → the tool cursor, or the closed hand if a pan
            // drag is still running.
            reassertCursor()
            return
        }
        super.keyUp(with: event)
    }

    /// A hard clear wipes the presented page's whole journal with no undo
    /// step left behind (the deactivate-path `canvas.clear()` and the
    /// toolbar's clear both land here), so every bare-path record naming
    /// this page is dead: the journal guard would refuse each one, but the
    /// records would still linger and accumulate across the board's open
    /// lifetime. Dropping them here keeps the record stacks bounded by the
    /// live history — the other pages' records stay, their journals are
    /// untouched.
    override func clear() {
        super.clear()
        let wipedPage = board.currentIndex
        clearUndoPages.removeAll { $0 == wipedPage }
        clearRedoPages.removeAll { $0 == wipedPage }
        batchUndoPages.removeAll { $0 == wipedPage }
        batchRedoPages.removeAll { $0 == wipedPage }
    }
}
