import CoreGraphics
import XCTest

@testable import StareCore

final class FrontWindowSelectionTests: XCTestCase {
    func testTheFrontmostNormalWindowOfAnotherAppWins() {
        let picked = FrontWindowSelection.frontmost(
            in: [
                window(id: 11, pid: 500),
                window(id: 12, pid: 500),
            ],
            excluding: 999
        )

        XCTAssertEqual(picked?.windowID, 11, "the list arrives front to back")
    }

    func testOurOwnWindowsAreNeverTheTarget() {
        let picked = FrontWindowSelection.frontmost(
            in: [
                window(id: 11, pid: 999),
                window(id: 12, pid: 500),
            ],
            excluding: 999
        )

        XCTAssertEqual(picked?.windowID, 12, "Stare's own panels can never be captured")
    }

    func testNonZeroLayersAreSkipped() {
        let picked = FrontWindowSelection.frontmost(
            in: [
                window(id: 11, pid: 500, layer: 25),
                window(id: 12, pid: 500, layer: 3),
                window(id: 13, pid: 500),
            ],
            excluding: 999
        )

        XCTAssertEqual(picked?.windowID, 13, "menu bar and floating helpers are not windows")
    }

    func testInvisibleAndTinyWindowsAreSkipped() {
        let picked = FrontWindowSelection.frontmost(
            in: [
                window(id: 11, pid: 500, alpha: 0),
                window(id: 12, pid: 500, bounds: CGRect(x: 10, y: 10, width: 49, height: 60)),
                window(id: 13, pid: 500, bounds: CGRect(x: 10, y: 10, width: 60, height: 49)),
                window(id: 14, pid: 500),
            ],
            excluding: 999
        )

        XCTAssertEqual(picked?.windowID, 14, "an alpha-zero or undersized window has nothing to capture")
    }

    func testAWindowThatIsNotOnScreenIsSkipped() {
        let picked = FrontWindowSelection.frontmost(
            in: [
                window(id: 11, pid: 500, onScreen: false),
                window(id: 12, pid: 500),
            ],
            excluding: 999
        )

        XCTAssertEqual(picked?.windowID, 12, "bounds are not proof that pixels exist")
    }

    func testNoEligibleWindowIsNil() {
        let picked = FrontWindowSelection.frontmost(
            in: [
                window(id: 11, pid: 999),
                window(id: 12, pid: 500, layer: 8),
            ],
            excluding: 999
        )

        XCTAssertNil(picked, "the caller must be able to tell that nothing qualified")
    }

    // MARK: - Helpers

    private func window(
        id: CGWindowID,
        pid: Int32,
        layer: Int = 0,
        alpha: Double = 1,
        bounds: CGRect = CGRect(x: 100, y: 200, width: 800, height: 600),
        onScreen: Bool = true
    ) -> WindowCandidate {
        WindowCandidate(
            windowID: id,
            ownerPID: pid,
            layer: layer,
            alpha: alpha,
            bounds: bounds,
            isOnScreen: onScreen
        )
    }
}
