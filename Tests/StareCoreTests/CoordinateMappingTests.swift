import CoreGraphics
import XCTest

import StareCore

final class CoordinateMappingTests: XCTestCase {
    private let tolerance: CGFloat = 0.001

    func testFlipMovesTheOriginToTheTop() {
        let bottomLeft = CGPoint(x: 30, y: 20)
        let flipped = CoordinateMapping.flipped(bottomLeft, height: 100)

        XCTAssertEqual(flipped.x, 30, accuracy: tolerance)
        XCTAssertEqual(flipped.y, 80, accuracy: tolerance)
    }

    func testPixelMappingAppliesTheBackingScale() {
        let point = CoordinateMapping.toPixels(CGPoint(x: 12, y: 34), scale: 2)
        XCTAssertEqual(point, CGPoint(x: 24, y: 68))

        let rect = CoordinateMapping.toPixels(
            CGRect(x: 10, y: 20, width: 30, height: 40),
            scale: 2
        )
        XCTAssertEqual(rect, CGRect(x: 20, y: 40, width: 60, height: 80))
    }

    func testPointsAndPixelsRoundTrip() {
        let original = CGRect(x: 10, y: 20, width: 30, height: 40)
        let pixels = CoordinateMapping.toPixels(original, scale: 2)
        let back = CoordinateMapping.toPoints(pixels, scale: 2)

        XCTAssertEqual(back, original)
    }

    func testZeroScaleDoesNotDivideByZero() {
        let rect = CoordinateMapping.toPoints(CGRect(x: 1, y: 2, width: 3, height: 4), scale: 0)
        XCTAssertEqual(rect, .zero)
    }

    func testScreenPointMapsIntoDisplayLocalOverlaySpace() {
        // A second display sitting to the right of the primary one.
        let screenFrame = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let pointer = CGPoint(x: 1512 + 100, y: 1080 - 50)

        let overlay = CoordinateMapping.overlayPoint(
            fromScreenPoint: pointer,
            screenFrame: screenFrame
        )

        XCTAssertEqual(overlay.x, 100, accuracy: tolerance)
        XCTAssertEqual(overlay.y, 50, accuracy: tolerance)
    }

    func testAreaCaptureClampsToTheDisplay() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        let draggedPastTheEdge = CGRect(x: 80, y: 80, width: 60, height: 60)

        let clamped = CoordinateMapping.clamped(draggedPastTheEdge, to: display)
        XCTAssertEqual(clamped, CGRect(x: 80, y: 80, width: 20, height: 20))
    }
}
