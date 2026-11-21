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
    /// Space is held: drags pan the canvas instead of drawing.
    private var isSpacePanning = false
    /// Middle-button drag pans the canvas too.
    private var isMiddlePanning = false
    private var lastPanPoint: CGPoint?

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
    }

    /// Cache of the beneath image: dragging a blur mark repaints per frame,
    /// and the content beneath it only changes when the page's marks,
    /// background, pan, scale or size change — all of which are in the key.
    private var beneathCache: (key: BeneathKey, image: CGImage)?

    /// The page as it is rendered beneath `stroke`: page colour plus every
    /// committed mark before it in draw order (the mark being dragged sits
    /// above everything already committed). The pan is applied here the same
    /// way the capture applies it, so the image covers view space and the
    /// view's crop lands where the board shows the patch.
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
        let key = BeneathKey(
            strokes: beneath,
            background: board.currentPage.background,
            isDark: isDark,
            transform: board.currentPage.transform,
            scale: scale,
            size: bounds.size
        )
        if let cached = beneathCache, cached.key == key { return cached.image }
        guard let base = board.currentPage.background.captureBase(
            width: Int(bounds.width * scale),
            height: Int(bounds.height * scale),
            isDark: isDark
        ) else { return nil }
        guard let image = MarkCompositor.composite(
            marks: beneath,
            over: base,
            scale: scale,
            diffusesContent: true,
            offset: board.currentPage.offset,
            zoom: board.currentPage.zoom
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
    override func drawBackground(in context: CGContext, dirty dirtyRect: NSRect) {
        context.setFillColor(board.currentPage.background.cgColor(isDark: isDarkAppearance))
        context.fill(bounds)
        drawDotGrid(in: context, dirty: dirtyRect)
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
    /// page the model refuses and the board stays as it was.
    @discardableResult
    func deleteCurrentPage() -> Bool {
        board.adopt(session)
        let deleted = board.deleteCurrentPage()
        if deleted {
            loadCurrentPage()
        }
        Diag.log("board delete page deleted=\(deleted) pages=\(board.count) current=\(board.currentIndex + 1)")
        return deleted
    }

    /// ⌥← / ⌥→ — reorders: the current page swaps with its neighbour and stays
    /// current. Refused at the ends, exactly like ‹ at the first page.
    @discardableResult
    func moveCurrentPageLeft() -> Bool {
        board.adopt(session)
        let moved = board.moveCurrentPageLeft()
        if moved {
            loadCurrentPage()
        }
        Diag.log("board move left moved=\(moved) current=\(board.currentIndex + 1)/\(board.count)")
        return moved
    }

    @discardableResult
    func moveCurrentPageRight() -> Bool {
        board.adopt(session)
        let moved = board.moveCurrentPageRight()
        if moved {
            loadCurrentPage()
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
        // survive, or handles would grab at marks that are not on the canvas.
        clearSelection()
        session = board.currentPage.session
        committedBounds.removeAll()
        needsDisplay = true
        onPageChanged?()
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
            return
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
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            isMiddlePanning = false
            lastPanPoint = nil
            return
        }
        lastPanPoint = nil
        super.mouseUp(with: event)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Space pans (the app-wide convention); holding it never draws.
        if event.keyCode == 49 {
            if !event.isARepeat { isSpacePanning = true }
            return
        }
        let modifiers = event.modifierFlags
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
            return
        }
        super.keyUp(with: event)
    }
}
