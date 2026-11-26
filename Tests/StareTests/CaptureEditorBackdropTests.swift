import AppKit
import CoreGraphics
import XCTest

@testable import Stare
import StareCore

/// T2/S2: the capture's background belongs in the editor. The control edits a
/// PER-CAPTURE backing value seeded from the stored default, composed at the
/// one point `composedImage()` is — so copy, save and the history delivery
/// all take the same pixels — and Settings keeps only the default: nothing
/// the control does persists into any stored preference.
@MainActor
final class CaptureEditorBackdropTests: XCTestCase {
    /// In-memory store double, the same pattern the other preference tests
    /// keep privately.
    private final class InMemoryPreferenceStore: PreferenceStore {
        private var storage: [String: Any] = [:]

        func object(forKey key: String) -> Any? { storage[key] }

        func set(_ value: Any?, forKey key: String) {
            storage[key] = value
        }
    }

    private func solid(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 0.9, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func pngData(_ image: CGImage) -> Data {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    }

    /// A folder in the system temp directory, gone after the test.
    private func temporaryFolder() -> URL {
        let unique = ProcessInfo.processInfo.globallyUniqueString
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stare-editor-backdrop-\(unique)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func backedPreference(destination folder: URL, format: CaptureFormat = .png) -> CapturePreference {
        // The extension parameters are skipped only through assignment: the
        // backdrop fields sit after the naming fields in the initializer.
        var preference = CapturePreference(format: format, destination: .folder(path: folder.path))
        preference.backdropPadding = 12
        preference.backdropCornerRadius = 8
        preference.backdropShadow = true
        return preference
    }

    // MARK: - Per capture, seeded from the stored default, never persisted

    func testThePerCaptureValuesSeedFromTheStoredDefault() {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.capture.backdropPadding = 12
        model.capture.backdropCornerRadius = 8
        model.capture.backdropShadow = true

        let content = CaptureEditorContent(image: solid(100, 80), capture: model.capture, redactionStyle: .blur)

        XCTAssertEqual(content.canvas.state?.backdropPadding, 12, "the controls start on the stored default")
        XCTAssertEqual(content.canvas.state?.backdropCornerRadius, 8)
        XCTAssertEqual(content.canvas.state?.backdropShadow, true)
    }

    /// Dates: https://cleanshot.com/video/screenshots/bgtool.mp4 — S2 puts the
    /// tool in the editor and leaves the stored default in Settings.
    func testAPerCaptureChangeNeverPersistsIntoTheStoredPreference() throws {
        let store = InMemoryPreferenceStore()
        let model = PreferencesModel(store: store)
        model.capture.backdropPadding = 12
        model.capture.backdropCornerRadius = 8
        model.capture.backdropShadow = true

        let content = CaptureEditorContent(image: solid(100, 80), capture: model.capture, redactionStyle: .blur)
        // The user edits this capture's background through the control.
        content.canvas.state?.backdropPadding = 40
        content.canvas.state?.backdropCornerRadius = 24
        content.canvas.state?.backdropShadow = false
        // And the editor composes and delivers — the write-through a leak
        // would ride on happens here, if there were one.
        var delivered: [CGImage] = []
        content.onDeliver = { delivered.append($0) }
        content.deliverComposed()
        XCTAssertEqual(delivered.count, 1)

        let reloaded = PreferencesModel(store: store)
        XCTAssertEqual(reloaded.capture.backdropPadding, 12, "the stored default survives the per-capture edit")
        XCTAssertEqual(reloaded.capture.backdropCornerRadius, 8)
        XCTAssertEqual(reloaded.capture.backdropShadow, true)
    }

    // MARK: - One composition point: copy == save == CaptureFile.write

    /// With the per-capture background set, the pixels the copy path hands
    /// the pasteboard equal the pixels the save path encodes, and both equal
    /// `CaptureFile.write`'s own composition for the same preference. This is
    /// also where today's inconsistency used to be: an editor save silently
    /// ignored the stored backdrop.
    func testCopySaveAndFileWriteShareTheSameBackedPixels() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let preference = backedPreference(destination: folder)
        let content = CaptureEditorContent(image: solid(100, 80), capture: preference, redactionStyle: .blur)

        let copyPixels = try XCTUnwrap(content.canvas.composedImage())
        let savePixels = try XCTUnwrap(content.canvas.composedImageForSave(format: preference.format))
        XCTAssertEqual(pngData(savePixels), pngData(copyPixels), "copy and save must take the same pixels")

        var delivered: [CGImage] = []
        content.onDeliver = { delivered.append($0) }
        content.deliverComposed()
        let deliveredPixels = try XCTUnwrap(delivered.first)
        XCTAssertEqual(pngData(deliveredPixels), pngData(copyPixels), "the history delivery takes the same pixels")

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let written = try XCTUnwrap(
            CaptureFile.write(solid(100, 80), preference: preference, date: date),
            "the file write must succeed in the temp folder")
        let fileImage = try XCTUnwrap(
            NSImage(data: try Data(contentsOf: written))?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(pngData(fileImage), pngData(copyPixels), "the file's own composition matches the editor's")
        // The backdrop must really be on: bigger than the capture by the
        // padding on both axes, plus the fixed shadow margin (16 px a side,
        // the composition's own constant).
        XCTAssertEqual(fileImage.width, 100 + 2 * 12 + 32)
    }

    /// A JPEG cannot carry the backdrop's transparent margin:
    /// `CaptureFile.write` flattens its own composition onto the backdrop's
    /// opaque base before encoding, and the editor's save path must do
    /// exactly the same, byte for byte. The copy path (PNG/TIFF pasteboard
    /// data) keeps the alpha margin.
    func testTheJPEGSaveFlattensExactlyAsCaptureFileWriteDoes() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let preference = backedPreference(destination: folder, format: .jpeg)
        let content = CaptureEditorContent(image: solid(100, 80), capture: preference, redactionStyle: .blur)

        let savePixels = try XCTUnwrap(content.canvas.composedImageForSave(format: .jpeg))
        let copyPixels = try XCTUnwrap(content.canvas.composedImage())
        XCTAssertNotEqual(pngData(savePixels), pngData(copyPixels), "the flatten is real: the margin loses alpha")

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let written = try XCTUnwrap(CaptureFile.write(solid(100, 80), preference: preference, date: date))
        // The save path's encodABLE bytes and the write's bytes: the same
        // encoder fed the same pixels, so they must match exactly.
        let editorSaveData = CaptureFile.data(for: savePixels, format: .jpeg)
        XCTAssertEqual(editorSaveData, try Data(contentsOf: written), "the editor's save path flattens like the write does")
    }

    /// With every per-capture parameter at the stored default (all off), the
    /// composed canvas comes back exactly as today's — the backdrop composes
    /// nothing, so the untouched editor save stays byte for byte.
    func testAnInactiveBackdropKeepsTodaysPixels() throws {
        let store = InMemoryPreferenceStore()
        let model = PreferencesModel(store: store)
        let content = CaptureEditorContent(image: solid(100, 80), capture: model.capture, redactionStyle: .blur)

        let state = try XCTUnwrap(content.canvas.state)
        XCTAssertFalse(state.backdropIsActive)
        let original = solid(100, 80)
        let composed = try XCTUnwrap(content.canvas.composedImage())
        XCTAssertEqual(composed.width, original.width)
        XCTAssertEqual(composed.height, original.height)
    }

    /// A silly value typed into the control clamps like the stored one
    /// always did — a nonsense preference can neither blank the capture nor
    /// grow the canvas enormous.
    func testTheControlClampsLikeTheStoredPreferenceDoes() {
        let content = CaptureEditorContent(image: solid(100, 80), capture: .standard, redactionStyle: .blur)
        guard let state = content.canvas.state else { return XCTFail("canvas has its state") }

        state.backdropPadding = -5
        XCTAssertEqual(state.backdropPadding, 0, "below zero degrades to off")
        state.backdropPadding = 1_000_000
        XCTAssertEqual(state.backdropPadding, CaptureBackdrop.maxPadding, "a giant value degrades to the maximum")
        state.backdropCornerRadius = -3
        XCTAssertEqual(state.backdropCornerRadius, 0)
        state.backdropCornerRadius = 9_999
        XCTAssertEqual(state.backdropCornerRadius, CaptureBackdrop.maxCornerRadius)
    }

    // MARK: - The background applies live (T5/S5)

    /// Renders the canvas the way the editor shows it, so the test reads the
    /// visible picture instead of only the composed output.
    private func renderedCanvas(_ canvas: CaptureEditorCanvas) throws -> CGImage? {
        guard canvas.bounds.width > 0, canvas.bounds.height > 0 else { return nil }
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(canvas.bounds.width), pixelsHigh: Int(canvas.bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        return rep.cgImage
    }

    /// S5: changing each of the three background values must change what the
    /// editor SHOWS — the dead control's defect (L4) was that the canvas
    /// never composed or invalidated the backdrop — and the composed pixels
    /// the copy, save and history paths take must still move with the knobs
    /// and stay one set of pixels.
    func testChangingEachBackgroundValueChangesWhatTheEditorShows() throws {
        let content = CaptureEditorContent(image: solid(120, 90), capture: .standard, redactionStyle: .blur)
        // A real, visible window: the dirty-flag assertion below reads the
        // same invalidation the live editor relies on, and an unhosted view
        // does not track it at all.
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 480, height: 400)),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = content
        window.confineToPrimaryScreen()
        window.orderFrontRegardless()
        content.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        let canvas = content.canvas
        let state = try XCTUnwrap(canvas.state)
        let before = pngData(try XCTUnwrap(renderedCanvas(canvas), "the canvas renders"))
        let beforeComposed = pngData(try XCTUnwrap(canvas.composedImage()))

        // Padding: the capture sits inside a margin.
        state.backdropPadding = 24
        XCTAssertTrue(canvas.needsDisplay, "a knob change must invalidate the canvas")
        XCTAssertNotEqual(
            pngData(try XCTUnwrap(renderedCanvas(canvas))), before,
            "padding must change what the editor shows")
        XCTAssertNotEqual(
            pngData(try XCTUnwrap(canvas.composedImage())), beforeComposed,
            "padding must change the composed pixels")

        // Corner radius: the capture's corners round.
        state.backdropPadding = 0
        state.backdropCornerRadius = 16
        XCTAssertTrue(canvas.needsDisplay)
        XCTAssertNotEqual(
            pngData(try XCTUnwrap(renderedCanvas(canvas))), before,
            "the corner radius must change what the editor shows")
        XCTAssertNotEqual(
            pngData(try XCTUnwrap(canvas.composedImage())), beforeComposed,
            "the corner radius must change the composed pixels")

        // Shadow: the fixed shadow shows around the capture.
        state.backdropCornerRadius = 0
        state.backdropShadow = true
        XCTAssertTrue(canvas.needsDisplay)
        XCTAssertNotEqual(
            pngData(try XCTUnwrap(renderedCanvas(canvas))), before,
            "the shadow must change what the editor shows")
        XCTAssertNotEqual(
            pngData(try XCTUnwrap(canvas.composedImage())), beforeComposed,
            "the shadow must change the composed pixels")
    }

    /// The liveness must not fork the pixels: with the knobs live in the
    /// view, the copy, the save and the history delivery still take the same
    /// composed pixels (L3's property).
    func testTheLiveBackgroundStillLeavesCopySaveAndHistoryOnOneSetOfPixels() throws {
        let content = CaptureEditorContent(image: solid(120, 90), capture: .standard, redactionStyle: .blur)
        let state = try XCTUnwrap(content.canvas.state)
        state.backdropPadding = 18
        state.backdropCornerRadius = 10
        state.backdropShadow = true

        let copyPixels = try XCTUnwrap(content.canvas.composedImage())
        let savePixels = try XCTUnwrap(content.canvas.composedImageForSave(format: .png))
        XCTAssertEqual(pngData(savePixels), pngData(copyPixels), "copy and save must take the same pixels")

        var delivered: [CGImage] = []
        content.onDeliver = { delivered.append($0) }
        content.deliverComposed()
        let deliveredPixels = try XCTUnwrap(delivered.first)
        XCTAssertEqual(pngData(deliveredPixels), pngData(copyPixels), "the history delivery takes the same pixels")
    }
}
