import AppKit
import CoreGraphics
import XCTest
@testable import Stare
import StareCore

/// The numbered step's glyph on the live drawing overlay (editor-save-in-place
/// L7): the digit belongs to `MarkRenderer` — the ONE glyph decision every
/// surface shares — so the overlay's live drawing must add no second digit of
/// its own over `MarkRenderer.draw`. The preview the user sees while drawing
/// is exactly the pixels the capture keeps.
final class OverlayNumberTests: XCTestCase {
    private let size = CGSize(width: 100, height: 80)
    private let centre = CGPoint(x: 50, y: 40)

    /// The overlay's live drawing of a committed step mark carries exactly one
    /// digit, the renderer's: near-black glyph pixels sit inside the yellow
    /// ball at the mark's centre, and every pixel of the digit's window
    /// matches a direct `MarkRenderer.draw` of the same mark. A second,
    /// differently weighted digit painted on top would darken the window
    /// beyond the tolerance — same centre or not, its extra weight shows.
    func testTheOverlayDrawsExactlyOneDigitAtTheMarksCentreFromTheRenderer() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen to host the probe")
        let state = EditorState()
        // The armed-frame preference persists on the machine: pin it off so
        // the probe's edge band cannot leak into the sampled window.
        state.showArmedFrame = false
        let view = OverlayView(
            frame: CGRect(origin: .zero, size: size), state: state, onEscape: {})
        let mark = Stroke(tool: .number, ink: .yellow, points: [centre], stepNumber: 1)
        view.session = DrawingSession.restored(strokes: [mark])

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.confineToPrimaryScreen()
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let overlay = try Reader(overlayImage(view))
        let direct = try Reader(rendererImage(mark))

        // Harness sanity: the direct one-glyph draw does put the digit down,
        // so the comparison below cannot pass on an empty window.
        XCTAssertGreaterThan(
            digitPixels(in: direct), 0,
            "the renderer must draw the digit for this comparison to mean anything")
        // The digit is there through the overlay's own path...
        XCTAssertGreaterThan(
            digitPixels(in: overlay), 0,
            "the overlay's live drawing shows no digit at the mark's centre")
        // ... and it is the ONLY one: the live pixels agree with the renderer's
        // one-glyph draw inside the digit's window.
        var worst = 0
        var worstAt = CGPoint.zero
        let span = 16
        let px = Int(centre.x) * 2, py = Int(centre.y) * 2
        for dy in -span...span {
            for dx in -span...span {
                let a = overlay.rgb(x: px + dx, y: py + dy)
                let b = direct.rgb(x: px + dx, y: py + dy)
                for (index, left) in [a.r, a.g, a.b, a.a].enumerated() {
                    let right = [b.r, b.g, b.b, b.a][index]
                    let delta = abs(Int(left) - Int(right))
                    if delta > worst {
                        worst = delta
                        worstAt = CGPoint(x: px + dx, y: py + dy)
                    }
                }
            }
        }
        XCTAssertLessThanOrEqual(
            worst, 8,
            "the overlay's live drawing must carry exactly one digit, the renderer's — " +
            "a second glyph's weight would darken the window (worst delta \(worst) at \(worstAt))")
    }

    // MARK: - Harness

    /// Near-black glyph pixels within 8 pt of the centre, sampled at 2× so the
    /// 15-pt digit's strokes clear the anti-aliasing floor (the same threshold
    /// the shared-path test in `MarkRendererTests` uses).
    private func digitPixels(in render: Reader) -> Int {
        var count = 0
        let px = Int(centre.x) * 2, py = Int(centre.y) * 2
        for dy in -16...16 {
            for dx in -16...16 {
                let pixel = render.rgb(x: px + dx, y: py + dy)
                if pixel.r < 26, pixel.g < 26, pixel.b < 26 { count += 1 }
            }
        }
        return count
    }

    /// The real view's paint at 2×: `view.draw(_:)` with the flip and the
    /// transform `cacheDisplay` would set up for a flipped view — top-left
    /// origin at 2× pixels — into the same sRGB space the direct render below
    /// reads, so the two rasters interpret the ink identically.
    private func overlayImage(_ view: OverlayView) throws -> CGImage {
        let width = Int(size.width) * 2, height = Int(size.height) * 2
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.scaleBy(x: 2, y: 2)
        // Overlay space is top-left origin; the bitmap context is bottom-left.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(ctx.makeImage(), "the overlay snapshot failed to render")
    }

    /// `MarkRenderer.draw` of the same mark over a transparent base, in the
    /// overlay-space context shape every production caller uses (top-left
    /// origin), rasterized at 2× in the same sRGB space the overlay snapshot
    /// reads.
    private func rendererImage(_ mark: Stroke) throws -> CGImage {
        let width = Int(size.width) * 2, height = Int(size.height) * 2
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.scaleBy(x: 2, y: 2)
        // Overlay space is top-left origin; the bitmap context is bottom-left.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        MarkRenderer.draw(strokes: [mark], in: ctx)
        return try XCTUnwrap(ctx.makeImage(), "the direct renderer snapshot failed")
    }

    /// A top-left-origin RGBA reader over an image, so comparisons read each
    /// image once (the same reader the redaction parity test uses).
    private struct Reader {
        let width: Int
        let height: Int
        let data: [UInt8]

        init(_ image: CGImage) throws {
            width = image.width
            height = image.height
            var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let ctx = try XCTUnwrap(CGContext(
                data: &buffer, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            data = buffer
        }

        func rgb(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let offset = (y * width + x) * 4
            return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
        }
    }
}
