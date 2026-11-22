import AppKit
import SwiftUI
import XCTest
@testable import Stare
import StareCore

/// T8/S10 + T9/S12, live: the toolbar window follows its content. The panel
/// takes the hosted view's fitting size whenever what the bar draws changes
/// while it is on screen — an orientation flip, a tool-set change — instead
/// of keeping the size it was built with, and the resized bar stays docked
/// inside the screen's visible frame. A position the user has dragged is
/// kept through a resize. These probes need a real display, so they skip
/// cleanly when there is no screen.
@MainActor
final class ToolbarPanelLiveResizeTests: XCTestCase {

    /// The keys the panel persists its anchor and screen under; snapshot and
    /// restore them so a probe never leaves a mark on the host's defaults.
    private let anchorKeys = ["toolbarAnchor", "toolbarScreen"]
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

    /// Lets the runloop turn so SwiftUI lays the changed content out and the
    /// panel's resize path has run.
    private func runLoopTurns(turns: Int = 10) {
        for _ in 0..<turns {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// Places the bar on the primary screen and shows it there. The placement
    /// the bar runs on its own — `positionNearPointerDisplay` targets the
    /// pointer's display — follows the human's cursor, which may sit on a
    /// secondary monitor they are watching while the tests run, so this probe
    /// never asks AppKit where the window belongs: it pins the primary screen
    /// (see `PrimaryScreenTestWindow`).
    private func makeOnScreenPanel(_ state: EditorState) throws -> ToolbarPanel {
        let panel = ToolbarPanel(
            state: state,
            onUndo: {}, onRedo: {}, onClear: {}, onDone: {}
        )
        let home = try XCTUnwrap(
            PrimaryScreenTestWindow.frame(for: panel.frame.size),
            "the primary screen cannot host the toolbar probe")
        panel.setFrameOrigin(home.origin)
        panel.orderFront(nil)
        runLoopTurns()
        return panel
    }

    /// Re-docks the bar onto the primary screen when one of the panel's own
    /// placement paths walked it off. The panel's reset path (fired live by
    /// an orientation or border change, T9/S12) re-targets the pointer's
    /// display, and the pointer is the human's, not the probe's — so every
    /// state change that can trigger a reset re-pins the window to the
    /// primary screen (see `PrimaryScreenTestWindow`) before assertions run.
    private func confineToPrimaryScreen(_ panel: ToolbarPanel) {
        guard let home = PrimaryScreenTestWindow.frame(for: panel.frame.size) else { return }
        let primaryVisible = NSScreen.screens.first?.visibleFrame ?? home
        guard !primaryVisible.contains(panel.frame) else { return }
        panel.setFrameOrigin(home.origin)
    }

    // MARK: - The window follows the content

    func testFlippingOrientationLiveTakesTheVerticalFittingSize() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the probe needs a real display")

        let state = EditorState()
        let panel = try makeOnScreenPanel(state)
        defer { panel.orderOut(nil) }

        // Baseline: a freshly shown bar shows exactly the hosted content's
        // fitting size.
        let hosting = try XCTUnwrap(panel.contentView)
        let horizontalFit = hosting.fittingSize
        XCTAssertEqual(panel.frame.width, horizontalFit.width, accuracy: 2)
        XCTAssertEqual(panel.frame.height, horizontalFit.height, accuracy: 2)

        // Flip the stacking direction while the bar is on screen: the window
        // takes the vertical shape.
        state.toolbarOrientation = .vertical
        // The flip fires the panel's live reset (T9/S12), which re-targets
        // the pointer's display: pin the bar back to the primary screen at
        // once, and again after the reset's async re-assert has run.
        confineToPrimaryScreen(panel)
        runLoopTurns()
        confineToPrimaryScreen(panel)

        let verticalFit = hosting.fittingSize
        XCTAssertEqual(panel.frame.width, verticalFit.width, accuracy: 2)
        XCTAssertEqual(panel.frame.height, verticalFit.height, accuracy: 2)
        // And the resized bar stays docked inside the screen's visible frame.
        let visible = try XCTUnwrap(panel.screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame)
        XCTAssertTrue(visible.contains(panel.frame), "\(panel.frame) must stay inside \(visible)")
    }

    func testChangingTheToolSetLiveShrinksTheWindow() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the probe needs a real display")

        let state = EditorState()
        let panel = try makeOnScreenPanel(state)
        defer { panel.orderOut(nil) }

        let hosting = try XCTUnwrap(panel.contentView)
        let fullFit = hosting.fittingSize

        // Hide every tool but the pen: the bar draws fewer items, so the
        // window must take the smaller fitting size.
        // Only the pen on the bar; every other tool waits in the pool.
        state.toolbarTools = ToolbarToolLayout(items: [.tool(.pen)])
        // A tool-set change only refits the size; the placement paths that
        // can walk the bar off the primary screen are the reset-driven ones
        // (orientation/border). Pin it anyway after the runloop settles.
        runLoopTurns()
        confineToPrimaryScreen(panel)

        let shrunkFit = hosting.fittingSize
        XCTAssertLessThan(shrunkFit.width + shrunkFit.height, fullFit.width + fullFit.height)
        XCTAssertEqual(panel.frame.width, shrunkFit.width, accuracy: 2)
        XCTAssertEqual(panel.frame.height, shrunkFit.height, accuracy: 2)
        let visible = try XCTUnwrap(panel.screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame)
        XCTAssertTrue(visible.contains(panel.frame), "\(panel.frame) must stay inside \(visible)")
    }

    // MARK: - A dragged bar keeps its spot through a resize

    func testADraggedBarKeepsItsAnchorThroughAResize() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the probe needs a real display")

        let state = EditorState()
        let panel = try makeOnScreenPanel(state)
        defer { panel.orderOut(nil) }

        // Simulate the user dragging the bar away from the default anchor:
        // the move persists the bar's relative centre, exactly what the
        // gripper drag path does.
        let screen = try XCTUnwrap(panel.screen ?? NSScreen.screens.first)
        let draggedCentre = CGPoint(
            x: screen.frame.minX + screen.frame.width * 0.25,
            y: screen.frame.minY + screen.frame.height * 0.25
        )
        panel.setFrameOrigin(
            CGPoint(
                x: draggedCentre.x - panel.frame.width / 2,
                y: draggedCentre.y - panel.frame.height / 2
            )
        )
        runLoopTurns()

        // Hide tools: the bar shrinks, but a resize must keep the dragged
        // anchor — the bar's centre stays where the user parked it.
        // Only the pen on the bar; every other tool waits in the pool.
        state.toolbarTools = ToolbarToolLayout(items: [.tool(.pen)])
        runLoopTurns()
        confineToPrimaryScreen(panel)

        // The resize itself must have happened, or the next assertions are
        // vacuous: the window takes the shrunk fitting size…
        let hosting = try XCTUnwrap(panel.contentView)
        let shrunkFit = hosting.fittingSize
        XCTAssertEqual(panel.frame.width, shrunkFit.width, accuracy: 2)
        XCTAssertEqual(panel.frame.height, shrunkFit.height, accuracy: 2)
        // …while the dragged anchor holds: the bar's centre stays where the
        // user parked it.
        XCTAssertLessThan(abs(panel.frame.midX - draggedCentre.x), 4)
        XCTAssertLessThan(abs(panel.frame.midY - draggedCentre.y), 4)
        let visible = try XCTUnwrap(panel.screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame)
        XCTAssertTrue(visible.contains(panel.frame), "\(panel.frame) must stay inside \(visible)")
    }
}
