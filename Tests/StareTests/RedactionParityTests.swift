import AppKit
import CoreGraphics
import XCTest
@testable import Stare
import StareCore

/// T6b/S13 parity: the live preview and the saved capture must redact a
/// randomized-pixelate mark through the ONE dispatch `MarkRenderer
/// .redactionPatch` — the mark that previews pixelated is saved pixelated,
/// before and after the editor's zoom (the claim in odd/tasks/
/// capture-extras.md L9). The preview side drives the real `OverlayView`
/// paint (the same `drawBlur` the whiteboard reuses for its board preview)
/// over a synthetic live frame; the save side drives `MarkCompositor
/// .composite` and the editor's `composedImage()`, the interface Save and
/// Copy use.
@MainActor
final class RedactionParityTests: XCTestCase {
    private let size = CGSize(width: 900, height: 600)
    private let patchRect = CGRect(x: 200, y: 100, width: 300, height: 300)

    // MARK: - Fixtures

    /// White with thin black vertical stripes (2 px, one stripe pair per 24 px
    /// inside the patch): the letter-stroke-thin fixture
    /// `RedactionDispatchTests` pins against.
    private func stripedPattern() -> CGImage {
        let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for stripe in stride(from: Int(patchRect.minX) + 20, to: Int(patchRect.maxX) - 10, by: 24) {
            context.fill(CGRect(x: stripe, y: 0, width: 2, height: Int(size.height)))
        }
        return context.makeImage()!
    }

    private func pixelateMark() -> Stroke {
        var mark = Stroke(
            tool: .blur,
            ink: .blue,
            points: [patchRect.origin, CGPoint(x: patchRect.maxX, y: patchRect.maxY)]
        )
        mark.redactionStyle = .randomizedPixelate
        return mark
    }

