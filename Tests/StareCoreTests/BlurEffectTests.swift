import CoreGraphics
import XCTest

import StareCore

final class BlurEffectTests: XCTestCase {
    // MARK: - Helpers

    /// Black on the left half, white on the right half, uniform top to bottom,
    /// so a pixel near the vertical boundary betrays any real blur. Sized large
    /// enough for the radius that CoreImage keeps the true Gaussian path.
    private func twoToneImage(width: Int = 64, height: Int = 32) -> CGImage {
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
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width / 2), height: CGFloat(height)))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: CGFloat(width / 2), y: 0, width: CGFloat(width - width / 2), height: CGFloat(height)))
        return context.makeImage()!
    }

    /// Reads a pixel with the origin at the top-left.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> UInt8 {
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
        return data[(y * image.width + x) * 4]
    }

    // MARK: - Real blur

    // T5/S3: the boundary pixel must end up strictly between the two halves:
    // a copy of the region would keep it at one extreme, not a mix.
    func testBlurMixesValuesAcrossTheBoundary() {
        let image = twoToneImage()
        let straddling = CGRect(x: 24, y: 4, width: 16, height: 24)

        let blurred = BlurEffect.crop(image, pixelRect: straddling, radius: 3)
        XCTAssertNotNil(blurred)
        XCTAssertEqual(CGFloat(blurred!.width), straddling.width, accuracy: 1)
        XCTAssertEqual(CGFloat(blurred!.height), straddling.height, accuracy: 1)

        // The boundary sits at x = 32, the crop's centre; the image is
        // uniform vertically, so any row shows the same mix.
        let boundary = pixel(blurred!, x: 8, y: 12)
        XCTAssertGreaterThan(boundary, 30, "must pick up white from the right half")
        XCTAssertLessThan(boundary, 225, "must pick up black from the left half")

        // Far inside each half the values stay close to that half's value.
        XCTAssertLessThan(pixel(blurred!, x: 0, y: 12), 30, "deep in the black half")
        XCTAssertGreaterThan(pixel(blurred!, x: 15, y: 12), 225, "deep in the white half")
    }

    func testRectsClearOfTheBoundaryStayUnblurredAtTheEdges() {
        let image = twoToneImage()

        // A crop fully inside the black half keeps its black edges, because the
        // blur samples edge-extended content instead of darkening the border.
        let blackOnly = BlurEffect.crop(
            twoToneImage(),
            pixelRect: CGRect(x: 1, y: 1, width: 10, height: 10),
            radius: 3
        )
        XCTAssertNotNil(blackOnly)
        XCTAssertLessThan(pixel(blackOnly!, x: 0, y: 0), 30, "the crop border must not darken")

        let whiteOnly = BlurEffect.crop(
            twoToneImage(),
            pixelRect: CGRect(x: 53, y: 21, width: 10, height: 10),
            radius: 3
        )
        XCTAssertNotNil(whiteOnly)
        XCTAssertGreaterThan(pixel(whiteOnly!, x: 9, y: 9), 225, "the crop border must not wash out")
    }

    // MARK: - Fallbacks

    func testEmptyRectReturnsNil() {
        let image = twoToneImage()
        XCTAssertNil(BlurEffect.crop(image, pixelRect: .zero, radius: 8))
        XCTAssertNil(BlurEffect.crop(image, pixelRect: CGRect(x: 5, y: 5, width: 0, height: 10), radius: 8))
    }

    func testRectOutsideTheImageReturnsNil() {
        let image = twoToneImage()
        XCTAssertNil(
            BlurEffect.crop(image, pixelRect: CGRect(x: 70, y: 0, width: 10, height: 10), radius: 3)
        )
        XCTAssertNil(
            BlurEffect.crop(image, pixelRect: CGRect(x: 0, y: 40, width: 10, height: 10), radius: 3)
        )
    }

    func testRectPartialOverlapCropsToTheIntersection() {
        let image = twoToneImage()
        let overlapping = BlurEffect.crop(
            image,
            pixelRect: CGRect(x: 59, y: 8, width: 20, height: 10),
            radius: 3
        )
        XCTAssertNotNil(overlapping)
        // Only the 5 columns that lie inside the image can be returned.
        XCTAssertEqual(CGFloat(overlapping!.width), 5, accuracy: 1)
        XCTAssertEqual(CGFloat(overlapping!.height), 10, accuracy: 1)
    }
}
