import CoreGraphics
import XCTest

@testable import StareCore

final class AreaSelectionGeometryTests: XCTestCase {
    // A 1920×1080 display, in overlay points, is the drag's bounds.
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testADragUpLeftIsNotEmpty() {
        // Dragging up and left from the first point must still produce a
        // rectangle with real size, never an empty one.
        let rect = AreaSelectionGeometry.rect(
            from: CGPoint(x: 500, y: 500),
            to: CGPoint(x: 100, y: 100),
            square: false,
            bounds: display
        )

        XCTAssertFalse(rect.isEmpty, "an up-left drag is a real drag, not a click")
        XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 400, height: 400))
    }

    func testSquareForcesEqualSides() {
        // dx = 300, dy = 160: the square takes the longer side, along the drag.
        let rect = AreaSelectionGeometry.rect(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 400, y: 260),
            square: true,
            bounds: display
        )

        XCTAssertEqual(rect.width, rect.height, "shift must make both sides equal")
        XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 300, height: 300))
    }

    func testSquareFollowsTheDragsQuadrant() {
        // Dragging up and left with shift: the square grows up-left, not
        // down-right, so it stays under the pointer.
        let rect = AreaSelectionGeometry.rect(
            from: CGPoint(x: 500, y: 500),
            to: CGPoint(x: 200, y: 300),
            square: true,
            bounds: display
        )

        XCTAssertEqual(rect, CGRect(x: 200, y: 200, width: 300, height: 300),
                       "the square must extend toward where the pointer went")
    }

    func testTheRectIsClampedToTheBounds() {
        // Dragging past the right and bottom edges of the display: the
        // rectangle must stop at the edge, never address pixels outside it.
        let rect = AreaSelectionGeometry.rect(
            from: CGPoint(x: 900, y: 700),
            to: CGPoint(x: 2000, y: 1500),
            square: false,
            bounds: display
        )

        XCTAssertEqual(rect, CGRect(x: 900, y: 700, width: 1020, height: 380),
                       "the drag must be cut at the display edge")
        XCTAssertEqual(rect, rect.intersection(display),
                       "the result must sit entirely inside the display")
    }

    func testADegenerateDragIsNotCaptureWorthy() {
        // A click without movement: zero size, so not a capture.
        let rect = AreaSelectionGeometry.rect(
            from: CGPoint(x: 300, y: 300),
            to: CGPoint(x: 300, y: 300),
            square: false,
            bounds: display
        )

        XCTAssertFalse(
            AreaSelectionGeometry.isCaptureWorthy(rect),
            "a drag that went nowhere is a stray click, not a capture"
        )
    }

    func testA4x4DragIsCaptureWorthy() {
        XCTAssertTrue(
            AreaSelectionGeometry.isCaptureWorthy(CGRect(x: 20, y: 20, width: 4, height: 4)),
            "exactly the minimum drag is a deliberate small capture"
        )
    }

    func testTheMinimumIsExclusiveBelowTheBoundary() {
        // Anything even slightly under the minimum on either side is a stray
        // click, never a capture.
        XCTAssertFalse(
            AreaSelectionGeometry.isCaptureWorthy(CGRect(x: 20, y: 20, width: 3.9, height: 4)),
            "under the minimum in width there is no capture"
        )
        XCTAssertFalse(
            AreaSelectionGeometry.isCaptureWorthy(CGRect(x: 20, y: 20, width: 4, height: 3.9)),
            "under the minimum in height there is no capture"
        )
    }
}
