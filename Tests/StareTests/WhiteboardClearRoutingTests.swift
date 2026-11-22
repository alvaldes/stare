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
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
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
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
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
}
