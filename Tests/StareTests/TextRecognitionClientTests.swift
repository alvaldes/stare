import AppKit
import CoreImage
import XCTest
@testable import Stare
@testable import StareCore

/// The OCR/QR recognition client (T5/S7). Vision runs for real here: the
/// synthetic images carry real pixels with real text and a real QR code, so
/// the recognition path is exercised, not mocked. The clipboard is a spy —
/// nothing a test recognises ever touches the user's clipboard, and the
/// Screen Recording permission is injected, so no test prompts or captures.
@MainActor
final class TextRecognitionClientTests: XCTestCase {
    private var clipboard: ClipboardSpy!
    private var capture: FakeScreenCapture!

    override func setUp() {
        super.setUp()
        clipboard = ClipboardSpy()
        capture = FakeScreenCapture()
    }

    override func tearDown() {
        clipboard = nil
        capture = nil
        super.tearDown()
    }

    // MARK: - Fakes

    final class ClipboardSpy: ClipboardWriting {
        private(set) var copied: [String] = []
        func copyString(_ string: String) { copied.append(string) }
    }

    final class FakeScreenCapture: ScreenCapturing {
        var hasPermission = true
        var captureCount = 0
        var image: CGImage?
        func requestPermission() {}
        func captureDisplay(_ displayID: CGDirectDisplayID) throws -> CGImage {
            captureCount += 1
            if hasPermission, let image { return image }
            throw CaptureError.permissionDenied
        }
    }

    // MARK: - Synthetic imagery

