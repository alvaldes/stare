import AppKit
import XCTest
@testable import Stare
import StareCore

/// The controller's global history needs page identity: a `.clear` entry names
/// a display, and undo must reach the page the clear happened on rather than
/// whichever page the display happens to show.
@MainActor
final class WhiteboardClearRoutingTests: XCTestCase {
    private let size = CGSize(width: 900, height: 600)

    /// The controller-path probes show a board canvas for every display and
    /// a palette on the pointer's display. Both placements write the
    /// toolbar's persisted anchor/screen (`ToolbarPanel.persistAnchor`), so
    /// snapshot and restore them here like `ToolbarPanelLiveResizeTests`
    /// does, leaving no mark on the host's own defaults.
    private let anchorKeys = [ToolbarPanel.anchorKey, ToolbarPanel.screenKey]
    private var savedDefaults: [(String, Any?)] = []

    override func setUp() {
        super.setUp()
        savedDefaults = anchorKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
    }

    override func tearDown() {
        for (key, value) in savedDefaults {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type, location: CGPoint(x: point.x, y: size.height - point.y),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1,
            clickCount: 1, pressure: 1)
    }

    private func drag(_ view: OverlayView, window: NSWindow, from start: CGPoint, to end: CGPoint) {
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: start, window: window)!)
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: end, window: window)!)
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: end, window: window)!)
    }

    private func escape(_ view: NSView) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false, keyCode: 53)!
        view.keyDown(with: event)
    }

    func testUndoOfAClearReachesThePageItHappenedOn() throws {
        let state = EditorState()
        state.tool = .pen
        state.ink = .blue
        let board = WhiteboardPages()
        let view = WhiteboardView(
            frame: CGRect(origin: .zero, size: size), state: state, board: board, onEscape: {})
        try XCTSkipIf(NSScreen.screens.isEmpty, "the probe shows a window, so it needs a screen")
        let window = NSWindow(
            contentRect: try XCTUnwrap(
                PrimaryScreenTestWindow.frame(for: size),
                "the primary screen cannot host the probe"),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        defer { window.orderOut(nil) }
        view.onClearMarks = { _ = view.clearForUndo() }

        drag(view, window: window, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 350, y: 190))
        XCTAssertEqual(board.pages[0].session.strokes.count, 1)
        escape(view)
        XCTAssertTrue(board.pages[0].session.strokes.isEmpty)

        view.selectNextPage()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        drag(view, window: window, from: CGPoint(x: 400, y: 300), to: CGPoint(x: 600, y: 340))
        XCTAssertEqual(board.pages[1].session.strokes.count, 1)
        escape(view)
        XCTAssertTrue(board.pages[1].session.strokes.isEmpty)

        view.selectPreviousPage()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(board.currentIndex, 0)
        let routed = view.undoClearedMarks()
        XCTAssertTrue(routed, "the newest clear must be undoable")
        XCTAssertEqual(board.pages[1].session.strokes.count, 1, "⌘Z must restore the clear that happened on page 2")
        XCTAssertEqual(board.pages[0].session.strokes.count, 0, "page 1's earlier clear is a different step")
    }

    func testAnEntryWhosePageWasRemovedIsSkippedAndTheNextEntryStillWorks() throws {
        let state = EditorState()
        state.tool = .pen
        state.ink = .blue
        let board = WhiteboardPages()
        let view = WhiteboardView(
            frame: CGRect(origin: .zero, size: size), state: state, board: board, onEscape: {})
        try XCTSkipIf(NSScreen.screens.isEmpty, "the probe shows a window, so it needs a screen")
        let window = NSWindow(
            contentRect: try XCTUnwrap(
                PrimaryScreenTestWindow.frame(for: size),
                "the primary screen cannot host the probe"),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        defer { window.orderOut(nil) }
        view.onClearMarks = { _ = view.clearForUndo() }

        drag(view, window: window, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 350, y: 190))
        escape(view)
        view.selectNextPage()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        drag(view, window: window, from: CGPoint(x: 400, y: 300), to: CGPoint(x: 600, y: 340))
        escape(view)
        XCTAssertEqual(board.count, 2)

        // The page is removed: ⌘⌫ deletes the presented page (page 2) through
        // the view, and the clear that happened there becomes stale.
        view.deleteCurrentPage()
        XCTAssertEqual(board.count, 1)

        // Routing the removed page's clear refuses: nothing traps and no
        // other page mutates.
        XCTAssertFalse(view.undoClearedMarks(onPage: 1), "a removed page's clear routes nowhere")
        XCTAssertTrue(board.pages[0].session.strokes.isEmpty, "the stale entry must not mutate another page")

        // The next entry still works: page 1's clear survives the removal.
        XCTAssertTrue(view.undoClearedMarks())
        XCTAssertEqual(board.pages[0].session.strokes.count, 1)

        // Nothing is left to undo: the removed page's clear can never come back.
        XCTAssertFalse(view.undoClearedMarks())
        XCTAssertEqual(board.pages[0].session.strokes.count, 1)
    }

    // MARK: - Controller-path page identity (N3/N4/N5)

    /// The controller-path tests below mirror the selftest's board-history
    /// section: a real OverlayController with real board canvases, driven
    /// through the views' own input path — never by calling a journal method.
    private func makeController() throws -> (OverlayController, WhiteboardView, NSWindow) {
        guard !NSScreen.screens.isEmpty else {
            throw XCTSkip("no screens: the board canvases need one")
        }
        // xctest runs without an initialized NSApplication: the controller's
        // board lifecycle talks to NSApp, so create it here first.
        _ = NSApplication.shared
        let controller = OverlayController(captureService: CaptureService())
        controller.state.tool = .pen
        controller.state.ink = .blue
        controller.toggleBoard()
        guard controller.isBoardActive,
              let view = controller.selfTestViews.first as? WhiteboardView,
              let panel = view.window else {
            controller.toggleBoard()
            throw XCTSkip("board canvas could not be created")
        }
        // Confinement (see `PrimaryScreenTestWindow`): the controller just
        // showed a board canvas for every display and the palette on the
        // pointer's display — neither screen is the test's to choose, and
        // the human watches the others while the suite runs. Everything the
        // board showed moves onto the primary screen's visible frame in the
        // same AppKit pass the windows were ordered front in — before the
        // first runloop turn below — so the window server only ever renders
        // the confined frames.
        let primary = try XCTUnwrap(NSScreen.screens.first, "the board canvases need a display")
        let boardsFrame = try XCTUnwrap(
            PrimaryScreenTestWindow.frame(for: primary.visibleFrame.size),
            "the primary screen cannot host the board canvases")
        for canvas in controller.selfTestViews.compactMap(\.window) {
            canvas.setFrame(boardsFrame, display: false)
        }
        for case let toolbar as ToolbarPanel in NSApplication.shared.windows {
            guard let paletteFrame = PrimaryScreenTestWindow.frame(for: toolbar.frame.size)
            else { continue }
            toolbar.setFrameOrigin(paletteFrame.origin)
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        return (controller, view, panel)
    }

    /// Real ⌘Z (⇧⌘Z when shifted) through the view's key handling, which
    /// routes to the controller's global pop loop.
    private func commandZ(_ view: NSView, shifted: Bool = false) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero,
            modifierFlags: shifted ? [.command, .shift] : [.command],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, characters: "z", charactersIgnoringModifiers: "z",
            isARepeat: false, keyCode: 6)!
        view.keyDown(with: event)
    }

    func testDeletingAPageTakesItsEntriesOutOfTheGlobalHistory() throws {
        let (controller, view, panel) = try makeController()
        defer { controller.toggleBoard() }
        let board = view.board

        // Draw and clear on page 1, then on page 2, each through the real
        // Escape path the controller wires. Four entries, the page-carrying
        // ones naming the page each clear happened on.
        drag(view, window: panel, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 350, y: 190))
        XCTAssertEqual(board.pages[0].session.strokes.count, 1)
        escape(view)
        XCTAssertTrue(board.pages[0].session.strokes.isEmpty)

        view.selectNextPage()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        drag(view, window: panel, from: CGPoint(x: 400, y: 300), to: CGPoint(x: 600, y: 340))
        XCTAssertEqual(board.pages[1].session.strokes.count, 1)
        escape(view)
        XCTAssertTrue(board.pages[1].session.strokes.isEmpty)

        XCTAssertEqual(controller.historyEntryCount, 4)
        XCTAssertEqual(controller.historyNamedPages, [nil, 0, nil, 1] as [Int?])

        // The presented page (page 2) is deleted: its clear and the mark
        // entries naming its marks leave the global history; page 1's stay.
        view.deleteCurrentPage()
        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(controller.historyEntryCount, 2, "the deleted page's entries must leave the history")
        XCTAssertEqual(controller.historyNamedPages, [nil, 0] as [Int?])

        // The surviving entries still work in order, from whichever page the
        // user presents: the clear comes back first, then the draw undoes.
        view.selectPreviousPage()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        commandZ(view)
        XCTAssertEqual(board.pages[0].session.strokes.count, 1, "page 1's clear restores")
        XCTAssertEqual(controller.historyEntryCount, 1)
        commandZ(view)
        XCTAssertTrue(board.pages[0].session.strokes.isEmpty, "the draw undoes next")
        XCTAssertEqual(controller.historyEntryCount, 0, "nothing may keep consuming steps")
    }

    func testAHardClearOfOnePageKeepsAnotherPagesClearUndoable() throws {
        let (controller, view, panel) = try makeController()
        defer { controller.toggleBoard() }
        let board = view.board

        // Draw and clear on page 1, then on page 2.
        drag(view, window: panel, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 350, y: 190))
        escape(view)
        view.selectNextPage()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        drag(view, window: panel, from: CGPoint(x: 400, y: 300), to: CGPoint(x: 600, y: 340))
        escape(view)
        XCTAssertEqual(controller.historyEntryCount, 4)

        // A hard clear wipes only the page it ran on (the presented one, the
        // toolbar's clear target): page 2's entries die, page 1's survive.
        controller.clearAll()
        XCTAssertEqual(controller.historyEntryCount, 2, "only the cleared page's entries die")
        XCTAssertEqual(controller.historyNamedPages, [nil, 0] as [Int?])

        view.selectPreviousPage()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        commandZ(view)
        XCTAssertEqual(board.pages[0].session.strokes.count, 1, "page 1's clear survives page 2's hard clear")
        XCTAssertEqual(board.pages[1].session.strokes.count, 0, "page 2 stays hard-cleared")
    }

    func testTheViewPageRecordsStayBoundedByTheLiveHistory() throws {
        let (controller, view, panel) = try makeController()
        defer { controller.toggleBoard() }
        let board = view.board

        // Two Escape clears through the controller path: a page record each.
        drag(view, window: panel, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 350, y: 190))
        escape(view)
        view.selectNextPage()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        drag(view, window: panel, from: CGPoint(x: 400, y: 300), to: CGPoint(x: 600, y: 340))
        escape(view)
        XCTAssertEqual(view.clearUndoPages, [0, 1])
        XCTAssertEqual(view.clearRedoPages, [])
        XCTAssertEqual(view.batchUndoPages, [])
        XCTAssertEqual(view.batchRedoPages, [])

        // The controller path consumes both steps and their records come with
        // them, so the stacks never grow past the live history.
        view.selectPreviousPage()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        commandZ(view)
        XCTAssertEqual(view.clearUndoPages, [0])
        commandZ(view)
        XCTAssertEqual(view.clearUndoPages, [])
        XCTAssertFalse(view.undoClearedMarks(), "a bare pop with the history fully consumed must refuse, not act")
        XCTAssertEqual(board.pages[0].session.strokes.count, 1)

        // Fresh clears on both pages build the records up again …
        drag(view, window: panel, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 350, y: 190))
        escape(view)
        view.selectNextPage()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        drag(view, window: panel, from: CGPoint(x: 400, y: 300), to: CGPoint(x: 600, y: 340))
        escape(view)
        XCTAssertEqual(view.clearUndoPages, [0, 1])

        // … and a hard clear of the presented page (page 2) drops exactly its
        // own records; page 1's record stays backed by a live journal op.
        controller.clearAll()
        XCTAssertEqual(view.clearUndoPages, [0])
        view.selectPreviousPage()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        commandZ(view)
        XCTAssertEqual(board.pages[0].session.strokes.count, 2, "page 1's clear still undoes after page 2's hard clear")
    }
}
