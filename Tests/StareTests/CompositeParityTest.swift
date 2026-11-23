import AppKit
import CoreGraphics
import XCTest

import StareCore

/// S15 slice A (T8): the other half of the parity promise — what the overlay
/// drew must still be in the capture after the file path's own round trip.
/// A filled shape and a filled arrow head have to survive the lossy encode a
/// folder save performs and still read as the marks the preview showed.
final class CompositeParityTest: XCTestCase {
    /// A plain white capture base, bottom-left origin.
    private func makeBase(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Re-renders `image` through an sRGB RGBA context and answers its pixels,
    /// so any decodable image — a JPEG round trip included — reads directly.
    private func pixels(_ image: CGImage) -> (data: [UInt8], width: Int, height: Int) {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let reader = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        reader.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (bytes, width, height)
    }

    func testFilledShapeSurvivesTheCaptureFileRoundTrip() throws {
        let width = 120, height = 90
        let base = makeBase(width: width, height: height)
        let marks = [
            Stroke(tool: .rectangle, ink: .red, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 60)], fill: true),
            Stroke(tool: .arrow, ink: .green, points: [CGPoint(x: 30, y: 70), CGPoint(x: 90, y: 45)], arrowHead: .filled),
        ]
        let composited = try XCTUnwrap(MarkCompositor.composite(marks: marks, over: base))

        // The encode a folder save performs, and its decode.
        let jpeg = try XCTUnwrap(
            NSBitmapImageRep(cgImage: composited)
                .representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        )
        let decodedImage = try XCTUnwrap(
            NSImage(data: jpeg)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
            "the encoded capture must decode"
        )

        let before = pixels(composited)
        let after = pixels(decodedImage)
        XCTAssertTrue(after.width >= width && after.height >= height)

        func channel(_ probe: (data: [UInt8], width: Int, height: Int), at point: CGPoint) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            // Overlay space is top-left; the bitmap rows run bottom-up.
            let x = min(probe.width - 1, max(0, Int(point.x)))
            let y = min(probe.height - 1, max(0, probe.height - Int(point.y)))
            let index = (y * probe.width + x) * 4
            return (CGFloat(probe.data[index]) / 255, CGFloat(probe.data[index + 1]) / 255, CGFloat(probe.data[index + 2]) / 255)
        }

        // Inside the filled rectangle the red wash must still reign: the
        // green channel stays clearly below the bare base on both sides of
        // the lossy encode.
        let insidePoint = CGPoint(x: 50, y: 40)
        XCTAssertLessThan(channel(before, at: insidePoint).g, 0.9, "the composited fill must hold before encoding")
        XCTAssertLessThan(channel(after, at: insidePoint).g, 0.95, "the decoded capture must still show the fill")

        // A bare spot of the same capture must read back as bare — the fill
        // cannot have leaked anywhere, and the encode must not have darkened
        // the base.
        let outsidePoint = CGPoint(x: 15, y: 8)
        XCTAssertGreaterThan(channel(after, at: outsidePoint).g, 0.97, "the bare base must survive the encode too")
    }
}
