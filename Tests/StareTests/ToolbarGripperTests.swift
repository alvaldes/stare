import XCTest
@testable import Stare

/// S4: the bar ends with a visible `⠇⠇` grab handle placed directly after
/// the close ("Done") button, so the user has an obvious spot to drag the
/// toolbar from. The order is a single source of truth the view maps over,
/// so pinning the array pins what the bar draws.
@MainActor
final class ToolbarGripperTests: XCTestCase {

    func testGripperSitsDirectlyAfterTheCloseButton() {
        XCTAssertEqual(
            ToolbarView.trailingItems.suffix(2),
            [.close, .gripper],
            "the gripper must be the item right after the close button, and the last in the bar"
        )
    }

    // MARK: Gripper cursors (T2/S3)

    func testGripperHoversWithTheOpenHandAndDragsWithTheClosedHand() {
        // T2/S3: over the gripper the open hand shows; while the drag runs it
        // is the closed hand — the same pair the board's pan shows.
        let gripper = ToolbarGripperView()
        XCTAssertFalse(gripper.isDragging)
        XCTAssertEqual(gripper.hoverCursor, .openHand)

        gripper.beginDrag()
        XCTAssertTrue(gripper.isDragging)
        XCTAssertEqual(gripper.hoverCursor, .closedHand)

        gripper.endDrag()
        XCTAssertFalse(gripper.isDragging)
        XCTAssertEqual(gripper.hoverCursor, .openHand, "releasing the drag returns the open hand")
    }

    func testGripperAbandonsTheDragWhenItLeavesTheWindow() {
        // T2/S3: the removal path must not leave a drag (or a hand cursor)
        // behind — the view forgets the drag state, and whatever sits under
        // the bar owns the cursor next.
        let gripper = ToolbarGripperView()
        gripper.beginDrag()
        XCTAssertTrue(gripper.isDragging)

        gripper.abandonDrag()
        XCTAssertFalse(gripper.isDragging)
        XCTAssertEqual(gripper.hoverCursor, .openHand)
    }
}