    /// An sRGB bitmap with a white background and optional black-on-white
    /// text centred on it, drawn through AppKit so Vision sees real glyphs.
    private func textImage(size: CGSize, text: String) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        // CoreText draws upright into the raw y-up CG context — no flipping
        // layers for the glyphs to vanish through.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 72),
            .foregroundColor: NSColor.black,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(string)
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textPosition = CGPoint(
            x: (size.width - textWidth) / 2,
            y: (size.height - 72) / 2)
        CTLineDraw(line, context)
        return context.makeImage()
    }

    /// A real QR code for `payload`, rendered on a white ground with the
    /// quiet zone every reader needs — generated on-device by CoreImage,
    /// exactly as offline as Vision is.
    private func qrImage(size: CGSize, payload: String) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator"),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let data = Data(payload.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = max(size.width, size.height) * 0.5 / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ciContext = CIContext(options: nil)
        guard let qr = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        context.draw(qr, in: CGRect(
            x: (size.width - scaled.extent.width) / 2,
            y: (size.height - scaled.extent.height) / 2,
            width: scaled.extent.width,
            height: scaled.extent.height))
        return context.makeImage()
    }

    /// Text across the top half and a QR code in the bottom half of one
    /// image, the mixed case the feature must answer to.
    private func mixedImage(size: CGSize, text: String, qrPayload: String) throws -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator"),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 60),
            .foregroundColor: NSColor.black,
        ])
        let line = CTLineCreateWithAttributedString(string)
        context.textPosition = CGPoint(x: 20, y: size.height - 60 - 10)
        CTLineDraw(line, context)
        let data = Data(qrPayload.utf8)
        filter.setValue(data, forKey: "inputMessage")
        let output = try XCTUnwrap(filter.outputImage)
        let ciContext = CIContext(options: nil)
        let height = size.height / 2.2
        let scale = height / output.extent.width
        guard let qr = ciContext.createCGImage(
            output.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
            from: output.extent.applying(CGAffineTransform(scaleX: scale, y: scale)))
        else { return nil }
        // The QR sits below the word: bottom of the image, in the CG's own
        // y-up space.
        context.draw(qr, in: CGRect(x: 20, y: 10, width: height, height: height))
        return context.makeImage()
    }

    // MARK: - Real recognition on synthetic pixels

    func testASyntheticImageWithRealTextIsRecognised() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "recognition needs a real graphics session")
        let image = try XCTUnwrap(textImage(size: CGSize(width: 900, height: 300), text: "STARE OCR TEST"))
        let client = TextRecognitionClient(captureService: capture, clipboard: clipboard)
        let result = await client.recognizePixels(image)
        guard case let .clipboard(string) = result else {
            return XCTFail("expected a clipboard result from real text, got \(result)")
        }
        XCTAssertTrue(string.contains("STARE"), "the recogniser saw the text: \(string)")
        XCTAssertTrue(string.contains("TEST"), "\(string)")
    }

    func testASyntheticQrPayloadIsRecognised() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "recognition needs a real graphics session")
        let image = try XCTUnwrap(qrImage(size: CGSize(width: 700, height: 700), payload: "https://stare.test/ocr-qr"))
        let client = TextRecognitionClient(captureService: capture, clipboard: clipboard)
        let result = await client.recognizePixels(image)
        guard case let .clipboard(string) = result else {
            return XCTFail("expected a clipboard result from a QR code, got \(result)")
        }
        XCTAssertTrue(string.contains("https://stare.test/ocr-qr"), "\(string)")
    }

    func testTextAndQrTogetherComeBackInReadingOrder() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "recognition needs a real graphics session")
        let image = try XCTUnwrap(
            mixedImage(size: CGSize(width: 800, height: 800), text: "TOKEN", qrPayload: "https://stare.test/qr-mix"))
        let client = TextRecognitionClient(captureService: capture, clipboard: clipboard)
        let result = await client.recognizePixels(image)
        guard case let .clipboard(string) = result else {
            return XCTFail("expected a clipboard result from mixed content, got \(result)")
        }
        let parts = string.components(separatedBy: "\n")
        XCTAssertEqual(parts.first, "TOKEN", "the word above the QR is read first: \(parts)")
        XCTAssertTrue(parts.contains("https://stare.test/qr-mix"), "the QR payload is kept: \(parts)")
    }

    func testABlankSelectionMeansNothingFoundAndClipboardUntouched() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "recognition needs a real graphics session")
        let image = try XCTUnwrap(textImage(size: CGSize(width: 600, height: 400), text: ""))
        let client = TextRecognitionClient(captureService: capture, clipboard: clipboard)
        let result = await client.recognizePixels(image)
        XCTAssertEqual(result, .nothingFound)
        XCTAssertTrue(clipboard.copied.isEmpty, "an empty recognition never copies over the clipboard")
    }

    // MARK: - The full gesture path, permission and clipboard included

    private func primary() throws -> NSScreen {
        try XCTUnwrap(NSScreen.screens.first, "the gesture needs a real display")
    }

    func testMissingScreenRecordingIsReportedWithoutCapturingOrPrompting() async throws {
        let screen = try primary()
        capture.hasPermission = false
        let client = TextRecognitionClient(captureService: capture, clipboard: clipboard)
        let selection = screen.frame.insetBy(dx: 100, dy: 100)
        let result = await client.recognize(selection: selection, on: screen)
        XCTAssertEqual(result, .permissionMissing, "the gesture says so, it does not prompt")
        XCTAssertEqual(capture.captureCount, 0, "a permission-less gesture captures nothing")
        XCTAssertTrue(clipboard.copied.isEmpty)
    }

    func testACaptureFailureIsReportedAndClipboardUntouched() async throws {
        let screen = try primary()
        capture.hasPermission = true
        capture.image = nil // the fake throws on every capture
        let client = TextRecognitionClient(captureService: capture, clipboard: clipboard)
        let result = await client.recognize(selection: screen.frame.insetBy(dx: 100, dy: 100), on: screen)
        XCTAssertEqual(result, .failed)
        XCTAssertTrue(clipboard.copied.isEmpty)
    }

    func testARecognisedSelectionReachesTheClipboardInOnePiece() async throws {
        let screen = try primary()
        capture.hasPermission = true
        // The fake display returns exactly the screen frame's pixels, so the
        // crop below is the selection, and the text drawn in the middle is
        // inside it.
        capture.image = try XCTUnwrap(
            textImage(size: screen.frame.integral.size, text: "STARE"))
        let client = TextRecognitionClient(captureService: capture, clipboard: clipboard)
        let selection = screen.frame.insetBy(dx: 120, dy: 200)
        let result = await client.recognize(selection: selection, on: screen)
        guard case let .clipboard(string) = result else {
            return XCTFail("expected a clipboard result, got \(result)")
        }
        XCTAssertEqual(clipboard.copied, [string], "exactly one copy lands on the clipboard")
        XCTAssertTrue(string.contains("STARE"), "\(string)")
    }
}
