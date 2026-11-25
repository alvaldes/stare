import AppKit
import SwiftUI
import XCTest
@testable import Stare
import StareCore

/// T6: the hidden tools get their own minimal window, opened beside the bar on
/// the side that faces the middle of the screen. The geometry is pinned in
/// StareCore (`ToolbarOverflowPlacementTests`); here is the window that uses it,
/// and the rule that picking a tool is what closes it.
@MainActor
final class ToolbarOverflowPanelTests: XCTestCase {

    private func makePanel(hidden: [Tool] = [.line, .spotlight], picked: ((Tool) -> Void)? = nil) -> ToolbarOverflowPanel {
        ToolbarOverflowPanel(
            state: EditorState(),
            hidden: hidden,
            vertical: true,
            onPick: { picked?($0) }
        )
    }

    /// The panel is a thing that appeared next to the bar, not a second bar: it
    /// cannot become key, has no title bar, and sits at the bar's own level.
    func testThePanelIsAMinimalNeighbourOfTheBar() {
        let panel = makePanel()
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, ToolbarOverflowPanel.panelLevel)
        XCTAssertEqual(panel.level, NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1))
    }

    /// The frame comes from the shared placement rule, so a bar on any edge opens
    /// its extras toward the screen and never off it.
    func testThePanelLandsOnTheSideFacingTheMiddleOfTheScreen() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let visible = screen.visibleFrame
        // A vertical bar 44 wide hugging each side edge, in the middle of the
        // screen vertically.
        let height: CGFloat = 300
        let leftBar = CGRect(x: visible.minX + 8, y: visible.midY, width: 44, height: height)
        let rightBar = CGRect(x: visible.maxX - 8 - 44, y: visible.midY, width: 44, height: height)

        let panel = makePanel()
        panel.place(beside: leftBar, border: .left, screen: screen)
        XCTAssertGreaterThan(panel.frame.minX, leftBar.maxX, "parked on the left, the extras open to the right")
        XCTAssertTrue(visible.contains(panel.frame))

        panel.place(beside: rightBar, border: .right, screen: screen)
        XCTAssertLessThan(panel.frame.maxX, rightBar.minX, "parked on the right, the extras open to the left")
        XCTAssertTrue(visible.contains(panel.frame))
    }

    /// Picking a tool reports it, which is what the controller turns into a
    /// selection plus a close.
    func testPickingAToolReportsThatTool() {
        var picked: [Tool] = []
        let panel = makePanel(picked: { picked.append($0) })
        panel.pick(.spotlight)
        panel.pick(.line)
        XCTAssertEqual(picked, [.spotlight, .line])
    }

    /// The panel closes on the first interaction that is not one of its own
    /// tools — a press on the canvas, on the bar, a key, the app going away — and
    /// survives a press inside itself. Dragging the bar by its gripper is the case
    /// the owner named: the press lands in the bar's window, so the panel goes.
    /// S12/L31 extends the rule with one exception, the more button's own frame:
    /// a press over it is left to that button's toggle. The old cases are kept
    /// exactly as they were so the extension cannot regress them.
    func testThePanelClosesOnAnyInteractionThatIsNotItsOwn() throws {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        let elsewhere = NSWindow(contentRect: NSRect(x: 100, y: 0, width: 40, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)

        XCTAssertFalse(OverlayController.closesOverflow(forEventAt: nil, in: panel, panel: panel, moreButtonFrame: nil), "its own tools must not close it")
        XCTAssertTrue(OverlayController.closesOverflow(forEventAt: nil, in: elsewhere, panel: panel, moreButtonFrame: nil), "the bar or the canvas closes it")
        XCTAssertTrue(OverlayController.closesOverflow(forEventAt: nil, in: nil, panel: panel, moreButtonFrame: nil), "a stray event closes it")
        XCTAssertFalse(OverlayController.closesOverflow(forEventAt: nil, in: elsewhere, panel: nil, moreButtonFrame: nil), "nothing to close")
    }

    /// The more button's frame as the bar reports it for the panel's placement,
    /// here as a fixture window standing in for the toolbar and its button.
    private func moreButtonFixture() -> (window: NSWindow, frame: CGRect) {
        let bar = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        return (bar, CGRect(x: 60, y: 60, width: 26, height: 26))
    }

    /// The owner's report (S12): one press opened the hidden tools, and the next
    /// one could never close them. The diagnosis: the close rule fired on the
    /// press over the more button itself (it reached the monitor before SwiftUI's
    /// button action), and the button's toggle then saw a closed panel and
    /// reopened it. The fix is in the pure rule: a press inside the more button's
    /// frame in the bar's window does not close — that button's own toggle owns
    /// the open state.
    func testAPressOnTheMoreButtonDoesNotCloseThePanel() {
        let panel = makePanel()
        let (bar, frame) = moreButtonFixture()
        XCTAssertFalse(
            OverlayController.closesOverflow(
                forEventAt: CGPoint(x: frame.midX, y: frame.midY),
                in: bar,
                panel: panel,
                moreButtonFrame: (bar, frame)
            ),
            "the more button's own toggle owns the open state")
    }

    /// Any other press in the bar's window still closes, even from the same
    /// window the button lives in.
    func testAPressElsewhereInTheBarStillClosesThePanel() {
        let panel = makePanel()
        let (bar, frame) = moreButtonFixture()
        XCTAssertTrue(
            OverlayController.closesOverflow(
                forEventAt: CGPoint(x: frame.minX - 5, y: frame.midY),
                in: bar,
                panel: panel,
                moreButtonFrame: (bar, frame)
            ),
            "a press elsewhere in the bar is not the button")
    }

    /// The panel's own window never closes it, whatever lands there.
    func testAPressInThePanelNeverClosesIt() {
        let panel = makePanel()
        let (bar, frame) = moreButtonFixture()
        XCTAssertFalse(
            OverlayController.closesOverflow(
                forEventAt: CGPoint(x: frame.midX, y: frame.midY),
                in: panel,
                panel: panel,
                moreButtonFrame: (bar, frame)
            ),
            "the panel's own tools never close it")
    }

    /// The frame exemption is bound to the button's window: a press in another
    /// window (the canvas) closes even at a point that happens to fall inside
    /// the frame's rect, and a nil window is a stray event that closes.
    func testAPressInAnyOtherWindowStillClosesThePanel() {
        let panel = makePanel()
        let (bar, frame) = moreButtonFixture()
        let canvas = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        XCTAssertTrue(
            OverlayController.closesOverflow(
                forEventAt: CGPoint(x: frame.midX, y: frame.midY),
                in: canvas,
                panel: panel,
                moreButtonFrame: (bar, frame)
            ),
            "only the bar's own window can be the button")
        XCTAssertTrue(
            OverlayController.closesOverflow(
                forEventAt: CGPoint(x: frame.midX, y: frame.midY),
                in: nil,
                panel: panel,
                moreButtonFrame: (bar, frame)
            ),
            "a nil window is a stray event")
    }

    /// The frame is not known before the bar's first layout pass has reported
    /// it, and a key event carries no pointer position. Both fall back to the
    /// old rule (the panel closes) rather than guessing at a frame or a point.
    func testAnUnknownFrameOrAnEventWithoutAPointStillClosesThePanel() {
        let panel = makePanel()
        let (bar, frame) = moreButtonFixture()
        XCTAssertTrue(
            OverlayController.closesOverflow(
                forEventAt: CGPoint(x: frame.midX, y: frame.midY),
                in: bar,
                panel: panel,
                moreButtonFrame: nil
            ),
            "with no known frame there is no exemption yet")
        XCTAssertTrue(
            OverlayController.closesOverflow(
                forEventAt: nil,
                in: bar,
                panel: panel,
                moreButtonFrame: (bar, frame)
            ),
            "a key event has no pointer position, so there is no press inside the frame")
    }

    /// Only the hidden tools are in the panel: nothing of the bar's own tail.
    func testThePanelShowsExactlyTheHiddenTools() {
        let hidden: [Tool] = [.line, .number, .blur, .spotlight, .laser]
        let view = ToolbarOverflowExtrasView(
            state: EditorState(), hidden: hidden, vertical: true, onPick: { _ in })
        XCTAssertEqual(view.hidden, hidden)
    }

    /// The real bar asks the controller for the panel; the Settings preview is
    /// the only surface that expands inside the pill (it passes `.inline`, and
    /// its render tests go through the same seam).
    func testTheRealBarDelegatesItsOverflowToThePanel() {
        let bar = ToolbarView(state: EditorState(), onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        XCTAssertEqual(bar.overflowPresentation, .panel)
        XCTAssertTrue(bar.showsOverflow, "the shipped bar still offers the button")
    }
}
