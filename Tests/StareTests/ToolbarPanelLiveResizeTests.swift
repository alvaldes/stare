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

    private func makeOnScreenPanel(_ state: EditorState) -> ToolbarPanel {
        let panel = ToolbarPanel(
            state: state,
            onUndo: {}, onRedo: {}, onClear: {}, onDone: {}
        )
        panel.positionNearPointerDisplay(placement: .cursor)
        panel.orderFront(nil)
        runLoopTurns()
        return panel
    }

    // MARK: - The window follows the content

    func testFlippingOrientationLiveTakesTheVerticalFittingSize() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the probe needs a real display")

        let state = EditorState()
        let panel = makeOnScreenPanel(state)
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
        runLoopTurns()

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
        let panel = makeOnScreenPanel(state)
        defer { panel.orderOut(nil) }

        let hosting = try XCTUnwrap(panel.contentView)
        let fullFit = hosting.fittingSize

        // Hide every tool but the pen: the bar draws fewer items, so the
        // window must take the smaller fitting size.
        // Only the pen on the bar; every other tool waits in the pool.
        state.toolbarTools = ToolbarToolLayout(items: [.tool(.pen)])
        runLoopTurns()

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
        let panel = makeOnScreenPanel(state)
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
