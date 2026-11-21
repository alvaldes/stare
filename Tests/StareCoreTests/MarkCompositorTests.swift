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

    // T5/S3: a blur mark shows the pixels underneath blurred, and only inside
    // its rectangle.
    func testBlurMarkBlursPixelsInsideItsRectangleOnly() {
        // Black left half, white right half, so the boundary at x = 50 is
        // somewhere no mark would paint.
        let base = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        base.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        base.fill(CGRect(x: 0, y: 0, width: 50, height: height))
        base.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        base.fill(CGRect(x: 50, y: 0, width: 50, height: height))
        let baseImage = base.makeImage()!

        let mark = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 35, y: 30), CGPoint(x: 65, y: 70)]
        )

        let result = MarkCompositor.composite(marks: [mark], over: baseImage)
        XCTAssertNotNil(result)

        // The centre of the blurred rectangle straddles the black/white
        // boundary: a real blur lands strictly between the two extremes.
        let centre = pixel(result!, x: 50, y: 50)
        XCTAssertGreaterThan(centre.r, 40, "the blur must mix in the white half")
        XCTAssertLessThan(centre.r, 215, "the blur must mix in the black half")

        // Outside the rectangle the capture is untouched.
        XCTAssertEqual(pixel(result!, x: 10, y: 50).r, pixel(baseImage, x: 10, y: 50).r, "left of the rectangle")
        XCTAssertEqual(pixel(result!, x: 90, y: 50).r, pixel(baseImage, x: 90, y: 50).r, "right of the rectangle")
        XCTAssertEqual(pixel(result!, x: 40, y: 10).r, pixel(baseImage, x: 40, y: 10).r, "above the rectangle")
        XCTAssertEqual(pixel(result!, x: 60, y: 90).r, pixel(baseImage, x: 60, y: 90).r, "below the rectangle")
    }

    // T12/S9: a whiteboard capture composites blur marks over the live frame
    // (the pixels the board's view blurs), not over the page colour base.
    func testBoardBlurBaseShowsRealPixelsInsteadOfThePageColour() {
        // Blur base: black left half, white right half, boundary at x = 50.
        let blurBase = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        blurBase.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        blurBase.fill(CGRect(x: 0, y: 0, width: 50, height: height))
        blurBase.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        blurBase.fill(CGRect(x: 50, y: 0, width: 50, height: height))
        let frame = blurBase.makeImage()!

        let mark = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 35, y: 30), CGPoint(x: 65, y: 70)]
        )

        let result = MarkCompositor.composite(marks: [mark], over: whiteBase(), blurBase: frame)
        XCTAssertNotNil(result)

        // The centre of the patch straddles the frame's black/white boundary:
        // a real blur mixes, the page colour (solid white) would read 255.
        let centre = pixel(result!, x: 50, y: 50)
        XCTAssertGreaterThan(centre.r, 40, "the blur must mix in the frame's black half")
        XCTAssertLessThan(centre.r, 215, "the blur must mix in the frame's white half")
    }

    // T12/S9: the live frame arrives downscaled (half the display pixels), so
    // the blur base must be sampled at its own scale, not the base's.
    func testDownscaledBlurBaseIsSampledAtItsOwnScale() {
        // Base 200x200 white; frame 100x100 with the boundary at x = 50.
        let base = CGContext(
            data: nil,
            width: 200,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        base.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        base.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        let baseImage = base.makeImage()!

        let blurBase = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        blurBase.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        blurBase.fill(CGRect(x: 0, y: 0, width: 50, height: 100))
        blurBase.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        blurBase.fill(CGRect(x: 50, y: 0, width: 50, height: 100))
        let frame = blurBase.makeImage()!

        let mark = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 35, y: 30), CGPoint(x: 65, y: 70)]
        )

        let result = MarkCompositor.composite(marks: [mark], over: baseImage, scale: 2, blurBase: frame)
        XCTAssertNotNil(result)

        // In pixels of the result the patch spans 70..130 and the frame's
        // boundary sits at 100: a real blur mixes both halves there.
        let centre = pixel(result!, x: 100, y: 100)
        XCTAssertGreaterThan(centre.r, 40, "the downscaled frame must be sampled at its own scale")
        XCTAssertLessThan(centre.r, 215, "the downscaled frame must be sampled at its own scale")
    }

    // T12 fix: the board capture composes page-space marks translated by the
    // page's pan, so a panned page copies what the board shows: a mark drawn
    // at a page point lands at pagePoint - offset in the composed image.
    func testOffsetPlacesPageMarksAtPageMinusOffset() {
        let mark = Stroke(
            tool: .pen,
            ink: .red,
            points: [CGPoint(x: 40, y: 40), CGPoint(x: 60, y: 60)]
        )

        let result = MarkCompositor.composite(
            marks: [mark],
            over: whiteBase(),
            scale: 2,
            offset: CGSize(width: 10, height: 20)
        )
        XCTAssertNotNil(result)

        // Page point (40,40) → view point (30,20) → pixel (60,40) at 2x.
        XCTAssertTrue(isReddish(pixel(result!, x: 60, y: 40)), "the mark lands where the board shows it")
        // The unpanned location is empty: the pan actually moved the ink.
        XCTAssertFalse(isReddish(pixel(result!, x: 80, y: 80)), "the mark must not stay at its page point")
    }

    // T12 fix: an offset of zero composes exactly like before the pan support
    // existed — the mark is at its own points.
    func testZeroOffsetLeavesMarksWhereTheyWereDrawn() {
        let mark = Stroke(
            tool: .pen,
            ink: .red,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10)]
        )

        let result = MarkCompositor.composite(
            marks: [mark],
            over: whiteBase(),
            scale: 2,
            offset: .zero
        )
        XCTAssertNotNil(result)

        XCTAssertTrue(isReddish(pixel(result!, x: 20, y: 20)), "the unpanned case is unchanged")
        XCTAssertTrue(isWhitesh(pixel(result!, x: 10, y: 10)), "nothing is left behind at 1x")
    }

    // T12 fix: a blur mark on a panned page must sample the live frame at the
    // panned (view-space) rectangle, not at the page-space one.
    func testOffsetBlurSamplesTheFrameAtThePannedLocation() {
        // Base 200x200 white (scale 2); frame 100x100, black left of x = 50.
        let base = CGContext(
            data: nil,
            width: 200,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        base.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        base.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        let baseImage = base.makeImage()!

        let frame = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        frame.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        frame.fill(CGRect(x: 0, y: 0, width: 50, height: 100))
        frame.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        frame.fill(CGRect(x: 50, y: 0, width: 50, height: 100))
        let frameImage = frame.makeImage()!

        let mark = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 35, y: 30), CGPoint(x: 65, y: 70)]
        )

        // Offset (35, 0): the view rect is (0,30)-(30,70), well inside the
        // frame's black half — more than two blur radii (2 × 15) from the
        // boundary at x = 50. Sampling at the page-space rect would straddle
        // the boundary and come back much lighter.
        let result = MarkCompositor.composite(
            marks: [mark],
            over: baseImage,
            scale: 2,
            blurBase: frameImage,
            offset: CGSize(width: 35, height: 0)
        )
        XCTAssertNotNil(result)

        // The patch centre lands at view point (15,50) → pixel (30,100).
        XCTAssertLessThan(pixel(result!, x: 30, y: 100).r, 80, "the blur must sample the frame where the board shows the patch")
    }

    // T11/S6: a rotated mark renders rotated about its anchor, and the old
    // orientation is gone.
    func testRotatedMarkRendersAtItsRotatedPlace() {
        // A horizontal line rotated a quarter turn now runs down the middle.
        let mark = Stroke(
            tool: .pen,
            ink: .red,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 20)]
        )
        let rotated = MarkTransform.rotated(mark, by: .pi / 2)

        let result = MarkCompositor.composite(marks: [rotated], over: whiteBase())
        XCTAssertNotNil(result)

        XCTAssertTrue(isReddish(pixel(result!, x: 50, y: 50)), "the rotated line runs down the middle")
        XCTAssertTrue(isWhitesh(pixel(result!, x: 20, y: 20)), "the old start point is empty")
        XCTAssertTrue(isWhitesh(pixel(result!, x: 80, y: 20)), "the old end point is empty")
    }

    // T11/S6: a rotated blur still shows the pixels underneath: the cropped
    // image rotates about its centre, never the crop rectangle.
    func testRotatedBlurShowsThePixelsUnderneathItsRotatedArea() {
        // Black left half, white right half, boundary at x = 50.
        let base = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        base.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        base.fill(CGRect(x: 0, y: 0, width: 50, height: height))
        base.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        base.fill(CGRect(x: 50, y: 0, width: 50, height: height))
        let baseImage = base.makeImage()!

        let mark = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 35, y: 30), CGPoint(x: 65, y: 70)]
        )
        let rotated = MarkTransform.rotated(mark, by: .pi / 2)

        let result = MarkCompositor.composite(marks: [rotated], over: baseImage)
        XCTAssertNotNil(result)

        // (32, 50) is inside the rotated patch but outside the unrotated one:
        // it must show the blurred mix, not the plain black base.
        let insideRotated = pixel(result!, x: 32, y: 50)
        XCTAssertGreaterThan(insideRotated.r, 40, "the rotated patch still blurs the pixels underneath")

        // Outside the rotated patch the capture is untouched.
        XCTAssertEqual(pixel(result!, x: 10, y: 50).r, pixel(baseImage, x: 10, y: 50).r,
                       "far from the mark the base is untouched")
    }

    // T11/S6: a scaled text mark must render proportionally larger: the
    // renderers size the font from the stroke's own textSize, not a hardcoded
    // one, so the ink and the handles agree at every scale.
    func testScaledTextRendersProportionallyLarger() {
        // "Hola mundo" measures 106×24 at the 20pt editing font, which is what
        // the app stores when the mark is created.
        let mark = Stroke(
            tool: .text,
            ink: .red,
            points: [CGPoint(x: 10, y: 30)],
            text: "Hola mundo",
            textSize: CGSize(width: 106, height: 24)
        )

        let base = inkExtent(of: mark)
        let scaled = MarkTransform.scaled(mark, from: CGPoint(x: 10, y: 30), by: 3)
        let grown = inkExtent(of: scaled)

        XCTAssertGreaterThan(base.w, 20, "the text renders at all")
        XCTAssertEqual(grown.w / base.w, 3, accuracy: 0.75, "a 3× text scale renders about 3× wider ink")
        XCTAssertEqual(grown.h / base.h, 3, accuracy: 0.75, "a 3× text scale renders about 3× taller ink")
    }

    /// Painted-pixel bounding box of the stroke's ink, in pixels.
    private func inkExtent(of stroke: Stroke) -> (w: CGFloat, h: CGFloat) {
        let width = 400
        let height = 200
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
        let result = MarkCompositor.composite(marks: [stroke], over: context.makeImage()!)!

        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let p = pixel(result, x: x, y: y)
                if !(p.r > 240 && p.g > 240 && p.b > 240) {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        XCTAssertGreaterThan(maxX, minX, "some ink must be on the canvas")
        return (CGFloat(maxX - minX + 1), CGFloat(maxY - minY + 1))
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
