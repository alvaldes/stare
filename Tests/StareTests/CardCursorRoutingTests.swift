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

    // The process state before the class ran, restored in teardown (the
    // shared `LeaveAsFound` hooks — round four, cross-test contamination):
    // the modes below activate the app and `set()` the crosshair, and the
    // runner spins none of that away between classes —
    // TextSelectionWindowTests shares this process and reads exactly that.
    private var foundState: LeaveAsFound.State!
    private var controller: OverlayController?

    override func setUp() {
        super.setUp()
        foundState = LeaveAsFound.capture()
    }

    override func tearDown() {
        // The overlay mode's own exit route, with no focus handoff behind it
        // — `restoringFocus: false`, the spelling the mode switch uses — so
        // it orders the standing panels out and hands the cursor to the
        // arrow itself. The board's standing residue (its canvas panels, the
        // toolbar, its monitors) left no lifetime seam here, so its class
        // leaves through its own user-visible route, `toggleBoard` — the same
        // close `openBoard`'s mode switch takes — whose focus restore
        // re-asserts whichever app was already frontmost.
        if let controller = self.controller {
            if controller.isBoardActive { controller.toggleBoard() }
            if controller.isActive { controller.deactivate(restoringFocus: false) }
            self.controller = nil
        }
        LeaveAsFound.restore(foundState)
        super.tearDown()
    }

    private func makeController() -> OverlayController {
        // xctest runs without an initialized NSApplication and the controller's
        // mode lifecycle talks to it, so create it here first.
        _ = NSApplication.shared
        let controller = OverlayController(captureService: CaptureService(), editorHandoff: { _, _ in })
        self.controller = controller
        return controller
    }

    func testWithNoModeOnScreenTheRuleIsOff() {
        let controller = self.makeController()
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.isBoardActive)
        XCTAssertFalse(
            controller.cursorSkipsTheCard(at: insideTheCard, cardFrames: [card]),
            "no mode is on screen, so nothing may claim the pointer"
        )
    }

    func testTheDrawingModeSkipsTheCard() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen in this environment")
        let controller = self.makeController()
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
        let controller = self.makeController()
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
        let controller = self.makeController()
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
        // A programmatic `NSWindow` comes with `isReleasedWhenClosed = true`,
        // so `close()` releases it in ObjC terms WHILE ARC still owns it: an
        // over-release that showed up later, at the end of the test, as
        // `EXC_BAD_ACCESS` inside XCTest's memory checker
        // (`objc_autoreleasePoolPop` → `objc_release`). It killed the whole
        // `StareTests` bundle mid-run, and with it every suite after this one —
        // the run still reported "0 failures". Every window the app builds sets
        // this flag for the same reason; a test's own window has to as well.
        stranger.isReleasedWhenClosed = false
        defer { stranger.close() }
        XCTAssertFalse(OverlayController.isCardWindow(stranger, cards: []))
    }
}
