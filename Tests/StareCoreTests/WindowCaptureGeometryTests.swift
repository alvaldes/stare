import CoreGraphics
import XCTest

@testable import StareCore

final class WindowCaptureGeometryTests: XCTestCase {
    // A 1920×1080 display captured at 2× is a 3840×2160 image.
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let imageSize = CGSize(width: 3840, height: 2160)

    func testTheCropSubtractsTheDisplayOriginAndScales() {
        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: 100, y: 200, width: 800, height: 600),
            displayBounds: display,
            scale: 2,
            imageSize: imageSize
        )

        XCTAssertEqual(crop, CGRect(x: 200, y: 400, width: 1600, height: 1200))
    }

    func testADisplayToTheRightUsesItsOwnOrigin() {
        // Second display starts where the first one ends, in the one global
        // top-left space both window lists and display bounds share.
        let secondDisplay = CGRect(x: 1920, y: 0, width: 2560, height: 1440)

        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: 2020, y: 120, width: 1000, height: 700),
            displayBounds: secondDisplay,
            scale: 2,
            imageSize: CGSize(width: 5120, height: 2880)
        )

        XCTAssertEqual(crop, CGRect(x: 200, y: 240, width: 2000, height: 1400))
    }

    func testTheCropIsClampedToTheImage() {
        // A window hanging off the left edge: half of it is not in the image.
        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: -40, y: 300, width: 400, height: 200),
            displayBounds: display,
            scale: 2,
            imageSize: imageSize
        )

        XCTAssertEqual(
            crop,
            CGRect(x: 0, y: 600, width: 720, height: 400),
            "cropping outside the image would crash rather than clip"
        )
    }

    func testAWindowOutsideTheDisplayGivesZero() {
        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: -500, y: -500, width: 100, height: 100),
            displayBounds: display,
            scale: 2,
            imageSize: imageSize
        )

        XCTAssertEqual(crop, .zero, "no overlap means nothing to composite onto")
    }

    func testADegenerateScaleGivesZero() {
        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: 100, y: 200, width: 800, height: 600),
            displayBounds: display,
            scale: 0,
            imageSize: imageSize
        )

        XCTAssertEqual(crop, .zero, "a scale of zero cannot produce pixels")
    }
}
