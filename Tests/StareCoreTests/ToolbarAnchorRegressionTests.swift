import XCTest

@testable import StareCore

/// A zero-width screen (never a real screen, still wrong) must not move the
/// side-docked column to dead centre: `sideFraction` falls back to the
/// cross-edge inset fraction so the column keeps docking on its own side.
final class ToolbarAnchorRegressionTests: XCTestCase {
    func testAZeroWidthScreenDocksTheColumnOnItsSideAtTheCrossEdgeInset() {
        XCTAssertEqual(
            ToolbarGripperSpec.sideFraction(screenFrame: .zero),
            ToolbarGripperSpec.crossEdgeInset,
            "the fallback is the 8% cross-edge inset, not the centre"
        )
        XCTAssertEqual(
            ToolbarGripperSpec.defaultAnchor(border: .right, screenFrame: .zero).x,
            1 - ToolbarGripperSpec.crossEdgeInset,
            "the column still docks on its side"
        )
    }
}
