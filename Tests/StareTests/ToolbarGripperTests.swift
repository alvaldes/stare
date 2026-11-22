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
}
