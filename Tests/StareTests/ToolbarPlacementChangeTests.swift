import AppKit
import SwiftUI
import XCTest
@testable import Stare
import StareCore

/// A placement change must leave the bar docked where the new placement says —
/// never parked in the middle of the screen — and the bar moves by its gripper
/// alone.
@MainActor
final class ToolbarPlacementChangeTests: XCTestCase {
    private let anchorKeys = ["toolbarAnchor", "toolbarScreen"]
    private var savedDefaults: [(String, Any?)] = []

    override func setUp() {
        super.setUp()
        savedDefaults = anchorKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        for key in anchorKeys { UserDefaults.standard.removeObject(forKey: key) }
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

    private func runLoopTurns(_ turns: Int = 12) {
        for _ in 0..<turns { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    private func makeOnScreenPanel(_ state: EditorState) throws -> ToolbarPanel {
        let panel = ToolbarPanel(state: state, onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        let home = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: panel.frame.size))
        panel.setFrameOrigin(home.origin)
        panel.orderFront(nil)
        runLoopTurns()
        return panel
    }

    /// The owner's report: switching a horizontal bar to vertical left it
    /// "broken". A column on a horizontal edge anchors at the middle of the
    /// screen, and the reset that follows used to consult the anchor its own
    /// move had just persisted — so the column stayed there. A flipped bar must
    /// stand against a SIDE edge.
    func testFlippingToVerticalLeavesTheColumnAgainstASideEdge() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the probe needs a real display")
        let state = EditorState()
        state.toolbarOrientation = .horizontal
        state.toolbarBorder = .top
        let panel = try makeOnScreenPanel(state)
        defer { panel.orderOut(nil) }

        // Flip only the orientation: the border stays a horizontal edge, which is
        // exactly the mismatched pair the placement has to survive.
        state.toolbarOrientation = .vertical
        runLoopTurns()

        let visible = try XCTUnwrap(NSScreen.screens.first?.visibleFrame)
        let frame = panel.frame
        XCTAssertGreaterThan(frame.height, frame.width, "a vertical bar is a column")
        XCTAssertTrue(visible.contains(frame), "\(frame) must stay inside \(visible)")
        // Against a side, not in the middle: either edge is fine, the centre is
        // the failure.
        let roomFromLeft = frame.minX - visible.minX
        let roomFromRight = visible.maxX - frame.maxX
        // A side dock keeps the column within the 8 % inset (86 pt on a
        // 1080-tall screen) plus its own half width; the middle of the screen is
        // ~940 pt away from both sides, which is the failure this pins.
        XCTAssertLessThan(
            min(roomFromLeft, roomFromRight), visible.width * 0.1,
            "a flipped column docks on a side edge; \(frame) in \(visible) is \(roomFromLeft) / \(roomFromRight) from the sides"
        )
    }

    /// The owner's report, second half: switching to vertical kept the
    /// horizontal height. A bar whose orientation changes while it is off screen
    /// used to come back with the old frame — the resize request was dropped for
    /// arriving while hidden, and the first placement trusted `frame.size`.
    func testAHiddenBarTakesTheNewShapeWhenItComesBack() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the probe needs a real display")
        let state = EditorState()
        state.toolbarOrientation = .horizontal
        state.toolbarBorder = .top
        let panel = ToolbarPanel(state: state, onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        defer { panel.orderOut(nil) }

        panel.orderFront(nil)
        runLoopTurns(6)
        let horizontalSize = panel.frame.size
        XCTAssertGreaterThan(horizontalSize.width, horizontalSize.height)

        // Change the placement while the bar is not on screen, then bring it
        // back the way the controller does.
        panel.orderOut(nil)
        state.toolbarOrientation = .vertical
        runLoopTurns(6)
        panel.positionNearPointerDisplay(placement: state.palettePlacementValue)
        panel.orderFront(nil)
        runLoopTurns(6)

        XCTAssertGreaterThan(
            panel.frame.height, panel.frame.width,
            "the bar came back as \(panel.frame.size) after switching to vertical; it must be a column")
        XCTAssertNotEqual(panel.frame.size, horizontalSize)
        let visible = try XCTUnwrap(NSScreen.screens.first?.visibleFrame)
        XCTAssertTrue(visible.contains(panel.frame), "\(panel.frame) must stay inside \(visible)")
    }

    /// The bar moves by its gripper alone: a press on the pill's own body must
    /// leave the window where it is. (A synthetic press cannot run AppKit's real
    /// drag session, so the owner still checks the feel; what this pins is that
    /// the content view no longer starts one.)
    func testPressingTheBarItselfNeverMovesIt() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the probe needs a real display")
        let state = EditorState()
        let panel = try makeOnScreenPanel(state)
        defer { panel.orderOut(nil) }

        let before = panel.frame
        let hosting = try XCTUnwrap(panel.contentView as? ToolbarHostingView)
        let point = NSPoint(x: hosting.bounds.midX, y: hosting.bounds.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type,
                location: panel.convertPoint(toScreen: point),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ) {
                panel.sendEvent(event)
            }
        }
        runLoopTurns(4)
        XCTAssertEqual(panel.frame, before, "the bar's body is not a drag handle")
    }
}
