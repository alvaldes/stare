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
}