    /// Renders `view`'s own paint into a top-left RGB bitmap at exactly one
    /// point per pixel, so the view's paint and the compositor's raster are
    /// read on the same grid regardless of the window's backing scale.
    private func snapshot(_ view: NSView, size: CGSize) -> CGImage? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: NSColorSpaceName.calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        representation.size = size
        // `cacheDisplay` sets up the flip and the transform the view's own
        // paint relies on; calling `view.draw(_:)` into a bare context would
        // not.
        view.cacheDisplay(in: view.bounds, to: representation)
        return representation.cgImage
    }

    /// A top-left-origin RGBA reader over an image, so whole-region
    /// comparisons read each image once instead of per sample.
    private struct Reader {
        let width: Int
        let data: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(
                data: &buffer, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            data = buffer
        }

        func rgb(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            let offset = (y * width + x) * 4
            return (data[offset], data[offset + 1], data[offset + 2])
        }

        func rgbA(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let offset = (y * width + x) * 4
            return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
        }
    }

    /// Every channel of every sample inside `rect` agrees within `tolerance`.
    private func assertRegion(
        _ a: CGImage, matches b: CGImage, inside rect: CGRect,
        tolerance: Int, _ message: String
    ) {
        let left = Reader(a)
        let right = Reader(b)
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let first = left.rgb(x: x, y: y)
                let second = right.rgb(x: x, y: y)
                let redDelta = abs(Int(first.r) - Int(second.r)) <= tolerance
                let greenDelta = abs(Int(first.g) - Int(second.g)) <= tolerance
                let blueDelta = abs(Int(first.b) - Int(second.b)) <= tolerance
                XCTAssertTrue(
                    redDelta && greenDelta && blueDelta,
                    "\(message) at (\(x), \(y)) \(first) vs \(second)")
            }
        }
    }

    // MARK: - Preview paint and saved raster redact through one dispatch

    func testLivePreviewAndSaveProduceTheSamePixelatedPixels() throws {
        let pattern = stripedPattern()
        let view = OverlayView(frame: CGRect(origin: .zero, size: size), state: EditorState(), onEscape: {})

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.confineToPrimaryScreen()
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        // The mark the session holds is the mark both paths paint: the same
        // style and (through the mark's identity) the same seed.
        let mark = pixelateMark()
        view.session = DrawingSession.restored(strokes: [mark])

        // Feed the known pattern through the real frame source path (T5/S3):
        // a fake capture answers immediately, so no Screen Recording and no
        // real frame is involved.
        let displayID = CGDirectDisplayID(1)
        let live = LiveFrameSource(capture: { _, _ in pattern })
        live.displaysNeedingFrames = { [displayID] }
        live.wake()
        defer { live.stop() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertNotNil(live.frame(for: displayID), "the fake frame source must have delivered the pattern")

        view.displayID = displayID
        view.liveFrameSource = live
        view.invalidateLiveBlurMarks()

        let preview = try XCTUnwrap(
            snapshot(view, size: size),
            "the live preview snapshot failed to render")
        // The view's pixels-per-point for this fake frame is exactly 1
        // (frame width / bounds width), so the compositor gets the same grid:
        // `scale: 1` over the same base.
        let saved = try XCTUnwrap(MarkCompositor.composite(marks: [mark], over: pattern, scale: 1))

        assertRegion(
            preview, matches: saved, inside: patchRect, tolerance: 3,
            "the live preview and the saved capture must redact identically")

        // The redaction is real, not a straight copy of the pattern: inside
        // the patch no pixelate block may carry glyph colour (the original
        // stripes are plain black), and outside the paint is untouched.
        let previewReader = Reader(preview)
        for stripe in stride(from: Int(patchRect.maxY) - 10, to: Int(patchRect.minY) + 10, by: -17) {
            let sample = previewReader.rgb(x: Int(patchRect.midX), y: stripe)
            XCTAssertGreaterThanOrEqual(
                Int(min(sample.r, min(sample.g, sample.b))), 120,
                "no glyph colour may survive in the preview's redacted block at \(stripe)")
        }
        // The overlay layer paints nothing outside its marks: the sample
        // outside must stay fully transparent, never a redaction spill.
        let outside = Reader(preview).rgbA(x: 50, y: 50)
        XCTAssertEqual(outside.a, 0, "outside the mark the preview must paint nothing at all")
    }

    // MARK: - The editor's zoom never re-decides the redaction (L9)

    func testTheEditorZoomSavesTheSamePixelatedPixels() throws {
        let imageBounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let canvasRect = CGRect(x: 0, y: 0, width: 300, height: 200)
        let imageRect = CGRect(x: 20, y: 20, width: 60, height: 60)

        let context = CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(imageBounds)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for stripe in stride(from: 26, to: 76, by: 12) {
            context.fill(CGRect(x: stripe, y: 0, width: 2, height: 100))
        }
        let image = context.makeImage()!

        let fitted = EditorCropSpace.fitted(coverage: imageBounds, inCanvas: canvasRect)
        var mark = Stroke(
            tool: .blur,
            ink: .blue,
            points: [imageRect.origin, CGPoint(x: imageRect.maxX, y: imageRect.maxY)]
        )
        mark.redactionStyle = .randomizedPixelate

        func seededComposed(zoomed: Bool) throws -> CGImage {
            let canvas = CaptureEditorCanvas(image: image)
            let state = EditorState()
            canvas.state = state
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: canvasRect.size),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.confineToPrimaryScreen()
            window.contentView = canvas
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }

            var space = fitted
            if zoomed {
                canvas.applyZoom(3, anchoredAt: CGPoint(x: 150, y: 100))
                space = EditorCropSpace.fitted(
                    coverage: imageBounds, viewport: canvas.viewportState, inCanvas: canvasRect)
            }
            // The same mark — same id, so the same seed — seeded exactly where
            // the mark-in-hand path would record it: at the active space's
            // view rect over the same image pixels. Both editors then ask the
            // compositor for the same redacted rectangle at the fit-sized
            // save target, which is what zoom is not allowed to move.
            var placed = mark
            let viewRect = space.viewRect(fromPixel: imageRect)
            placed.points = [viewRect.origin, CGPoint(x: viewRect.maxX, y: viewRect.maxY)]
            canvas.seedMarks([placed])
            return try XCTUnwrap(canvas.composedImage(), "the editor save composition failed")
        }

        let fitComposed = try seededComposed(zoomed: false)
        let zoomedComposed = try seededComposed(zoomed: true)
        XCTAssertEqual(
            NSBitmapImageRep(cgImage: zoomedComposed).tiffRepresentation,
            NSBitmapImageRep(cgImage: fitComposed).tiffRepresentation,
            "after the editor's zoom the same pixelate mark must save exactly the pixels the fit saves")

        // The saved patch is the pixelate the mark names, not its blur twin:
        // the save is the capture's own pixels and the mark covers the same
        // image rectangle there in bitmap (bottom-left) coordinates, so the
        // expectation simply names that rectangle.
        let pixelRectX = imageRect.minX
        let pixelRectY = CGFloat(image.height) - imageRect.maxY
        let pixelRect = CGRect(
            x: pixelRectX,
            y: pixelRectY,
            width: imageRect.width,
            height: imageRect.height
        )
        let primitive = try XCTUnwrap(
            PixelateEffect.crop(image, pixelRect: pixelRect, seed: mark.redactionSeed),
            "the pixelate primitive must produce the patch")
        let composedReader = Reader(fitComposed)
        let primitiveReader = Reader(primitive)
        // The crop is bottom-left oriented like the save bitmap; the Reader
        // walks top-down, so crop row r (0 = bottom of the rect) sits at
        // bitmap row `height - 1 - (y + r)` from the top.
        let originX = Int(pixelRectX)
        let originY = Int(pixelRectY)
        for r in 0..<Int(pixelRect.height) {
            for dx in 0..<Int(pixelRect.width) {
                let top = composedReader.rgb(x: originX + dx, y: originY + r)
                let patch = primitiveReader.rgb(x: dx, y: r)
                let redDelta = abs(Int(top.r) - Int(patch.r)) <= 3
                let greenDelta = abs(Int(top.g) - Int(patch.g)) <= 3
                let blueDelta = abs(Int(top.b) - Int(patch.b)) <= 3
                XCTAssertTrue(
                    redDelta && greenDelta && blueDelta,
                    "the saved redaction must be the mark's pixelate patch at (\(dx), \(r)) \(top) vs \(patch)")
            }
        }
    }
}
