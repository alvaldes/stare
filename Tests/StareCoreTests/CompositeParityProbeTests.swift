import CoreGraphics
import CryptoKit
import XCTest
import StareCore

/// Independent parity probe (T12/S9, brought in from the verifier): the
/// drawing overlay's capture path calls MarkCompositor.composite without a
/// blur base, so its output must be byte-identical before and after T12.
final class CompositeParityProbeTests: XCTestCase {
    func testDrawingOverlayCompositeBytes() {
        let width = 300, height = 150
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 150))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.9, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 30, y: 20, width: 120, height: 60)) // bottom-left origin
        let base = ctx.makeImage()!

        let marks = [
            Stroke(tool: .pen, ink: .red, points: [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 30), CGPoint(x: 35, y: 15)]),
            Stroke(tool: .rectangle, ink: .blue, points: [CGPoint(x: 50, y: 30), CGPoint(x: 90, y: 45)]),
            Stroke(tool: .blur, ink: .red, points: [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 35)]),
            Stroke(tool: .arrow, ink: .green, points: [CGPoint(x: 60, y: 5), CGPoint(x: 95, y: 20)]),
        ]
        let out = MarkCompositor.composite(marks: marks, over: base, scale: 3)!
        var data = [UInt8](repeating: 0, count: out.width * out.height * 4)
        let read = CGContext(data: &data, width: out.width, height: out.height, bitsPerComponent: 8,
                             bytesPerRow: out.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        read.draw(out, in: CGRect(x: 0, y: 0, width: out.width, height: out.height))
        print("PARITY size=\(out.width)x\(out.height) sha256=\(SHA256.hash(data: Data(data)))")
    }

    // MARK: - S15 slice A: filled shapes and filled heads must arrive in the
    // capture exactly what the overlay preview showed

    /// The RGBA bytes of an image, read through an sRGB bitmap context.
    private func bytes(of image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let reader = CGContext(
            data: &data,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        reader.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// The parity probe for the new mark properties (S15, T8 slice A): the
    /// overlay's preview path renders marks through `MarkRenderer`, and the
    /// compositor must reproduce those same decisions over the base, so the
    /// values sampled inside a filled shape and inside a filled arrow head
    /// are drawn by the compositor exactly as the shared renderer draws them.
    func testFilledShapeAndFilledHeadCompositorMatchesRendererPath() {
        let width = 120, height = 90
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let base = ctx.makeImage()!

        let marks: [Stroke] = [
            Stroke(tool: .rectangle, ink: .red, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 60)], fill: true),
            Stroke(tool: .arrow, ink: .green, points: [CGPoint(x: 30, y: 70), CGPoint(x: 90, y: 45)], arrowHead: .filled),
        ]

        // The composited capture…
        let composited = bytes(of: MarkCompositor.composite(marks: marks, over: base)!)    
        // …and the same marks laid down straight by the renderer — the exact
        // surface the overlay preview paints through.
        let probe = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        probe.setFillColor(CGColor(gray: 1, alpha: 1))
        probe.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // The compositor's own placement math: top-left overlay space lands
        // in the bottom-left bitmap, so the renderer's output must agree
        // pixel for pixel under the same flip it applies.
        probe.translateBy(x: 0, y: CGFloat(height))
        probe.scaleBy(x: 1, y: -1)
        MarkRenderer.draw(strokes: marks, in: probe)
        let direct = bytes(of: probe.makeImage()!)

        if composited.count != direct.count {
            XCTFail("composite and renderer probe differ in size")
            return
        }
        for (index, byte) in composited.enumerated() where byte != direct[index] {
            XCTFail("composite and renderer probe diverge at byte \(index): \(byte) vs \(direct[index])")
            return
        }
    }

    /// The fill and the filled head must actually reach the capture: the
    /// composited pixels inside a filled shape and inside a filled head are
    /// no longer the bare base.
    func testCompositorCarriesTheFillAndTheFilledHead() {
        let width = 120, height = 90
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let base = ctx.makeImage()!

        let marks: [Stroke] = [
            Stroke(tool: .rectangle, ink: .red, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 60)], fill: true),
            Stroke(tool: .arrow, ink: .green, points: [CGPoint(x: 30, y: 70), CGPoint(x: 90, y: 45)], arrowHead: .filled),
        ]
        let image = bytes(of: MarkCompositor.composite(marks: marks, over: base)!)
        func pixel(at point: CGPoint) -> (CGFloat, CGFloat, CGFloat) {
            // Top-left overlay point space; the bitmap's rows run bottom-up.
            let x = Int(point.x), y = height - 1 - Int(point.y)
            let index = (y * width + x) * 4
            return (CGFloat(image[index]) / 255, CGFloat(image[index + 1]) / 255, CGFloat(image[index + 2]) / 255)
        }

        // Inside the filled rectangle the ink wash must hold, at the same
        // alpha the preview paints the shape with.
        let inside = pixel(at: CGPoint(x: 50, y: 40))
        XCTAssertEqual(inside.0, 1, accuracy: 0.02, "red fill keeps its red channel on white")
        XCTAssertEqual(inside.1, 1 - 0.3 + 0.3 * 0.23, accuracy: 0.05, "red fill washes the green channel down by 0.3 alpha")

        // Inside the filled head the ink must be at full opacity, not a bare
        // base: the head triangle's centre, three points behind the tip.
        let head = pixel(at: CGPoint(x: 90 - 12, y: 45 + 2.5))
        XCTAssertTrue(head.1 < 0.9 && head.2 < 0.9, "the filled head's triangle interior must carry green ink, got \(head)")
    }
}
