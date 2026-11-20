import CoreGraphics
import XCTest

import StareCore

final class MarkCompositorTests: XCTestCase {
    private let width = 100
    private let height = 100

    // MARK: - Helpers

    private func whiteBase() -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Reads a pixel with the origin at the top-left, which is the space the
    /// overlay draws in.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &data,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2])
    }

    private func isReddish(_ value: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
        value.r > 150 && value.g < 120 && value.b < 120
    }

    private func isWhitesh(_ value: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
        value.r > 240 && value.g > 240 && value.b > 240
    }

    // S30: a capture is the real screen with the marks redrawn on top.
    func testRectangleBorderIsPaintedAndItsInteriorIsNot() {
        let mark = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 30, y: 30), CGPoint(x: 70, y: 70)]
        )

        let result = MarkCompositor.composite(marks: [mark], over: whiteBase())
        XCTAssertNotNil(result)

        XCTAssertTrue(isReddish(pixel(result!, x: 30, y: 50)), "left edge is painted")
        XCTAssertTrue(isReddish(pixel(result!, x: 50, y: 30)), "top edge is painted")
        XCTAssertTrue(isWhitesh(pixel(result!, x: 50, y: 50)), "the inside stays clear")
    }

    func testEmptyMarksLeaveTheImageUntouched() {
        let base = whiteBase()
        let result = MarkCompositor.composite(marks: [], over: base)

        XCTAssertNotNil(result)
        XCTAssertTrue(isWhitesh(pixel(result!, x: 10, y: 10)))
        XCTAssertTrue(isWhitesh(pixel(result!, x: 90, y: 90)))
    }

    // S30: the laser is ephemeral and must never reach a capture.
    func testLaserMarksAreExcluded() {
        let laser = Stroke(
            tool: .laser,
            ink: .red,
            points: [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)],
            createdAt: Date()
        )

        let result = MarkCompositor.composite(marks: [laser], over: whiteBase())
        XCTAssertNotNil(result)

        for x in stride(from: 0, to: width, by: 10) {
            XCTAssertTrue(
                isWhitesh(pixel(result!, x: x, y: 50)),
                "the laser must not appear in a capture, found paint at x=\(x)"
            )
        }
    }

    func testScaleMapsPointsToPixels() {
        let stroke = Stroke(
            tool: .pen,
            ink: .red,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10)]
        )

        let result = MarkCompositor.composite(marks: [stroke], over: whiteBase(), scale: 2)
        XCTAssertNotNil(result)

        XCTAssertTrue(
            isReddish(pixel(result!, x: 20, y: 20)),
            "a point at (10,10) must land at pixel (20,20) at 2x"
        )
        XCTAssertTrue(isWhitesh(pixel(result!, x: 10, y: 10)), "nothing is left behind at 1x")
    }

    func testTextIsDrawnAtItsOrigin() {
        let mark = Stroke(
            tool: .text,
            ink: .red,
            points: [CGPoint(x: 10, y: 20)],
            text: "Export failed",
            textSize: CGSize(width: 120, height: 24)
        )

        let result = MarkCompositor.composite(marks: [mark], over: whiteBase())
        XCTAssertNotNil(result)

        var painted = 0
        for x in 10..<110 where !isWhitesh(pixel(result!, x: x, y: 30)) {
            painted += 1
        }
        XCTAssertGreaterThan(painted, 0, "glyphs have to be visible where the text mark sits")
    }

    func testZeroSizedImageIsRejected() {
        let empty = CGContext(
            data: nil,
            width: 0,
            height: 0,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()

        if let empty {
            XCTAssertNil(MarkCompositor.composite(marks: [], over: empty))
        }
    }
}
