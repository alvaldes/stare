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
    func testThePanelClosesOnAnyInteractionThatIsNotItsOwn() throws {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        let elsewhere = NSWindow(contentRect: NSRect(x: 100, y: 0, width: 40, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)

        XCTAssertFalse(OverlayController.closesOverflow(forEventIn: panel, panel: panel), "its own tools must not close it")
        XCTAssertTrue(OverlayController.closesOverflow(forEventIn: elsewhere, panel: panel), "the bar or the canvas closes it")
        XCTAssertTrue(OverlayController.closesOverflow(forEventIn: nil, panel: panel), "a stray event closes it")
        XCTAssertFalse(OverlayController.closesOverflow(forEventIn: elsewhere, panel: nil), "nothing to close")
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
