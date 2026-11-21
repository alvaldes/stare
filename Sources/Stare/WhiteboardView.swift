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
final class WhiteboardView: OverlayView {
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WhiteboardView is created in code only")
    }

    override var panOffset: CGSize { board.currentPage.offset }

    // MARK: - Painting

    override func drawBackground(in context: CGContext) {
        context.setFillColor(board.currentPage.background.cgColor)
        context.fill(bounds)
    }

    override func showIntroHint() {
        showHint(
            "Whiteboard · ⌘← ⌘→ pages · ⌘B background · space-drag pan · esc to leave",
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

    /// ⌘B — the current page's background flips between white and black.
    func togglePageBackground() {
        board.toggleBackground()
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

    /// Shifts the current page's pan offset: the marks on screen move by the
    /// opposite of `delta`, and their stored points never change.
    func pan(byPointerDelta delta: CGSize) {
        board.pan(by: CGSize(width: -delta.width, height: -delta.height))
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
        if modifiers.contains(.command), let characters = event.charactersIgnoringModifiers {
            switch characters {
            case "\u{F702}": // ⌘←
                selectPreviousPage()
                return
            case "\u{F703}": // ⌘→
                selectNextPage()
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
