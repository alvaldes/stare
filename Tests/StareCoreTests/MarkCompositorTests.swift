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

    /// A 200x200 solid white base: a board page's colour at 2x.
    private func pageBase() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 200,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        return context.makeImage()!
    }

    // S1: a blur mark on the board diffs the board's own content — the page
    // colour and the marks painted before it. The blur rectangle overlaps the
    // red rectangle's bottom border: inside the patch the pixels are neither
    // the pure page colour nor the pure rectangle ink (the content was
    // diffused), and outside the patch nothing changes.
    func testBoardBlurDiffusesTheContentBeneathIt() {
        let rect = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 50)]
        )
        let blur = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 30, y: 25), CGPoint(x: 70, y: 60)]
        )

        let result = MarkCompositor.composite(
            marks: [rect, blur],
            over: pageBase(),
            scale: 2,
            diffusesContent: true
        )
        XCTAssertNotNil(result)

        // Pixel (100,100) sits on the rectangle's bottom border inside the
        // patch: neither the pure page colour (255) nor visibly tinted away
        // from it. The blur of the border's thin line under the patch's 15pt
        // radius never darkens this pixel past g≈244 — measured, deterministic
        // — so the assertion holds the real output inside (200, 250): a result
        // at or above 250 differs from the undiffused page by 2% or less, which
        // is not visible diffusion, and the old behaviour — blur cropping the
        // solid page colour — reads exactly 255 and fails.
        let onBorder = pixel(result!, x: 100, y: 100)
        XCTAssertGreaterThan(onBorder.g, 200, "the patch keeps the page colour, not the pure ink")
        XCTAssertLessThan(onBorder.g, 250, "the patch must be visibly diffused away from the page colour")

        // Pixel (130,110) is inside the patch over plain page, close enough to
        // the border that the diffusion tints it: not the pure page colour.
        let overPage = pixel(result!, x: 130, y: 110)
        XCTAssertLessThan(overPage.g, 250, "the diffusion reaches the whole patch")
        XCTAssertGreaterThan(overPage.g, 59, "the patch is never the pure rectangle ink")

        // Outside the patch the page is untouched.
        XCTAssertTrue(isReddish(pixel(result!, x: 40, y: 70)), "the border left of the patch is untouched")
        XCTAssertTrue(isWhitesh(pixel(result!, x: 20, y: 160)), "the page beside the patch is untouched")
    }

    // S1 coverage (verifier advisory): a blur mark may extend past the base
    // image — a mark drawn across the page's edge, or a capture smaller than
    // the patch. The part of the patch over the base is the inside part and it
    // must blur the content underneath it at its true position: exactly like
    // the same patch stopped at the base's edge, never the crop stretched
    // across the whole rect. The part off the base must not reshape what the
    // base shows inside, and nothing crashes.
    func testBlurMarkCrossingTheBaseEdgeBlursOnlyTheInsidePart() {
        // Black left half, white right half, boundary at x = 50; the mark runs
        // 250pt past the right edge of the base.
        let baseImage = splitBase()
        let mark = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 35, y: 30), CGPoint(x: 350, y: 70)]
        )
        // The same patch stopped at the edge: the reference the inside part
        // must reproduce.
        let clipped = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 35, y: 30), CGPoint(x: 100, y: 70)]
        )

        for diffuses in [false, true] {
            let crossing = MarkCompositor.composite(
                marks: [mark], over: baseImage, diffusesContent: diffuses
            )
            XCTAssertNotNil(crossing, "a patch past the base edge must compose, not crash")
            XCTAssertEqual(crossing!.width, 100, "the composed capture keeps the base's size")
            let stopped = MarkCompositor.composite(
                marks: [clipped], over: baseImage, diffusesContent: diffuses
            )!
            // Inside the base the crossing patch is exactly the patch that
            // stops at the edge: same crop, drawn at the same place, not
            // stretched over the mark's own (much wider) rectangle.
            for x in [36, 42, 48, 54, 60, 70, 80, 90, 99] {
                for y in [32, 50, 68] {
                    XCTAssertEqual(
                        pixel(crossing!, x: x, y: y).r, pixel(stopped, x: x, y: y).r,
                        "the inside part at (\(x),\(y)) must blur like the patch stopped at the edge"
                    )
                }
            }
            // The blurred boundary inside the patch sits where the base puts
            // it: x = 45 is 5pt into the black half and reads visibly mixed,
            // x = 60 is 10pt into the white half and reads near white. A crop
            // stretched across the 315pt-wide rect maps these samples back to
            // black-side pixels (≈124 and ≈140) and fails both.
            XCTAssertGreaterThan(pixel(crossing!, x: 45, y: 50).r, 150,
                                 "the boundary blurs where the base is, got \(pixel(crossing!, x: 45, y: 50))")
            XCTAssertGreaterThan(pixel(crossing!, x: 60, y: 50).r, 200,
                                 "the white half stays white inside the patch, got \(pixel(crossing!, x: 60, y: 50))")
            // Outside the patch the base is untouched.
            XCTAssertEqual(pixel(crossing!, x: 10, y: 50).r, pixel(baseImage, x: 10, y: 50).r, "left of the patch")
            XCTAssertEqual(pixel(crossing!, x: 40, y: 10).r, pixel(baseImage, x: 40, y: 10).r, "above the patch")
            XCTAssertEqual(pixel(crossing!, x: 40, y: 90).r, pixel(baseImage, x: 40, y: 90).r, "below the patch")
        }

        // A patch entirely off the base composes the plain base instead of
        // crashing.
        let outside = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 110, y: 40), CGPoint(x: 140, y: 60)]
        )
        let offBase = MarkCompositor.composite(marks: [outside], over: baseImage, diffusesContent: true)
        XCTAssertNotNil(offBase, "a patch entirely off the base must compose, not crash")
        XCTAssertEqual(pixel(offBase!, x: 55, y: 50).r, pixel(baseImage, x: 55, y: 50).r, "nothing lands where the base is")
    }

    /// Black left half, white right half, on a 100x100 sRGB image.
    private func splitBase() -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 50, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 50, y: 0, width: 50, height: height))
        return context.makeImage()!
    }

    // S1 coverage (verifier advisory): a degenerate blur mark — two equal
    // points, one point, or no points — is a no-op: the composition succeeds
    // and the base is left exactly as it was.
    func testDegenerateBlurMarkIsANoOp() {
        let base = whiteBase()
        let degenerate: [(String, Stroke)] = [
            ("zero-size", Stroke(tool: .blur, ink: .red, points: [CGPoint(x: 40, y: 40), CGPoint(x: 40, y: 40)])),
            ("single-point", Stroke(tool: .blur, ink: .red, points: [CGPoint(x: 60, y: 60)])),
            ("no-points", Stroke(tool: .blur, ink: .red, points: [])),
        ]
        for (name, mark) in degenerate {
            let overlay = MarkCompositor.composite(marks: [mark], over: base)
            XCTAssertNotNil(overlay, "\(name): a degenerate blur mark must compose as the plain base")
            XCTAssertTrue(isWhitesh(pixel(overlay!, x: 39, y: 39)), "\(name): no paint where the degenerate mark sat")
            XCTAssertTrue(isWhitesh(pixel(overlay!, x: 61, y: 61)), "\(name): no paint where the degenerate mark sat")

            let board = MarkCompositor.composite(marks: [mark], over: base, diffusesContent: true)
            XCTAssertNotNil(board, "\(name): a degenerate blur mark must compose as the plain base")
            XCTAssertTrue(isWhitesh(pixel(board!, x: 50, y: 50)), "\(name): no paint where the degenerate mark sat")
        }
    }

    // S1, draw order: a blur mark applies to what is already rendered beneath
    // it, and a mark painted after it stays sharp where it overlaps.
    func testBoardBlurKeepsMarksPaintedAfterItSharp() {
        let blur = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 30, y: 25), CGPoint(x: 70, y: 60)]
        )
        let rect = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 50)]
        )

        let result = MarkCompositor.composite(
            marks: [blur, rect],
            over: pageBase(),
            scale: 2,
            diffusesContent: true
        )
        XCTAssertNotNil(result)

        // The same border pixel the diffusion test samples: here the rectangle
        // is painted after the blur, so it reads as pure ink over the patch.
        XCTAssertTrue(
            isReddish(pixel(result!, x: 100, y: 100)),
            "a mark painted after the blur stays sharp over the patch"
        )
        XCTAssertTrue(isWhitesh(pixel(result!, x: 20, y: 160)), "the page beside the patch is untouched")
    }

    // S1 fix, pan: a blur mark on a panned page diffuses the content where the
    // board shows it — pagePoint - offset — not at the mark's stored points.
    func testOffsetBoardBlurDiffusesThePannedContent() {
        let rect = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 50, y: 40), CGPoint(x: 90, y: 60)]
        )
        let blur = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 45, y: 35), CGPoint(x: 75, y: 65)]
        )

        // Offset (35, 0): the rectangle shows at view (15,40)-(55,60) and the
        // patch at view (10,35)-(40,65) — overlapping the rectangle's bottom
        // border where the board shows both.
        let result = MarkCompositor.composite(
            marks: [rect, blur],
            over: pageBase(),
            scale: 2,
            diffusesContent: true,
            offset: CGSize(width: 35, height: 0)
        )
        XCTAssertNotNil(result)

        // View (15,50) → pixel (30,100): on the rectangle's left border inside
        // the patch — neither the pure page colour nor the pure ink.
        let onBorder = pixel(result!, x: 30, y: 100)
        XCTAssertGreaterThan(onBorder.g, 200, "the patch keeps the page colour, not the pure ink")
        XCTAssertLessThan(onBorder.g, 250, "the panned patch must be visibly diffused, not near-white")

        // View (55,50) → pixel (110,100): the right border beyond the patch
        // stays sharp.
        XCTAssertTrue(isReddish(pixel(result!, x: 110, y: 100)), "the border beyond the patch is untouched")
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

    // MARK: - T5/S5: capture at a non-default zoom

    /// The board capture copies what the board shows: the same pan, and the
    /// same zoom. A mark stored at page (40,30)–(60,50) on a page panned to
    /// offset (10,5) and zoomed 2× shows at view (60,50)–(100,90) — the
    /// unzoomed placement stays empty.
    func testCaptureAtZoomPlacesMarksWhereTheBoardShowsThem() {
        let mark = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 40, y: 30), CGPoint(x: 60, y: 50)]
        )
        let result = MarkCompositor.composite(
            marks: [mark],
            over: whiteBase(),
            scale: 1,
            offset: CGSize(width: 10, height: 5),
            zoom: 2
        )
        let composed = try! XCTUnwrap(result)
        // The composed canvas keeps the base's size: the capture covers the
        // view, which is the size the board shows, whatever the zoom is.
        XCTAssertEqual(composed.width, width)
        XCTAssertEqual(composed.height, height)

        XCTAssertTrue(isReddish(pixel(composed, x: 60, y: 70)), "left edge at view (60,70)")
        XCTAssertTrue(isReddish(pixel(composed, x: 99, y: 70)), "right edge at view (99,70)")
        XCTAssertTrue(isReddish(pixel(composed, x: 80, y: 50)), "top edge at view (80,50)")
        XCTAssertTrue(isReddish(pixel(composed, x: 80, y: 89)), "bottom edge at view (80,89)")
        XCTAssertTrue(isWhitesh(pixel(composed, x: 80, y: 70)), "the interior stays clear")
        // The 1:1 placement the zoomless compositor used must not appear.
        XCTAssertTrue(isWhitesh(pixel(composed, x: 40, y: 45)), "the unzoomed spot stays empty")
        XCTAssertTrue(isWhitesh(pixel(composed, x: 10, y: 40)), "the panned-only spot stays empty")
    }
}
