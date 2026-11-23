import CoreGraphics
import XCTest

import StareCore

final class PixelateEffectTests: XCTestCase {
    // MARK: - Helpers

    /// Four quadrants, each a solid tone with a small brighter dot inside it,
    /// so every cell has a value range that does not overlap its neighbours.
    /// A block that sampled outside its own cell would fall outside the range.
    private func cellRangeImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let tones: [UInt8] = [40, 90, 140, 200]
        for row in 0..<2 {
            for column in 0..<2 {
                // CGContext fills with a bottom-left origin, but blocks are
                // read back top-left first, so invert y when placing.
                let cellRect = CGRect(x: column * 32, y: (1 - row) * 32, width: 32, height: 32)
                let tone = tones[row * 2 + column]
                context.setFillColor(
                    CGColor(srgbRed: CGFloat(tone) / 255, green: CGFloat(tone) / 255, blue: CGFloat(tone) / 255, alpha: 1)
                )
                context.fill(cellRect)
                // A small darker dot inside the cell so the cell's own range
                // still has room under the tone but never reaches a
                // neighbour's tone.
                context.setFillColor(
                    CGColor(srgbRed: CGFloat(tone) / 2 / 255, green: CGFloat(tone) / 2 / 255, blue: CGFloat(tone) / 2 / 255, alpha: 1)
                )
                context.fill(CGRect(x: cellRect.minX + 6, y: cellRect.minY + 6, width: 4, height: 4))
            }
        }
        return context.makeImage()!
    }

    /// Vertical stripes with a period of one block: within every cell the left
    /// half is black and the right half is white, so the naive whole-cell mean
    /// is always the mid grey, while a moved sample window can sit on either
    /// side.
    private func stripeImage(width: Int = 128, height: Int = 64) -> CGImage {
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
        for cellStart in stride(from: 0, to: width, by: 16) {
            context.fill(CGRect(x: cellStart, y: 0, width: 8, height: height))
        }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        for cellStart in stride(from: 8, to: width, by: 16) {
            context.fill(CGRect(x: cellStart, y: 0, width: 8, height: height))
        }
        return context.makeImage()!
    }

    /// Dark text on white, drawn with CoreText so no window is involved.
    private func textImage() -> (image: CGImage, rect: CGRect) {
        let rect = CGRect(x: 16, y: 8, width: 300, height: 48)
        let context = CGContext(
            data: nil,
            width: 340,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 340, height: 64))
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 24, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, "Stare" as CFString, attributes as CFDictionary)!
        )
        context.textPosition = CGPoint(x: rect.minX, y: rect.minY)
        CTLineDraw(line, context)
        return (context.makeImage()!, rect)
    }

    /// Reads a pixel's red channel with the origin at the top-left.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        rgbaBytes(image)[(y * image.width + x) * 4]
    }

    private func rgbaBytes(_ image: CGImage) -> [UInt8] {
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
        return data
    }

    // MARK: - Contract shared with BlurEffect

    func testOutputHasTheRectsExactSize() {
        let image = stripeImage()
        let rect = CGRect(x: 16, y: 20, width: 64, height: 40)

        let pixelated = PixelateEffect.crop(image, pixelRect: rect)
        XCTAssertNotNil(pixelated)
        XCTAssertEqual(pixelated!.width, 64, "the returned image must match the rect's exact width")
        XCTAssertEqual(pixelated!.height, 40, "the returned image must match the rect's exact height")
    }

    func testEmptyRectReturnsNil() {
        let image = stripeImage()
        XCTAssertNil(PixelateEffect.crop(image, pixelRect: .zero))
        XCTAssertNil(PixelateEffect.crop(image, pixelRect: CGRect(x: 5, y: 5, width: 0, height: 10)))
    }

    func testRectOutsideTheImageReturnsNil() {
        let image = stripeImage()
        XCTAssertNil(PixelateEffect.crop(image, pixelRect: CGRect(x: 200, y: 0, width: 10, height: 10)))
        XCTAssertNil(PixelateEffect.crop(image, pixelRect: CGRect(x: 0, y: 100, width: 10, height: 10)))
    }

    func testRectPartialOverlapCropsToTheIntersection() {
        let image = stripeImage()
        let overlapping = PixelateEffect.crop(image, pixelRect: CGRect(x: 100, y: 8, width: 60, height: 20))
        XCTAssertNotNil(overlapping)
        XCTAssertEqual(overlapping!.width, 28, "only the 28 columns inside the image can be returned")
        XCTAssertEqual(overlapping!.height, 20)
    }

    // MARK: - Block size: derived from the mark, floored, not shrinkable

    func testBlockSizeIsDerivedFromTheMarkWithAFloor() {
        // Half the mark's smaller side, when that is above the floor.
        XCTAssertEqual(
            PixelateEffect.blockSize(for: CGRect(x: 0, y: 0, width: 240, height: 48)),
            24,
            accuracy: 0
        )
        // Below the floor the floor wins, so a small mark still bites.
        XCTAssertEqual(
            PixelateEffect.blockSize(for: CGRect(x: 0, y: 0, width: 10, height: 6)),
            PixelateEffect.minimumBlockSize,
            accuracy: 0
        )
    }

    func testRequestedBlockBelowTheFloorIsClamped() {
        let image = stripeImage()
        let rect = CGRect(x: 0, y: 0, width: 64, height: 64)

        // A block of 2 pixels is honoured as the floor instead: the output is
        // byte-identical to an explicit floor-sized request.
        let clamped = PixelateEffect.crop(image, pixelRect: rect, blockSize: 2)
        let floored = PixelateEffect.crop(image, pixelRect: rect, blockSize: PixelateEffect.minimumBlockSize)
        XCTAssertNotNil(clamped)
        XCTAssertNotNil(floored)
        XCTAssertEqual(rgbaBytes(clamped!), rgbaBytes(floored!), "requested blocks below the floor must clamp to the floor")
    }

    // MARK: - What survives: nothing at block scale

    func testEveryBlockIsAConstantColourTakenFromInsideItsOwnCell() {
        let image = cellRangeImage()
        let rect = CGRect(x: 0, y: 0, width: 64, height: 64)
        let input = rgbaBytes(image)

        let pixelated = PixelateEffect.crop(image, pixelRect: rect, blockSize: 32)!
        let output = rgbaBytes(pixelated)
        XCTAssertEqual(pixelated.width, 64)
        XCTAssertEqual(pixelated.height, 64)

        let cellTones: [(min: UInt8, max: UInt8)] = [(20, 40), (45, 90), (70, 140), (100, 200)]
        for row in 0..<2 {
            for column in 0..<2 {
                let cellRect = CGRect(x: column * 32, y: row * 32, width: 32, height: 32)
                let range = cellTones[row * 2 + column]

                // Every pixel of the output block is the one constant colour.
                let blockColour = pixel(pixelated, x: column * 32, y: row * 32)
                for y in 0..<32 {
                    for x in 0..<32 {
                        XCTAssertEqual(
                            output[Int((row * 32 + y) * 64 + column * 32 + x) * 4],
                            blockColour,
                            "block at \(cellRect) must be constant"
                        )
                    }
                }

                // The colour came from inside that block's own cell: it lies
                // within the cell's value range, which no neighbour's range
                // reaches (each range stops short of the next tone up).
                XCTAssertGreaterThanOrEqual(blockColour, range.min, "block at \(cellRect)")
                XCTAssertLessThanOrEqual(blockColour, range.max, "block at \(cellRect)")

                // Sanity on the fixture itself: the cell's own pixels fill the
                // asserted range.
                var cellMin: UInt8 = 255
                var cellMax: UInt8 = 0
                for y in 0..<32 {
                    for x in 0..<32 {
                        let value = input[Int((row * 32 + y) * 64 + column * 32 + x) * 4]
                        cellMin = min(cellMin, value)
                        cellMax = max(cellMax, value)
                    }
                }
                XCTAssertLessThanOrEqual(Int(cellMin), Int(range.min))
                XCTAssertGreaterThanOrEqual(Int(cellMax), Int(range.max))
            }
        }
    }

    func testOriginalDetailDoesNotSurviveAtBlockScale() {
        // A 2x2 white dot per block, on grey: after pixelating, no output
        // pixel comes close to the dot's value, because the block only
        // publishes an averaged sample from inside its cell.
        let context = CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        for cellX in [0, 32] {
            for cellY in [0, 32] {
                context.fill(CGRect(x: cellX + 15, y: cellY + 15, width: 2, height: 2))
            }
        }
        let image = context.makeImage()!
        let input = rgbaBytes(image)
        // Scan the red channel only: alpha bytes are 255 everywhere.
        let inputRed = stride(from: 0, to: input.count, by: 4).map { input[$0] }
        XCTAssertTrue(inputRed.contains(255), "fixture must really contain the detail")

        let pixelated = PixelateEffect.crop(image, pixelRect: CGRect(x: 0, y: 0, width: 64, height: 64), blockSize: 32)!
        let output = rgbaBytes(pixelated)
        let outputRed = stride(from: 0, to: output.count, by: 4).map { output[$0] }
        XCTAssertFalse(outputRed.contains(255), "the dot must not survive pixelation")
        XCTAssertFalse(
            outputRed.contains(where: { $0 > 64 }),
            "no output pixel may approach the dot's value; got max \(outputRed.max() ?? 0)"
        )
    }

    // MARK: - Randomized, deterministic

    func testSamplingOffsetsMoveInsideTheCellInsteadOfPublishingACellMean() {
        let image = stripeImage()
        let pixelated = PixelateEffect.crop(image, pixelRect: CGRect(x: 0, y: 0, width: 128, height: 64), blockSize: 16)!
        let output = rgbaBytes(pixelated)

        // The naive regular grid publishes the whole-cell mean (~128 grey) for
        // every block. With the sample window moved inside each cell, the
        // moved window lands mostly on one stripe for enough blocks that some
        // block colour drifts far from the mean.
        let extremes = stride(from: 0, to: output.count, by: 4).map { output[$0] }
        XCTAssertTrue(
            extremes.contains(where: { $0 <= 95 || $0 >= 159 }),
            "every block published the cell mean (\(Set(extremes))); the sample offsets must move"
        )
    }

    func testSameSeedIsByteIdenticalAndDifferentSeedsDiffer() {
        let image = stripeImage()
        let rect = CGRect(x: 0, y: 0, width: 128, height: 64)

        // An explicit block keeps the sample window (half of it) off the
        // stripe period, so a moved window really changes each block's mean.
        let first = PixelateEffect.crop(image, pixelRect: rect, blockSize: 16, seed: 7)!
        let second = PixelateEffect.crop(image, pixelRect: rect, blockSize: 16, seed: 7)!
        XCTAssertEqual(rgbaBytes(first), rgbaBytes(second), "the same seed must reproduce the same output")

        let other = PixelateEffect.crop(image, pixelRect: rect, blockSize: 16, seed: 8)!
        XCTAssertNotEqual(rgbaBytes(first), rgbaBytes(other), "a different seed must produce a different output")
    }

    // MARK: - The pressure point: strokes thinner than a block are lost

    func testTextFixtureWithStrokesThinnerThanABlockLosesTheStrokes() {
        let (image, rect) = textImage()
        let input = rgbaBytes(image)

        // The fixture has real stroke pixels: near-black on white.
        let strokePixels = stride(from: 0, to: input.count, by: 4).map { input[$0] }.filter { $0 < 60 }
        XCTAssertGreaterThan(strokePixels.count, 200, "the fixture must contain stroke pixels to lose")

        // The derived block for this mark is well above the stroke width, so
        // no sample window can sit fully inside a stroke: every output pixel
        // is far lighter than the strokes.
        let pixelated = PixelateEffect.crop(image, pixelRect: rect)!
        XCTAssertNotNil(pixelated)
        let output = rgbaBytes(pixelated)
        let outputMin = stride(from: 0, to: output.count, by: 4).map { output[$0] }.min() ?? 255
        XCTAssertGreaterThan(
            outputMin, 110,
            "strokes thinner than a block must be lost, not carried through; darkest output pixel was \(outputMin)"
        )
    }
}
