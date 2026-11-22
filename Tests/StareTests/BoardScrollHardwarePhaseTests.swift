import AppKit
import XCTest
@testable import Stare
import StareCore

/// Real AppKit-shaped scroll events through the real
/// `WhiteboardView.scrollWheel` (T1/S2 regression): the synthesized events
/// carry the same CG phase fields hardware does, probed against
/// `NSEvent(cgEvent:)` on this machine — the
/// `scrollWheelEventScrollPhase` field 1 decodes to `.began` (1), 2 to
/// `.changed` (4), 4 to `.ended` (8) and 8 to `.cancelled` (16); the
/// `scrollWheelEventMomentumPhase` field 1 decodes to momentum begin (1),
/// 2 to momentum continued (4) and 3 to momentum end (8).
///
/// The phaseless events the suite used before hid the wrong phase table:
/// every live `.changed` event closed the gesture (so the lock was released
/// on every event and the zoom fluttered), the momentum tail and
/// `.cancelled` decoded to `.none` (so momentum zoomed and an interrupted
/// gesture left the lock latched).
@MainActor
final class BoardScrollHardwarePhaseTests: XCTestCase {
    private let size = CGSize(width: 900, height: 600)

    // Probe-verified CG → AppKit phase fields (see the class comment).
    private enum CGScrollPhase {
        static let began: Int64 = 1
        static let changed: Int64 = 2
        static let ended: Int64 = 4
        static let cancelled: Int64 = 8
    }
    private enum CGMomentumPhase {
        static let begin: Int64 = 1
        static let continued: Int64 = 2
        static let end: Int64 = 3
    }

    private func scrollEvent(
        deltaY: Int32,
        command: Bool,
        scrollPhase: Int64? = nil,
        momentumPhase: Int64? = nil
    ) -> NSEvent? {
        guard let cg = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else { return nil }
        if command { cg.flags = .maskCommand }
        if let scrollPhase { cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase) }
        if let momentumPhase { cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase) }
        return NSEvent(cgEvent: cg)
    }

    private func makeBoardAndView() throws -> (WhiteboardPages, WhiteboardView) {
        let state = EditorState()
        state.tool = .select
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return (board, view)
    }

    /// A live `.changed`-shaped stream keeps the gesture running: opposite
    /// jitter between zoom-in steps must not zoom, and consistent deltas
    /// keep zooming in.
    func testALiveChangedStreamKeepsTheDirectionLockLatched() throws {
        let (board, view) = try makeBoardAndView()
        defer { view.window?.orderOut(nil) }
        view.resetPageView()
        let base = board.currentPage.zoom

        guard let step1 = scrollEvent(deltaY: 2, command: true, scrollPhase: CGScrollPhase.began),
              let step2 = scrollEvent(deltaY: 2, command: true, scrollPhase: CGScrollPhase.changed),
              let jitter = scrollEvent(deltaY: -1, command: true, scrollPhase: CGScrollPhase.changed),
              let step3 = scrollEvent(deltaY: 2, command: true, scrollPhase: CGScrollPhase.changed)
        else { return XCTFail("the synthesized scroll event could not be built") }
        view.scrollWheel(with: step1)
        view.scrollWheel(with: step2)
        XCTAssertTrue(board.currentPage.zoom > base, "⌘ + scroll with a live phase zooms in")
        let zoomed = board.currentPage.zoom

        view.scrollWheel(with: jitter)
        XCTAssertEqual(
            board.currentPage.zoom, zoomed,
            "a small opposite delta inside the live gesture is jitter and must not zoom"
        )

        view.scrollWheel(with: step3)
        XCTAssertGreaterThan(board.currentPage.zoom, zoomed, "consistent deltas keep zooming in")
    }

    /// The closing `.ended` event (raw 8 through the CG field) ends the
    /// gesture, so a following event may zoom the other way.
    func testTheEndedEventClosesTheGestureSoTheNextMayZoomTheOtherWay() throws {
        let (board, view) = try makeBoardAndView()
        defer { view.window?.orderOut(nil) }
        view.resetPageView()
        let base = board.currentPage.zoom

        guard let zoomIn = scrollEvent(deltaY: 2, command: true, scrollPhase: CGScrollPhase.changed),
              let close = scrollEvent(deltaY: 0, command: true, scrollPhase: CGScrollPhase.ended),
              let zoomOut = scrollEvent(deltaY: -2, command: true, scrollPhase: CGScrollPhase.began)
        else { return XCTFail("the synthesized scroll event could not be built") }
        view.scrollWheel(with: zoomIn)
        let zoomed = board.currentPage.zoom
        XCTAssertTrue(zoomed > base)
        view.scrollWheel(with: close)
        XCTAssertEqual(board.currentPage.zoom, zoomed, "the closing event itself zooms nothing")
        view.scrollWheel(with: zoomOut)
        XCTAssertLessThan(
            board.currentPage.zoom, zoomed,
            "after .ended the lock is released and the next gesture zooms out"
        )
    }

    /// The momentum tail (raw values AppKit reports as momentum begin,
    /// continued and end) never zooms, however large its delta.
    func testTheMomentumTailNeverZooms() throws {
        let (board, view) = try makeBoardAndView()
        defer { view.window?.orderOut(nil) }
        view.resetPageView()
        let base = board.currentPage.zoom

        guard let zoomIn = scrollEvent(deltaY: 2, command: true, scrollPhase: CGScrollPhase.changed),
              let close = scrollEvent(deltaY: 0, command: true, scrollPhase: CGScrollPhase.ended)
        else { return XCTFail("the synthesized scroll event could not be built") }
        view.scrollWheel(with: zoomIn)
        let zoomed = board.currentPage.zoom
        XCTAssertTrue(zoomed > base)
        view.scrollWheel(with: close)
        XCTAssertEqual(board.currentPage.zoom, zoomed, "the closing event itself zooms nothing")

        for field in [CGMomentumPhase.begin, CGMomentumPhase.continued, CGMomentumPhase.end] {
            guard let momentum = scrollEvent(deltaY: 400, command: true, momentumPhase: field)
            else { return XCTFail("the synthesized momentum event could not be built") }
            view.scrollWheel(with: momentum)
            XCTAssertEqual(
                board.currentPage.zoom, zoomed,
                "the momentum tail (CG field \(field)) must not zoom"
            )
        }
    }

    /// A cancelled gesture releases the direction lock: the next gesture may
    /// zoom the other way instead of the lock staying latched.
    func testACancelledGestureReleasesTheLock() throws {
        let (board, view) = try makeBoardAndView()
        defer { view.window?.orderOut(nil) }
        view.resetPageView()
        let base = board.currentPage.zoom

        guard let zoomIn = scrollEvent(deltaY: 2, command: true, scrollPhase: CGScrollPhase.changed),
              let cancel = scrollEvent(deltaY: 0, command: true, scrollPhase: CGScrollPhase.cancelled),
              let zoomOut = scrollEvent(deltaY: -2, command: true, scrollPhase: CGScrollPhase.began)
        else { return XCTFail("the synthesized scroll event could not be built") }
        view.scrollWheel(with: zoomIn)
        XCTAssertTrue(board.currentPage.zoom > base)
        let zoomed = board.currentPage.zoom
        view.scrollWheel(with: cancel)
        XCTAssertEqual(board.currentPage.zoom, zoomed, "the cancelled event itself zooms nothing")
        view.scrollWheel(with: zoomOut)
        XCTAssertLessThan(
            board.currentPage.zoom, zoomed,
            "after .cancelled the lock is released and the next gesture zooms out"
        )
    }
}
