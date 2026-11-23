import AppKit
import XCTest

@testable import StareCore

/// Tests for the save-time downscale decision (T7/S14): the arithmetic is
/// pure — target width for 1× and for a maximum width, the floor so nothing
/// degrades to nothing, and when to leave the image alone — plus the thin
/// encode path's contract: with the switch off, the file write is byte
/// identical to today's, and the clipboard path is never touched.
final class CaptureDownscaleTests: XCTestCase {
    // MARK: Off — today's behaviour (S14: apagada por defecto)

    func testOffAlwaysLeavesTheImageAlone() {
        XCTAssertNil(CaptureDownscale.targetPixelWidth(
            pixelWidth: 2880, logicalWidth: 1440, mode: .off, maxPixelWidth: 1600
        ))
        XCTAssertNil(CaptureDownscale.targetPixelWidth(
            pixelWidth: 40, logicalWidth: 40, mode: .off, maxPixelWidth: 20
        ))
        XCTAssertNil(CaptureDownscale.targetPixelWidth(
            pixelWidth: 5, logicalWidth: nil, mode: .off, maxPixelWidth: 1
        ))
    }

    // MARK: 1× — the logical size, never an upscale

    func testOneXScalesARetinaCaptureToItsLogicalWidth() {
        XCTAssertEqual(CaptureDownscale.targetPixelWidth(
            pixelWidth: 2880, logicalWidth: 1440, mode: .oneX, maxPixelWidth: 1600
        ), 1440)
        // An odd logical size still names its nearest pixel.
        XCTAssertEqual(CaptureDownscale.targetPixelWidth(
            pixelWidth: 2880, logicalWidth: 1439.5, mode: .oneX, maxPixelWidth: 1600
        ), 1440)
        XCTAssertEqual(CaptureDownscale.targetPixelWidth(
            pixelWidth: 2001, logicalWidth: 1000.4, mode: .oneX, maxPixelWidth: 1600
        ), 1000)
    }

    func testOneXNeverUpscalesAnAlreadyLogicalCapture() {
        // A 1× capture asked to become 1× stays as it is.
        XCTAssertNil(CaptureDownscale.targetPixelWidth(
            pixelWidth: 1440, logicalWidth: 1440, mode: .oneX, maxPixelWidth: 1600
        ))
        // A capture larger than its logical width cannot happen for an honest
        // scale, but the rule holds anyway: never up.
        XCTAssertNil(CaptureDownscale.targetPixelWidth(
            pixelWidth: 800, logicalWidth: 1440, mode: .oneX, maxPixelWidth: 1600
        ))
    }

    func testOneXWithoutALogicalWidthLeavesTheImageAlone() {
        // The caller cannot vouch for a scale: no guess, no scaling.
        XCTAssertNil(CaptureDownscale.targetPixelWidth(
            pixelWidth: 2880, logicalWidth: nil, mode: .oneX, maxPixelWidth: 1600
        ))
        XCTAssertNil(CaptureDownscale.targetPixelWidth(
            pixelWidth: 2880, logicalWidth: 0, mode: .oneX, maxPixelWidth: 1600
        ))
        XCTAssertNil(CaptureDownscale.targetPixelWidth(
            pixelWidth: 2880, logicalWidth: -1440, mode: .oneX, maxPixelWidth: 1600
        ))
    }

    // MARK: Max width — and the floor so nothing degrades to nothing

    func testMaxWidthScalesOnlyWiderCapturesDown() {
        XCTAssertEqual(CaptureDownscale.targetPixelWidth(
            pixelWidth: 2880, logicalWidth: 1440, mode: .maxWidth, maxPixelWidth: 1600
        ), 1600)
        // A capture smaller than the requested max width is left alone.
        XCTAssertNil(CaptureDownscale.targetPixelWidth(
            pixelWidth: 1200, logicalWidth: 600, mode: .maxWidth, maxPixelWidth: 1600
        ))
        // Exactly at the limit: nothing to do.
        XCTAssertNil(CaptureDownscale.targetPixelWidth(
            pixelWidth: 1600, logicalWidth: 800, mode: .maxWidth, maxPixelWidth: 1600
        ))
    }

    func testMaxWidthNeverTargetsBelowOnePixel() {
        // A garbage limit degrades to the 1-pixel floor instead of nothing.
        XCTAssertEqual(CaptureDownscale.targetPixelWidth(
            pixelWidth: 5, logicalWidth: nil, mode: .maxWidth, maxPixelWidth: 0
        ), 1)
        XCTAssertEqual(CaptureDownscale.targetPixelWidth(
            pixelWidth: 5, logicalWidth: nil, mode: .maxWidth, maxPixelWidth: -100
        ), 1)
    }

    func testOneXFloorKeepsADegenerateLogicalWidthAtOnePixel() {
        // A logical width under a pixel still floors at 1 rather than
        // degrading to nothing — and only applies when it is actually a
        // downscale of the capture.
        XCTAssertEqual(CaptureDownscale.targetPixelWidth(
            pixelWidth: 4, logicalWidth: 0.4, mode: .oneX, maxPixelWidth: 1600
        ), 1)
    }

    // MARK: The thin redraw

    /// A solid image, so dimensions are all a scaled copy can change.
    private func solidImage(width: Int, height: Int) -> CGImage? {
        CGImage.solid(width: width, height: height)
    }

