import AppKit
import XCTest

@testable import Stare

/// The card cursor rule's mode gate (B9). The comparison itself is pinned in
/// `CardCursorTests`; this pins that the controller asks it in *each* live mode,
/// because the board sets `isBoardActive` and never `isActive` — the reason the
/// arrow stayed missing on the board long after the overlay had it.
@MainActor
final class CardCursorRoutingTests: XCTestCase {
    private let card = CGRect(x: 100, y: 200, width: 220, height: 150)
    private let insideTheCard = CGPoint(x: 210, y: 275)
    private let offTheCard = CGPoint(x: 900, y: 900)

    private func controller() -> OverlayController {
        // xctest runs without an initialized NSApplication and the controller's
        // mode lifecycle talks to it, so create it here first.
        _ = NSApplication.shared
        return OverlayController(captureService: CaptureService(), editorHandoff: { _, _ in })
    }

    func testWithNoModeOnScreenTheRuleIsOff() {
        let controller = self.controller()
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.isBoardActive)
        XCTAssertFalse(
            controller.cursorSkipsTheCard(at: insideTheCard, cardFrames: [card]),
            "no mode is on screen, so nothing may claim the pointer"
        )
    }

    func testTheDrawingModeSkipsTheCard() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen in this environment")
        let controller = self.controller()
        controller.activate()
        XCTAssertTrue(controller.isActive, "the drawing mode has to be the one under test")

        XCTAssertTrue(
            controller.cursorSkipsTheCard(at: insideTheCard, cardFrames: [card]),
            "the crosshair must give way to the arrow over a card"
        )
        XCTAssertFalse(
            controller.cursorSkipsTheCard(at: offTheCard, cardFrames: [card]),
            "and must hold everywhere else on the display"
        )
    }

    /// The one this file exists for: the board never sets `isActive`, so a guard
    /// on that flag alone left the arrow missing exactly here.
    func testTheBoardModeSkipsTheCard() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen in this environment")
        let controller = self.controller()
        controller.toggleBoard()
        XCTAssertTrue(controller.isBoardActive, "the board has to be the one under test")
        XCTAssertFalse(controller.isActive, "and the board is not the overlay mode")

        XCTAssertTrue(
            controller.cursorSkipsTheCard(at: insideTheCard, cardFrames: [card]),
            "the tool cursor must give way to the arrow over a card on the board too"
        )
        XCTAssertFalse(
            controller.cursorSkipsTheCard(at: offTheCard, cardFrames: [card]),
            "and must hold everywhere else on the page"
        )
    }

    func testNoCardsOnScreenMeansNoSkip() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen in this environment")
        let controller = self.controller()
        controller.activate()
        XCTAssertFalse(controller.cursorSkipsTheCard(at: insideTheCard, cardFrames: []))
    }

    /// The canvas re-asserts its cursor on the move as well as on the cursor
    /// update, so the arrow only holds if both are dropped over a card.
    func testTheMoveAndTheCursorUpdateAreBothDroppedOverACard() {
        XCTAssertTrue(OverlayController.swallowsPointerEvent(.cursorUpdate, overCard: true))
        XCTAssertTrue(OverlayController.swallowsPointerEvent(.mouseMoved, overCard: true))
        XCTAssertFalse(
            OverlayController.swallowsPointerEvent(.mouseEntered, overCard: true),
            "entering still has to reach the canvas: it is not a cursor re-assertion"
        )
    }

    func testNothingIsDroppedOffACard() {
        for type in [NSEvent.EventType.cursorUpdate, .mouseMoved, .mouseEntered] {
            XCTAssertFalse(OverlayController.swallowsPointerEvent(type, overCard: false))
        }
    }

    /// A move with no window is not a card's, so it has to take the swallow path
    /// like any canvas move: that is what keeps the arrow for synthesized events.
    func testAWindowlessMoveIsNotACardMove() {
        XCTAssertFalse(
            OverlayController.isCardWindow(nil, cards: []),
            "no window means no card, so the canvas-side path runs"
        )
        XCTAssertTrue(
            OverlayController.swallowsPointerEvent(.mouseMoved, overCard: true),
            "and that path swallows the move"
        )
    }

    func testAWindowThatIsNotACardIsNotACardMove() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen in this environment")
        let stranger = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 40, height: 40),
            styleMask: [.borderless], backing: .buffered, defer: true
        )
        defer { stranger.close() }
        XCTAssertFalse(OverlayController.isCardWindow(stranger, cards: []))
    }
}
