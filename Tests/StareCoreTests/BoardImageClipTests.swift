import AppKit
import CoreGraphics
import XCTest

import StareCore

/// A partly off-base image layer is clipped, not squeezed: the composite is
/// drawn through the layer's FULL scaled rect and cut by the context's clip
/// at the visible intersection, so the capture and a blur's beneath-image
/// show exactly the pixels the board's view shows — the same semantics as
/// the board view's own `context.draw` clipping.
final class BoardImageClipTests: XCTestCase {

    // MARK: Helpers

    private func solid(
        _ width: Int,
        _ height: Int,
        _ left: CGColor,
        _ right: CGColor? = nil
    ) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(left)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let right {
            context.setFillColor(right)
            context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        }
        return context.makeImage()!
    }

    /// A pixel in BOTTOM-LEFT coordinates, read through the rep's top-left
    /// accessor — the same helper shape `BoardImageTests` uses.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let representation = NSBitmapImageRep(cgImage: image)
        let colour = representation.colorAt(x: x, y: image.height - 1 - y)!.usingColorSpace(.deviceRGB)!
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue)
    }

    // MARK: The probe

    func testAPartlyOffBaseLayerIsClippedNotSqueezed() throws {
        // A 2×1 layer, left red and right blue, drawn at rect (-50, 0, 100, 100)
        // over a 100 pt base: only the layer's RIGHT half lies over the base, so
        // the composite's covered half must be the layer's blue, at the scale
        // the full rect dictates — never the whole image squeezed into the
        // visible strip.
        let layer = BoardImage(
            image: solid(2, 1, CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)),
            rect: CGRect(x: -50, y: 0, width: 100, height: 100)
        )
        let composed = try XCTUnwrap(
            layer.composited(over: solid(100, 100, CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)), transform: .identity, scale: 1)
        )

        XCTAssertEqual(composed.width, 100, "the layer never enlarges the capture")
        XCTAssertEqual(composed.height, 100)

        let visibleHalfBlue = pixel(composed, x: 10, y: 50)
        XCTAssertGreaterThan(visibleHalfBlue.blue, 0.6, "the view's covered half shows the blue half of the image")
        XCTAssertLessThan(visibleHalfBlue.red, 0.4, "not the red half squeezed into the strip")
        let squeezedWouldBeRed = pixel(composed, x: 45, y: 50)
        XCTAssertGreaterThan(squeezedWouldBeRed.blue, 0.6, "the scale comes from the full rect, so the deep strip is still blue")
        let offLayer = pixel(composed, x: 75, y: 50)
        XCTAssertGreaterThan(offLayer.red, 0.9, "beyond the layer's rect the base shows through untouched")
        XCTAssertGreaterThan(offLayer.green, 0.9)
        XCTAssertGreaterThan(offLayer.blue, 0.9)
    }
}