    func testImageScalesDownPreservingAspect() throws {
        let image = try XCTUnwrap(solidImage(width: 40, height: 20))
        let scaled = try XCTUnwrap(CaptureDownscale.image(image, targetPixelWidth: 20))
        XCTAssertEqual(scaled.width, 20)
        XCTAssertEqual(scaled.height, 10)
    }

    func testImageRefusesANonDownscale() throws {
        let image = try XCTUnwrap(solidImage(width: 40, height: 20))
        // Never an upscale, and the identity stays a no-op.
        XCTAssertNil(CaptureDownscale.image(image, targetPixelWidth: 40))
        XCTAssertNil(CaptureDownscale.image(image, targetPixelWidth: 80))
        XCTAssertNil(CaptureDownscale.image(image, targetPixelWidth: 0))
        XCTAssertNil(CaptureDownscale.image(image, targetPixelWidth: -10))
    }

    func testImageFloorsTheHeightAtOnePixel() throws {
        let image = try XCTUnwrap(solidImage(width: 40, height: 1))
        let scaled = try XCTUnwrap(CaptureDownscale.image(image, targetPixelWidth: 20))
        XCTAssertEqual(scaled.width, 20)
        XCTAssertEqual(scaled.height, 1)
    }

    // MARK: The file write (T7/S14) — off is byte identical to today

    /// The image every write test uses: 40×10, too small to be real but big
    /// enough for the encoders.
    private var sampleImage: CGImage { CGImage.solid(width: 40, height: 10)! }

    private var folderURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stare-downscale-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let folderURL {
            try? FileManager.default.removeItem(at: folderURL)
        }
        folderURL = nil
        try super.tearDownWithError()
    }

    private func preference(mode: CaptureDownscale.Mode, maxSaveWidth: Int = CapturePreference.defaultMaxSaveWidth) -> CapturePreference {
        var preference = CapturePreference(
            format: .png,
            destination: .folder(path: folderURL.path),
            fileNamePrefix: "Stare"
        )
        preference.downscaleMode = mode
        preference.maxSaveWidth = maxSaveWidth
        return preference
    }

    /// Today's encode, computed independently of `CaptureFile`, so the
    /// byte-identical proof does not compare the code with itself.
    private func legacyEncode(_ image: CGImage, format: CaptureFormat) throws -> Data {
        let type: NSBitmapImageRep.FileType = format == .png ? .png : .jpeg
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: type, properties: [:]))
    }

    private func writtenData(for preference: CapturePreference, scale: CGFloat? = nil) throws -> Data {
        let date = Date(timeIntervalSince1970: 1_763_702_733)
        let url = try XCTUnwrap(
            CaptureFile.write(sampleImage, preference: preference, date: date, scale: scale),
            "the write must succeed"
        )
        return try XCTUnwrap(Data(contentsOf: url))
    }

    func testWriteWithDownscaleOffIsByteIdenticalToTodaysEncode() throws {
        // The switch off: every capture is saved exactly as today — same
        // pixels, same encoder, same bytes.
        XCTAssertEqual(
            try writtenData(for: preference(mode: .off)),
            try legacyEncode(sampleImage, format: .png)
        )
    }

    func testWriteWithMaxWidthScalesTheFileDown() throws {
        let data = try writtenData(for: preference(mode: .maxWidth, maxSaveWidth: 20))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 20)
        XCTAssertEqual(rep.pixelsHigh, 5)
        // And it is not today's bytes: the file really was rescaled.
        XCTAssertNotEqual(data, try legacyEncode(sampleImage, format: .png))
    }

    func testWriteWithMaxWidthSmallerThanTheCaptureLeavesTheFileByteIdentical() throws {
        // A capture smaller than the requested max width is written as today.
        XCTAssertEqual(
            try writtenData(for: preference(mode: .maxWidth, maxSaveWidth: 1600)),
            try legacyEncode(sampleImage, format: .png)
        )
    }

    func testWriteWithOneXAndUnknownScaleLeavesTheFileByteIdentical() throws {
        // 1× needs a scale the caller vouches for; without one nothing is
        // guessed and the file is written as today.
        XCTAssertEqual(
            try writtenData(for: preference(mode: .oneX), scale: nil),
            try legacyEncode(sampleImage, format: .png)
        )
    }

    func testWriteWithOneXAndScaleScalesTheFileDownToLogicalSize() throws {
        // A 2× 40-pixel-wide capture has a 20-point logical width.
        let data = try writtenData(for: preference(mode: .oneX), scale: 2)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 20)
        XCTAssertEqual(rep.pixelsHigh, 5)
    }

    func testWriteIgnoresAnUnusableDestinationExactlyAsBefore() {
        var preference = preference(mode: .maxWidth, maxSaveWidth: 20)
        preference.destination = .clipboard
        XCTAssertNil(
            CaptureFile.write(sampleImage, preference: preference, date: Date()),
            "the clipboard destination is not a file write, unchanged"
        )
    }

    func testClipboardPathIsNeverTouchedByDownscaling() throws {
        // The pasteboard encode is the plain representation call and never
        // even sees the preference: downscaling applies to the file write
        // only, so no mode can change what the clipboard gets.
        XCTAssertEqual(
            CaptureFile.data(for: sampleImage, format: .png),
            try legacyEncode(sampleImage, format: .png)
        )
    }
}

/// `CGImage.solid(width:height:)` mirrors the test helper above so the
/// preference-level write tests can build images too.
private extension CGImage {
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
