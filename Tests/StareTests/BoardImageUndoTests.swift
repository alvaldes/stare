import AppKit
import XCTest

@testable import Stare
import StareCore

/// L8: the board's image layer is on the SAME undo stream as the marks. Each
/// edit reports itself once with the placement before and after, and the model
/// restores either side, which is what makes undo and redo work on it.
@MainActor
final class BoardImageUndoTests: XCTestCase {
    private let size = CGSize(width: 900, height: 600)

    private func solid(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func buttonEvent(
        _ type: NSEvent.EventType, at point: CGPoint, window: NSWindow
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: CGPoint(x: point.x, y: size.height - point.y),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1,
            clickCount: 1, pressure: 1
        )
    }

    private func drag(_ view: WhiteboardView, window: NSWindow, from start: CGPoint, to end: CGPoint) {
        view.mouseDown(with: buttonEvent(.leftMouseDown, at: start, window: window)!)
        view.mouseDragged(with: buttonEvent(.leftMouseDragged, at: end, window: window)!)
        view.mouseUp(with: buttonEvent(.leftMouseUp, at: end, window: window)!)
    }

    private func makeBoardView() throws -> (view: WhiteboardView, board: WhiteboardPages, window: NSWindow) {
        try XCTSkipIf(NSScreen.main == nil, "no display: the window-backed gesture paths cannot run")
        let state = EditorState()
        state.tool = .select
        let board = WhiteboardPages()
        let view = WhiteboardView(
            frame: CGRect(origin: .zero, size: size), state: state, board: board, onEscape: {}
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = view
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return (view, board, window)
    }

    func testAPasteReportsTheEmptyPageItReplaced() throws {
        let (view, _, window) = try makeBoardView()
        defer { window.orderOut(nil) }
        var edits: [(BoardImage?, BoardImage?)] = []
        view.onBoardImageEdited = { before, after, _ in edits.append((before, after)) }

        view.pasteImage(solid(100, 80))

        XCTAssertEqual(edits.count, 1, "one paste, one step")
        XCTAssertNil(edits.first?.0, "the page carried nothing before it")
        XCTAssertNotNil(edits.first?.1)
    }

    func testADragReportsOneEditFromWhereTheLayerStarted() throws {
        let (view, board, window) = try makeBoardView()
        defer { window.orderOut(nil) }
        view.pasteImage(solid(100, 80))
        let pasted = try XCTUnwrap(board.currentPage.image)
        var edits: [(BoardImage?, BoardImage?)] = []
        view.onBoardImageEdited = { before, after, _ in edits.append((before, after)) }

        // Several dragged events, one gesture: the stream gets one step.
        view.mouseDown(with: buttonEvent(.leftMouseDown, at: CGPoint(x: 450, y: 300), window: window)!)
        for dx in [10.0, 20.0, 30.0] {
            view.mouseDragged(with: buttonEvent(.leftMouseDragged, at: CGPoint(x: 450 + dx, y: 300), window: window)!)
        }
        view.mouseUp(with: buttonEvent(.leftMouseUp, at: CGPoint(x: 480, y: 300), window: window)!)

        XCTAssertEqual(edits.count, 1, "a drag is one step, not one per event")
        XCTAssertEqual(edits.first?.0?.rect, pasted.rect, "it starts from where the layer was")
        let moved = try XCTUnwrap(edits.first?.1?.rect.origin.x)
        XCTAssertEqual(moved, pasted.rect.origin.x + 30, accuracy: 0.5)
    }

    func testDeletingTheLayerReportsItAndTheModelPutsItBack() throws {
        let (view, board, window) = try makeBoardView()
        defer { window.orderOut(nil) }
        view.pasteImage(solid(100, 80))
        let pasted = try XCTUnwrap(board.currentPage.image)
        var edits: [(BoardImage?, BoardImage?)] = []
        view.onBoardImageEdited = { before, after, page in edits.append((before, after)) }

        let escape = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false, keyCode: 53
        )!
        view.keyDown(with: escape)

        XCTAssertNil(board.currentPage.image, "esc removed the layer")
        XCTAssertEqual(edits.count, 1, "and reported the removal")
        XCTAssertEqual(edits.first?.0?.id, pasted.id, "with the layer it took away")

        // Undo: the model puts that exact layer back, and the board can show it.
        XCTAssertTrue(view.restorePageImage(edits[0].0, onPage: 0))
        XCTAssertEqual(board.currentPage.image?.id, pasted.id)
        XCTAssertEqual(board.currentPage.image?.rect, pasted.rect)
    }

    /// The whole path: the controller's own undo and redo, which is what ⌘Z and
    /// ⇧⌘Z reach, on a real board.
    func testUndoAndRedoOnTheControllerTakeTheLayerOffAndPutItBack() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screens: the board canvases need one")
        _ = NSApplication.shared
        let controller = OverlayController(captureService: CaptureService())
        controller.toggleBoard()
        guard controller.isBoardActive,
            let view = controller.selfTestViews.compactMap({ $0 as? WhiteboardView }).first
        else {
            controller.toggleBoard()
            throw XCTSkip("board canvas could not be created")
        }
        defer { controller.toggleBoard() }

        view.pasteImage(solid(40, 20))
        let pasted = try XCTUnwrap(view.board.currentPage.image)
        XCTAssertEqual(controller.historyEntryCount, 1, "the paste is one step on the stream")

        controller.undo()
        XCTAssertNil(view.board.currentPage.image, "⌘Z takes the paste back off the page")

        controller.redo()
        XCTAssertEqual(view.board.currentPage.image?.id, pasted.id, "⇧⌘Z puts that same layer back")
        XCTAssertEqual(view.board.currentPage.image?.rect, pasted.rect)
    }

    func testRestoringAPageThatNoLongerExistsReportsNothing() throws {
        let (view, _, window) = try makeBoardView()
        defer { window.orderOut(nil) }
        XCTAssertFalse(view.restorePageImage(nil, onPage: 7), "no such page, nothing to restore")
    }
}
