import CoreGraphics
import XCTest

@testable import StareCore

/// Boundaries the first pass of the window capture left untested, plus one
/// probe that composes a real mark and proves it survives the crop at the
/// offset it was drawn. Written from an independent verification of `1ee6393`
/// and `ff41287`.
final class WindowCaptureBoundaryTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    // MARK: - Geometry boundaries

    func testAWindowEqualToTheDisplayIsTheWholeImage() {
        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: display,
            displayBounds: display,
            scale: 2,
            imageSize: CGSize(width: 3840, height: 2160)
        )

        XCTAssertEqual(crop, CGRect(x: 0, y: 0, width: 3840, height: 2160))
    }

    func testAWindowLargerThanTheDisplayIsTheWholeImage() {
        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: -200, y: -100, width: 3000, height: 2000),
            displayBounds: display,
            scale: 2,
            imageSize: CGSize(width: 3840, height: 2160)
        )

        XCTAssertEqual(crop, CGRect(x: 0, y: 0, width: 3840, height: 2160))
    }

    func testANonRetinaDisplayScalesByOne() {
        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: 100, y: 50, width: 1200, height: 800),
            displayBounds: display,
            scale: 1,
            imageSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(crop, CGRect(x: 100, y: 50, width: 1200, height: 800))
    }

    func testAWindowOffTheRightAndBottomEdgesClips() {
        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: 1500, y: 900, width: 900, height: 700),
            displayBounds: display,
            scale: 2,
            imageSize: CGSize(width: 3840, height: 2160)
        )

        XCTAssertEqual(crop, CGRect(x: 3000, y: 1800, width: 840, height: 360))
    }

    func testADisplayAboveTheMainOneWithNegativeOrigin() {
        // A display arranged above the primary has a negative y in the one
        // global space, and the subtraction has to keep working.
        let above = CGRect(x: 0, y: -1080, width: 1920, height: 1080)

        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: 200, y: -1000, width: 400, height: 300),
            displayBounds: above,
            scale: 2,
            imageSize: CGSize(width: 3840, height: 2160)
        )

        XCTAssertEqual(crop, CGRect(x: 400, y: 160, width: 800, height: 600))
    }

    func testAFractionalWindowOriginRoundsOutward() {
        // `.integral` grows the rect, so a fractional origin can carry up to one
        // pixel of neighbouring content per edge. Documented, not accidental.
        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: 100.5, y: 200.25, width: 10.25, height: 10.5),
            displayBounds: display,
            scale: 2,
            imageSize: CGSize(width: 3840, height: 2160)
        )

        XCTAssertEqual(crop, CGRect(x: 201, y: 400, width: 21, height: 22))
    }

    func testAZeroSizeWindowGivesZero() {
        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: 100, y: 100, width: 0, height: 0),
            displayBounds: display,
            scale: 2,
            imageSize: CGSize(width: 3840, height: 2160)
        )

        XCTAssertEqual(crop, .zero)
    }

    func testAZeroImageGivesZero() {
        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: 100, y: 100, width: 50, height: 50),
            displayBounds: display,
            scale: 2,
            imageSize: .zero
        )

        XCTAssertEqual(crop, .zero)
    }

    // MARK: - A mark survives the crop where it was drawn

    func testAMarkInsideTheWindowSurvivesTheCropAtTheDrawnOffset() throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 3840,
                height: 2160,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let base = try XCTUnwrap(context.makeImage())

        // A 20 pt red pen stroke starting at overlay point (400, 300).
        let marks = [
            Stroke(
                tool: .pen,
                ink: .red,
                points: [CGPoint(x: 400, y: 300), CGPoint(x: 420, y: 300)]
            )
        ]
        let composed = try XCTUnwrap(
            MarkCompositor.composite(marks: marks, over: base, scale: 2)
        )

        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: CGRect(x: 200, y: 100, width: 1200, height: 800),
            displayBounds: display,
            scale: 2,
            imageSize: CGSize(width: composed.width, height: composed.height)
        )
        XCTAssertEqual(crop, CGRect(x: 400, y: 200, width: 2400, height: 1600))

        let result = try XCTUnwrap(composed.cropping(to: crop))
        let box = try XCTUnwrap(brightBounds(of: result))

        // Overlay (400,300) inside a window at (200,100) is offset (200,200),
        // which at 2x is pixel (400,400) of the crop.
        XCTAssertTrue(
            box.contains(CGPoint(x: 400, y: 400)),
            "the mark must stay at its drawn offset inside the crop: \(box)"
        )
    }

    /// The bounding box of every pixel brighter than the black base, in the
    /// image's own top-left pixel space. Enough to prove where a mark landed
    /// without asserting on antialiasing.
    private func brightBounds(of image: CGImage) throws -> CGRect? {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let read = try XCTUnwrap(
            CGContext(
                data: &data,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        read.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        var minX = Int.max
        var minY = Int.max
        var maxX = -1
        var maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let index = (y * image.width + x) * 4
                if data[index] > 60 || data[index + 1] > 60 || data[index + 2] > 60 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: - Selection boundaries

    private func window(
        _ id: CGWindowID,
        pid: Int32 = 500,
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

    func testAnEmptyListIsNil() {
        XCTAssertNil(FrontWindowSelection.frontmost(in: [], excluding: 999))
    }

    func testExactlyTheMinimumSizeQualifies() {
        let picked = FrontWindowSelection.frontmost(
            in: [window(1, bounds: CGRect(x: 0, y: 0, width: 50, height: 50))],
            excluding: 999
        )

        XCTAssertEqual(picked?.windowID, 1)
    }

    func testFiftyByFortyNineDoesNotQualify() {
        XCTAssertNil(
            FrontWindowSelection.frontmost(
                in: [window(1, bounds: CGRect(x: 0, y: 0, width: 50, height: 49))],
                excluding: 999
            )
        )
    }

    func testAnyPositiveAlphaQualifies() {
        let picked = FrontWindowSelection.frontmost(
            in: [window(1, alpha: 0.01)],
            excluding: 999
        )

        XCTAssertEqual(picked?.windowID, 1)
    }

    func testOnlyOurOwnWindowsIsNil() {
        XCTAssertNil(
            FrontWindowSelection.frontmost(
                in: [window(1, pid: 999), window(2, pid: 999)],
                excluding: 999
            )
        )
    }

    func testANegativeLayerIsSkipped() {
        XCTAssertNil(FrontWindowSelection.frontmost(in: [window(1, layer: -1)], excluding: 999))
    }

    func testTheListOrderIsKeptNotSortedBySize() {
        let picked = FrontWindowSelection.frontmost(
            in: [
                window(1, bounds: CGRect(x: 0, y: 0, width: 60, height: 60)),
                window(2, bounds: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
            ],
            excluding: 999
        )

        XCTAssertEqual(picked?.windowID, 1, "the front-most window wins, not the biggest")
    }
}
