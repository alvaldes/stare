import AppKit
import XCTest

@testable import StareCore

/// Tests for the save backdrop (T11/S18): optional padding, rounded corners
/// and a shadow, composed purely in StareCore — no window, no screen — and
/// applied by the folder writer before any downscale, so the padding is never
/// resampled on its own and the original pixels are never re-encoded by the
/// backdrop itself. Off by default on every parameter, so a preference left
/// alone writes today's bytes. Sizes are clamped so a silly preference can
/// neither blank the capture nor grow the canvas enormous.
final class CaptureBackdropTests: XCTestCase {
    private var sampleImage: CGImage { CGImage.solid(width: 40, height: 10)! }

    private var folderURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stare-backdrop-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let folderURL {
            try? FileManager.default.removeItem(at: folderURL)
        }
        folderURL = nil
        try super.tearDownWithError()
    }

    private func folderPreference(
        padding: Int = 0,
        cornerRadius: Int = 0,
        shadow: Bool = false,
        downscaleMode: CaptureDownscale.Mode = .off,
        maxSaveWidth: Int = CapturePreference.defaultMaxSaveWidth
    ) -> CapturePreference {
        var preference = CapturePreference(
            format: .png,
            destination: .folder(path: folderURL.path),
            fileNamePrefix: "Stare"
        )
        preference.backdropPadding = padding
        preference.backdropCornerRadius = cornerRadius
        preference.backdropShadow = shadow
        preference.downscaleMode = downscaleMode
        preference.maxSaveWidth = maxSaveWidth
        return preference
    }

    private func writtenRep(for preference: CapturePreference, scale: CGFloat? = nil) throws -> NSBitmapImageRep {
        let date = Date(timeIntervalSince1970: 1_763_702_733)
        let url = try XCTUnwrap(
            CaptureFile.write(sampleImage, preference: preference, date: date, scale: scale),
            "the write must succeed"
        )
        return try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: url)))
    }

    // MARK: Off — today's behaviour, byte for byte (the PRESERVE pin's twin)

    func testCompositionWithEveryParameterOffIsNothing() {
        XCTAssertNil(
            CaptureBackdrop.composed(sampleImage, padding: 0, cornerRadius: 0, shadow: false),
            "every parameter off must leave the image alone, not redraw it"
        )
    }

    func testWriteWithBackdropDefaultsOffIsByteIdenticalToTodaysEncode() throws {
        let date = Date(timeIntervalSince1970: 1_763_702_733)
        let url = try XCTUnwrap(
            CaptureFile.write(sampleImage, preference: folderPreference(), date: date)
        )
        let written = try XCTUnwrap(Data(contentsOf: url))
        let today = try XCTUnwrap(
            NSBitmapImageRep(cgImage: sampleImage).representation(using: .png, properties: [:])
        )
        XCTAssertEqual(written, today, "a default preference must save exactly today's bytes")
    }

    // MARK: Padding — the canvas grows and the original pixels ride inside it

    func testPaddingGrowsTheCanvasByTwiceThePadding() throws {
        let composed = try XCTUnwrap(
            CaptureBackdrop.composed(sampleImage, padding: 5, cornerRadius: 0, shadow: false)
        )
        XCTAssertEqual(composed.width, 50, "add the padding on both sides")
        XCTAssertEqual(composed.height, 20)
    }

    func testPaddedRegionCarriesTheOriginalPixelsUnresampled() throws {
        // Rule by pixel comparison, not metaphor: inside the padded region the
        // pixel at (pad + x, pad + y) is exactly the original's (x, y), and
        // the added margin is fully transparent.
        let pad = 5
        let composed = try XCTUnwrap(
            CaptureBackdrop.composed(sampleImage, padding: pad, cornerRadius: 0, shadow: false)
        )
        let rep = try XCTUnwrap(NSBitmapImageRep(cgImage: composed))
        let original = try XCTUnwrap(NSBitmapImageRep(cgImage: sampleImage))
        for (x, y) in [(0, 0), (39, 0), (0, 9), (39, 9), (19, 4)] {
            XCTAssertEqual(
                rep.colorAt(x: pad + x, y: pad + y),
                original.colorAt(x: x, y: y),
                "the capture inside the padding must be the original pixels, offset"
            )
        }
        for (x, y) in [(0, 0), (49, 0), (0, 19), (49, 19)] {
            let color = try XCTUnwrap(rep.colorAt(x: x, y: y))
            XCTAssertEqual(color.alphaComponent, 0, "the padding margin stays transparent")
        }
    }

    // MARK: Rounded corners — the capture's corners go transparent

    func testCornerRadiusRoundsTheCaptureCorners() throws {
        let pad = 2
        let composed = try XCTUnwrap(
            CaptureBackdrop.composed(sampleImage, padding: pad, cornerRadius: 4, shadow: false)
        )
        XCTAssertEqual(composed.width, 44)
        XCTAssertEqual(composed.height, 14)
        let rep = try XCTUnwrap(NSBitmapImageRep(cgImage: composed))
        let original = try XCTUnwrap(NSBitmapImageRep(cgImage: sampleImage))
        // A square canvas would carry the capture's opaque corner here; the
        // radius rounds it away. The centre still carries the capture whole.
        XCTAssertLessThan(try XCTUnwrap(rep.colorAt(x: pad, y: pad)).alphaComponent, 1.0)
        XCTAssertEqual(
            rep.colorAt(x: pad + 20, y: pad + 5),
            original.colorAt(x: 20, y: 5),
            "rounding must not resample the capture's interior"
        )
    }

    func testRadiusBeyondHalfTheShortestSideIsClampedAtCompose() throws {
        // A radius over half the capture would invert the rounded rect and
        // blank the image; the compose clamps it at the half side and keeps
        // drawing — pinned by comparing against the exact boundary value.
        let boundary = try XCTUnwrap(
            CaptureBackdrop.composed(sampleImage, padding: 2, cornerRadius: 5, shadow: false),
            "half of the 10-pixel height is the largest honest radius"
        )
        let silly = try XCTUnwrap(
            CaptureBackdrop.composed(sampleImage, padding: 2, cornerRadius: 999_999, shadow: false)
        )
        XCTAssertEqual(silly.width, boundary.width)
        XCTAssertEqual(silly.height, boundary.height)
        let sillyRep = try XCTUnwrap(NSBitmapImageRep(cgImage: silly))
        let original = try XCTUnwrap(NSBitmapImageRep(cgImage: sampleImage))
        XCTAssertEqual(sillyRep.colorAt(x: 22, y: 7), original.colorAt(x: 20, y: 5), "the interior is still the capture")
    }

    // MARK: Shadow — a fixed cheap shadow on a larger canvas

    func testShadowAddsAFixedMarginToTheCanvas() throws {
        let composed = try XCTUnwrap(
            CaptureBackdrop.composed(sampleImage, padding: 0, cornerRadius: 0, shadow: true)
        )
        XCTAssertEqual(composed.width, sampleImage.width + 2 * CaptureBackdrop.shadowCanvasMargin)
        XCTAssertEqual(composed.height, sampleImage.height + 2 * CaptureBackdrop.shadowCanvasMargin)
    }

    func testShadowKeepsTheCapturePixelsAndShadesOutsideThem() throws {
        let margin = CaptureBackdrop.shadowCanvasMargin
        let composed = try XCTUnwrap(
            CaptureBackdrop.composed(sampleImage, padding: 0, cornerRadius: 0, shadow: true)
        )
        let rep = try XCTUnwrap(NSBitmapImageRep(cgImage: composed))
        let original = try XCTUnwrap(NSBitmapImageRep(cgImage: sampleImage))
        for (x, y) in [(0, 0), (39, 9), (19, 4)] {
            XCTAssertEqual(
                rep.colorAt(x: margin + x, y: margin + y),
                original.colorAt(x: x, y: y),
                "the shadow is drawn behind the capture; the capture is drawn over it unchanged"
            )
        }
        // Just outside the capture the shadow is present but not opaque.
        let shade = try XCTUnwrap(rep.colorAt(x: margin - 2, y: margin + 5))
        XCTAssertGreaterThan(shade.alphaComponent, 0, "a shadow actually reaches outside the capture")
        XCTAssertLessThan(shade.alphaComponent, 1.0, "the shadow never paints over the neighbourhood opaquely")
    }

    func testNoShadowLeavesTheMarginFullyTransparentWhereShadowWouldShade() throws {
        let pad = 6
        let composed = try XCTUnwrap(
            CaptureBackdrop.composed(sampleImage, padding: pad, cornerRadius: 0, shadow: false)
        )
        let rep = try XCTUnwrap(NSBitmapImageRep(cgImage: composed))
        let color = try XCTUnwrap(rep.colorAt(x: pad - 2, y: pad + 5))
        XCTAssertEqual(color.alphaComponent, 0, "without the shadow the margin stays clean")
    }

    // MARK: The write order — padding before the downscale, never after

    func testWriteAppliesPaddingBeforeTheDownscaleResamplesIt() throws {
        // A 40×10 capture with padding 10 and a 20-pixel max width: the
        // padded 60×30 canvas is scaled to 20 wide, so the file is 20×10 and
        // the capture fills two thirds of it. Applied after the downscale
        // instead, the file would be 40×25 — this dimension would fail.
        let rep = try XCTUnwrap(
            writtenRep(for: folderPreference(padding: 10, downscaleMode: .maxWidth, maxSaveWidth: 20))
        )
        XCTAssertEqual(rep.pixelsWide, 20)
        XCTAssertEqual(rep.pixelsHigh, 10)
    }

    func testWriteOneXScalesThePaddedCanvasToItsOwnLogicalSize() throws {
        // A 2× 40×10 capture padded by 5 becomes a 50×20 canvas whose
        // logical size is 25×10; 1× scales that whole canvas, padding and all.
        let rep = try XCTUnwrap(
            writtenRep(for: folderPreference(padding: 5, downscaleMode: .oneX), scale: 2)
        )
        XCTAssertEqual(rep.pixelsWide, 25)
        XCTAssertEqual(rep.pixelsHigh, 10)
    }

    // MARK: Clamps — a silly preference can neither blank nor enlarge madly

    func testPaddingClampsAtTheMaximum() {
        XCTAssertEqual(CaptureBackdrop.clampedPadding(0), 0)
        XCTAssertEqual(CaptureBackdrop.clampedPadding(-5), 0, "nothing degrades to nothing")
        XCTAssertEqual(CaptureBackdrop.clampedPadding(1_000_000), CaptureBackdrop.maxPadding)
        XCTAssertEqual(CaptureBackdrop.maxPadding, 128, "the documented maximum")
    }

    func testCornerRadiusClampsAtTheMaximum() {
        XCTAssertEqual(CaptureBackdrop.clampedCornerRadius(0), 0)
        XCTAssertEqual(CaptureBackdrop.clampedCornerRadius(-5), 0)
        XCTAssertEqual(CaptureBackdrop.clampedCornerRadius(1_000_000), CaptureBackdrop.maxCornerRadius)
        XCTAssertEqual(CaptureBackdrop.maxCornerRadius, 64, "the documented maximum")
    }

    func testMaximumBackdropFillsNeitherBlankNorEnormous() throws {
        // Padding and shadow at their ceilings on the tiny sample: the canvas
        // grows by at most 2×128 + 2×16 pixels, the capture is still there in
        // the middle, and the composition never fails.
        let composed = try XCTUnwrap(
            CaptureBackdrop.composed(
                sampleImage,
                padding: CaptureBackdrop.maxPadding,
                cornerRadius: CaptureBackdrop.maxCornerRadius,
                shadow: true
            )
        )
        XCTAssertEqual(
            composed.width,
            sampleImage.width + 2 * CaptureBackdrop.maxPadding + 2 * CaptureBackdrop.shadowCanvasMargin
        )
        let rep = try XCTUnwrap(NSBitmapImageRep(cgImage: composed))
        let original = try XCTUnwrap(NSBitmapImageRep(cgImage: sampleImage))
        XCTAssertEqual(
            rep.colorAt(x: CaptureBackdrop.maxPadding + CaptureBackdrop.shadowCanvasMargin + 20,
                        y: CaptureBackdrop.maxPadding + CaptureBackdrop.shadowCanvasMargin + 5),
            original.colorAt(x: 20, y: 5),
            "even at the clamps the capture is still inside, unresampled"
        )
    }

    // MARK: The preference fields — appended, defaults off, leniently decoded

    func testStandardPreferenceCarriesBackdropOff() {
        XCTAssertEqual(CapturePreference.standard.backdropPadding, 0)
        XCTAssertEqual(CapturePreference.standard.backdropCornerRadius, 0)
        XCTAssertFalse(CapturePreference.standard.backdropShadow)
        XCTAssertEqual(CaptureBackdrop.composed(
            sampleImage,
            padding: CapturePreference.standard.backdropPadding,
            cornerRadius: CapturePreference.standard.backdropCornerRadius,
            shadow: CapturePreference.standard.backdropShadow
        ), nil)
    }

    func testBlobWithoutBackdropFieldsDecodesOff() throws {
        let decoded = try JSONDecoder().decode(
            CapturePreference.self,
            from: Data(#"{"format":"jpeg","destination":{"folder":"/tmp/shots"},"fileNamePrefix":"Shots"}"#.utf8)
        )
        XCTAssertEqual(decoded.backdropPadding, 0)
        XCTAssertEqual(decoded.backdropCornerRadius, 0)
        XCTAssertFalse(decoded.backdropShadow)
    }

    func testGarbageBackdropValuesInBlobDecodeToOffAndKeepTheRest() throws {
        let decoded = try JSONDecoder().decode(
            CapturePreference.self,
            from: Data(
                #"{"format":"png","destination":{"clipboard":true},"fileNamePrefix":"Shots","backdropPadding":"wide","backdropCornerRadius":"round","backdropShadow":"yes"}"#
                    .utf8
            )
        )
        XCTAssertEqual(decoded.backdropPadding, 0)
        XCTAssertEqual(decoded.backdropCornerRadius, 0)
        XCTAssertFalse(decoded.backdropShadow)
        XCTAssertEqual(decoded.fileNamePrefix, "Shots", "the rest of the blob still decodes")
    }

    func testBackdropFieldsRoundTripThroughJSON() throws {
        var saved = CapturePreference.standard
        saved.backdropPadding = 16
        saved.backdropCornerRadius = 12
        saved.backdropShadow = true
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(CapturePreference.self, from: data), saved)
    }

    func testAssignedBackdropValuesAreClampedToo() {
        var preference = CapturePreference.standard
        preference.backdropPadding = 999_999
        XCTAssertEqual(preference.backdropPadding, CaptureBackdrop.maxPadding)
        preference.backdropPadding = -10
        XCTAssertEqual(preference.backdropPadding, 0)
        preference.backdropCornerRadius = 999_999
        XCTAssertEqual(preference.backdropCornerRadius, CaptureBackdrop.maxCornerRadius)
        preference.backdropCornerRadius = -10
        XCTAssertEqual(preference.backdropCornerRadius, 0)
    }

}

private extension CGImage {
    /// A small solid image, enough for the compositor and the encoders.
    static func solid(width: Int, height: Int) -> CGImage? {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }
}
