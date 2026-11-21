import CoreGraphics
import XCTest

import StareCore

/// Independent blur-base probes (T12/S9, brought in from the verifier): the
/// board's live frame must be sampled at its own scale on both axes, in the
/// right orientation, and an unusable frame must never crash the compositor.
final class BlurBaseProbeTests: XCTestCase {
    private func image(_ w: Int, _ h: Int, _ fill: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        fill(ctx)
        return ctx.makeImage()!
    }

    private func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var data = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ctx = CGContext(data: &data, width: img.width, height: img.height, bitsPerComponent: 8,
                            bytesPerRow: img.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let o = (y * img.width + x) * 4
        return (data[o], data[o + 1], data[o + 2])
    }

    // Display-sized base 300x150 px = 100x50 points at scale 3; the live frame
    // is the same screen downscaled 3x (100x50 px), the shape LiveFrameSource
    // produces at downscale 0.5 of a 1x display... here a 3x ratio on purpose.
    func testBlurBaseXIsSampledAtTheFramesOwnScale() {
        let base = image(300, 150) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 150))
        }
        // Frame: left half black, right half white (bottom-left origin, full height).
        let frame = image(100, 50) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 50, y: 0, width: 50, height: 50))
        }
        // A: points 10..40 → frame px 10..40 (black half).
        // With the base's scale (3) it would crop frame px 30..120 and bleed white.
        let a = Stroke(tool: .blur, ink: .red, points: [CGPoint(x: 10, y: 20), CGPoint(x: 40, y: 40)])
        // B: points 60..90 → frame px 60..90 (white half).
        let b = Stroke(tool: .blur, ink: .red, points: [CGPoint(x: 60, y: 20), CGPoint(x: 90, y: 40)])
        let out = MarkCompositor.composite(marks: [a, b], over: base, scale: 3, blurBase: frame)!
        let pa = pixel(out, 75, 90)   // A's centre in base pixels
        let pb = pixel(out, 225, 90)  // B's centre
        print("PROBE blur-x A=\(pa.r) expect<80 B=\(pb.r) expect>200")
        XCTAssertLessThan(pa.r, 80, "a mark over the frame's black half must stay black")
        XCTAssertGreaterThan(pb.r, 200, "a mark over the frame's white half must stay white")
    }

    func testBlurBaseYIsFlippedAndScaled() {
        let base = image(300, 150) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 150))
        }
        // Frame: black on top in view space, white at the bottom.
        let frame = image(100, 50) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 25, width: 100, height: 25)) // bottom-origin top half
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 25))
        }
        // C near the top of the page (points y 5..20), D near the bottom (30..45).
        let c = Stroke(tool: .blur, ink: .red, points: [CGPoint(x: 40, y: 5), CGPoint(x: 70, y: 20)])
        let d = Stroke(tool: .blur, ink: .red, points: [CGPoint(x: 40, y: 30), CGPoint(x: 70, y: 45)])
        let out = MarkCompositor.composite(marks: [c, d], over: base, scale: 3, blurBase: frame)!
        let pc = pixel(out, 165, 36)
        let pd = pixel(out, 165, 111)
        print("PROBE blur-y C=\(pc.r) expect<200 D=\(pd.r) expect>200")
        XCTAssertLessThan(pc.r, 200, "the top of the page must sample the frame's top (black)")
        XCTAssertGreaterThan(pd.r, 200, "the bottom of the page must sample the frame's bottom (white)")
    }

    func testTinyOrMissingBlurBaseDoesNotCrash() {
        let base = image(60, 60) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        }
        let tiny = image(1, 1) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let mark = Stroke(tool: .blur, ink: .red, points: [CGPoint(x: 5, y: 5), CGPoint(x: 25, y: 25)])
        XCTAssertNotNil(MarkCompositor.composite(marks: [mark], over: base, blurBase: tiny))
        XCTAssertNotNil(MarkCompositor.composite(marks: [mark], over: base))
        // Nothing of Stare may crash on a frame whose aspect differs from the base either.
        let odd = image(40, 90) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 90))
        }
        XCTAssertNotNil(MarkCompositor.composite(marks: [mark], over: base, blurBase: odd))
    }
}
