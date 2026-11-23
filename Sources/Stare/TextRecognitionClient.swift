import AppKit
import StareCore
import Vision

/// Writes text to the system clipboard. Injectable so the recognition tests
/// can observe a copy without ever touching the user's real clipboard.
protocol ClipboardWriting: AnyObject {
    func copyString(_ string: String)
}

/// The real clipboard behind the feature: the recognised text, and nothing
/// else, lands as plain text.
final class PasteboardClipboard: ClipboardWriting {
    func copyString(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        Diag.log("text recognition copied \(string.count) characters")
    }
}

/// What the whole gesture produced. `dismissed` is the undersize selection:
/// the plan refused it, so nothing is captured and the clipboard is
/// untouched. `nothingFound` and `failed` are reported through the hint
/// surface instead of copying an empty string over the user's clipboard.
enum TextRecognitionResult: Equatable {
    case clipboard(String)
    case nothingFound
    case permissionMissing
    case failed
    case dismissed
}

/// Vision glue for on-device text and QR recognition (T5/S7). The client
/// reads the pixels the pointer's display carries, crops the selection, and
/// runs `VNRecognizeTextRequest` and `VNDetectBarcodesRequest` — both local
/// to the machine, no network call of any kind (S8). The permission check is
/// a preflight: a missing Screen Recording grant is *reported*, never
/// prompted mid-gesture (S9) — the gesture points at System Settings instead.
@MainActor
final class TextRecognitionClient {
    let captureService: any ScreenCapturing
    private let clipboard: any ClipboardWriting

    init(
        captureService: any ScreenCapturing = CaptureService(),
        clipboard: any ClipboardWriting = PasteboardClipboard()
    ) {
        self.captureService = captureService
        self.clipboard = clipboard
    }

    /// One recognition on already-prepared pixels: real Vision (text lines
    /// and barcodes on the same image), then the pure reading-order decision,
    /// then the clipboard copy on success only.
    func recognizePixels(_ image: CGImage) async -> TextRecognitionResult {
        let observations: [TextRecognitionObservation]
        do {
            observations = try await Self.recognise(in: image)
        } catch {
            Diag.log("text recognition failed: \(error.localizedDescription)")
            return .failed
        }
        switch TextRecognition.clipboardOutcome(from: observations) {
        case .clipboard(let string):
            clipboard.copyString(string)
            return .clipboard(string)
        case .nothingFound:
            return .nothingFound
        }
    }

    /// The full gesture: preflight the permission, accept the plan's
    /// dismissal of an undersize drag, capture the pointer's display, crop
    /// the selection into display pixels, apply the plan's scale, and
    /// recognise. Every fallthrough that cannot read pixels is reported, so
    /// the user always gets a plain answer.
    func recognize(selection: CGRect, on screen: NSScreen) async -> TextRecognitionResult {
        // The non-prompting TCC check: no consent dialog is ever opened in
        // the middle of the gesture.
        guard captureService.hasPermission else { return .permissionMissing }
        guard let displayID = Self.displayID(of: screen) else { return .failed }

        let plan = TextRecognition.plan(selection: selection, displayScale: screen.backingScaleFactor)
        guard case let .capture(visionScale) = plan else { return .dismissed }

        guard let display = try? captureService.captureDisplay(displayID) else { return .failed }

        let pixelScale = CGFloat(display.width) / screen.frame.width
        guard pixelScale > 0, pixelScale.isFinite else { return .failed }
        var crop = TextRecognition.cropRect(selection: selection, in: screen.frame, pixelScale: pixelScale)
        crop = crop
            .intersection(CGRect(x: 0, y: 0, width: display.width, height: display.height))
            .integral
        guard crop.width >= 1, crop.height >= 1 else { return .nothingFound }
        guard let pixels = display.cropping(to: crop) else { return .failed }

        let input = Self.resample(
            pixels,
            targetLongestSide: max(selection.width, selection.height) * visionScale
        )
        Diag.log("text recognition crop=\(crop) input=\(input.width)x\(input.height)")
        return await recognizePixels(input)
    }

    /// Text lines and barcodes from one image, mapped into
    /// `TextRecognitionObservation`s whose coordinate space keeps the reading
    /// order decision pure: Vision reports bounding boxes in a bottom-left
    /// normalized space, converted to pixel centres with the larger `centerY`
    /// still meaning higher on the page.
    static func recognise(in image: CGImage) async throws -> [TextRecognitionObservation] {
        // Vision is synchronous and CPU-bound, so the main thread (the
        // hotkey's handler) waits detached, exactly like the capture path.
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let text = VNRecognizeTextRequest()
                // Accurate runs the on-device model; no network is involved.
                text.recognitionLevel = .accurate
                text.usesLanguageCorrection = false
                let barcode = VNDetectBarcodesRequest()
                let handler = VNImageRequestHandler(cgImage: image)

                var observations: [TextRecognitionObservation] = []
                do {
                    try handler.perform([text, barcode])
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                if let results = text.results as? [VNRecognizedTextObservation] {
                    for result in results {
                        guard let line = result.topCandidates(1).first?.string else { continue }
                        observations.append(Self.observation(
                            payload: line,
                            boundingBox: result.boundingBox,
                            imageSize: image.size))
                    }
                }
                if let results = barcode.results as? [VNBarcodeObservation] {
                    for result in results where result.payloadStringValue != nil {
                        observations.append(Self.observation(
                            payload: result.payloadStringValue!,
                            boundingBox: result.boundingBox,
                            imageSize: image.size))
                    }
                }
                continuation.resume(returning: observations)
            }
        }
    }

    private nonisolated static func observation(
        payload: String,
        boundingBox: CGRect,
        imageSize: CGSize
    ) -> TextRecognitionObservation {
        TextRecognitionObservation(
            payload: payload,
            // Vision reports bounding boxes in a bottom-left normalized
            // space: multiplied by the image height, larger means higher on
            // the page — exactly the convention the reading order sorts by.
            centerY: Double(boundingBox.midY * imageSize.height),
            centerX: Double(boundingBox.midX * imageSize.width)
        )
    }

    /// Brings the longest pixel side down (only down) to the plan's target, so
    /// an oversize selection costs Vision a bounded input instead of a
    /// framebuffer. A target at or above the current size leaves the pixels
    /// untouched — recognition never upsamples beyond what the display gave.
    static func resample(_ image: CGImage, targetLongestSide: CGFloat) -> CGImage {
        let longest = max(image.width, image.height)
        let target = Int(targetLongestSide.rounded())
        guard target > 0, target < longest else { return image }
        let factor = CGFloat(target) / CGFloat(longest)
        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}

extension CGImage {
    /// CGSize from a CGImage's pixel dimensions, in pixels.
    fileprivate var size: CGSize {
        CGSize(width: width, height: height)
    }
}
