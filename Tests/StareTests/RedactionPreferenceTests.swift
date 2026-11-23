import AppKit
import CoreGraphics
import XCTest

@testable import Stare
import StareCore

/// T6b/S13 step 2: the redaction choice rides the one preferences blob into
/// every surface that draws a mark — the model mirrors it, EditorState keeps
/// its own mirror in step with the `laserLifetime` precedent (detached state
/// keeps today's blur), and the capture editor stamps the same choice on its
/// own marks. The overlay's live-preview arm (the line in `OverlayView`) is
/// the peer's file and lands separately; nothing here depends on it.
@MainActor
final class RedactionPreferenceTests: XCTestCase {
    /// In-memory store double, so persistence is tested without touching real
    /// `UserDefaults` (the same double the Settings tests keep privately).
    private final class InMemoryPreferenceStore: PreferenceStore {
        private var storage: [String: Any] = [:]

        func object(forKey key: String) -> Any? { storage[key] }

        func set(_ value: Any?, forKey key: String) {
            storage[key] = value
        }
    }

    // MARK: - Rule 2: the model mirrors the blob and writes through

    func testTheModelSeedsTheStyleFromThePersistedBlob() {
        let store = InMemoryPreferenceStore()
        var saved = AppPreferences.standard
        saved.redactionStyle = .randomizedPixelate
        saved.save(to: store)

        let model = PreferencesModel(store: store)
        XCTAssertEqual(model.redactionStyle, .randomizedPixelate)
    }

    func testWritingTheModelPersistsTheStyleAndTheRestOfTheBlob() {
        let store = InMemoryPreferenceStore()
        let model = PreferencesModel(store: store)
        model.capture.fileNamePrefix = "Kept"

        model.redactionStyle = .randomizedPixelate

        let reloaded = PreferencesModel(store: store)
        XCTAssertEqual(reloaded.redactionStyle, .randomizedPixelate)
        XCTAssertEqual(reloaded.capture.fileNamePrefix, "Kept", "the write-through persists the whole document, not a lone key")
    }

    // MARK: - Rule 3: EditorState mirrors the model; detached keeps today's

    func testAStateAttachedToTheModelMirrorsItsStyle() {
        let store = InMemoryPreferenceStore()
        var saved = AppPreferences.standard
        saved.redactionStyle = .randomizedPixelate
        saved.save(to: store)
        let model = PreferencesModel(store: store)

        let state = EditorState(preferences: model)
        XCTAssertEqual(state.redactionStyle, .randomizedPixelate)
    }

    func testAChangeOnTheModelReachesTheState() {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        let state = EditorState(preferences: model)

        model.redactionStyle = .randomizedPixelate

        XCTAssertEqual(state.redactionStyle, .randomizedPixelate)
    }

    func testAChangeOnTheStatePersistsThroughTheModel() {
        let store = InMemoryPreferenceStore()
        let model = PreferencesModel(store: store)
        let state = EditorState(preferences: model)

        state.redactionStyle = .randomizedPixelate

        XCTAssertEqual(model.redactionStyle, .randomizedPixelate)
        XCTAssertEqual(AppPreferences(store: store).redactionStyle, .randomizedPixelate)
    }

    /// The capture editor and the selftest harness never see the app's model:
    /// detached state keeps today's shipped blur in memory only.
    func testADetachedStateKeepsTodaysBlur() {
        XCTAssertEqual(EditorState().redactionStyle, .blur)
    }

    // MARK: - Rule 5: the editor's own mark creation follows the preference

    /// White with thin black vertical stripes: letter-stroke thin, so a blur
    /// patch and a pixelate patch over it read unambiguously differently.
    private static func stripedImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for stripe in stride(from: 10, to: 90, by: 12) {
            context.fill(CGRect(x: stripe, y: 0, width: 2, height: 100))
        }
        return context.makeImage()!
    }

    private func pngData(_ image: CGImage) -> Data {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    }

    /// Opens the editor the way a capture opens it — through the real
    /// `CaptureEditorContent` — drives a real blur-tool drag across its
    /// canvas, and returns what saving would produce.
    private func composed(with redactionStyle: RedactionStyle) throws -> CGImage {
        let content = CaptureEditorContent(
            image: Self.stripedImage(),
            capture: .standard,
            redactionStyle: redactionStyle)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: content.preferredSize),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = content
        window.confineToPrimaryScreen()
        content.layoutSubtreeIfNeeded()

        let canvas = content.canvas
        // The blur tool is what carries the redaction choice (S13): arm it
        // before the drag, the way the palette would.
        canvas.state?.tool = .blur
        // The canvas is flipped and sits at the content's bottom edge: a view
        // point maps to window coordinates as measured from the canvas frame.
        func windowPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: canvas.frame.minX + x, y: canvas.frame.maxY - y)
        }
        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
        }

        // A blur-tool drag across the middle of the fitted display, the same
        // gesture the drawing overlay would make. The fitted square is
        // centred, so a rect at the canvas's centre is always over the image.
        let inset = CanvasDrawingProbe.rect(bounds: canvas.bounds)
        canvas.mouseDown(with: try event(.leftMouseDown, at: windowPoint(inset.origin.x, inset.origin.y)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, at: windowPoint(inset.maxX, inset.maxY)))
        canvas.mouseUp(with: try event(.leftMouseUp, at: windowPoint(inset.maxX, inset.maxY)))

        return try XCTUnwrap(canvas.composedImage(), "the editor save composition failed")
    }

    func testTheEditorsOwnMarkCreationStampsThePreference() throws {
        let base = try XCTUnwrap(composedProbeOnly())
        let blurred = try composed(with: .blur)
        let pixelated = try composed(with: .randomizedPixelate)

        XCTAssertNotEqual(
            pngData(blurred), pngData(base),
            "the drag must have drawn a real mark")
        XCTAssertNotEqual(
            pngData(pixelated), pngData(base),
            "the drag must have drawn a real mark")
        XCTAssertNotEqual(
            pngData(pixelated), pngData(blurred),
            "the editor's own mark must save as the preference's redaction, never the blur twin")
    }

    /// The same content, never drawn on: what an untouched save produces.
    private func composedProbeOnly() throws -> CGImage {
        let content = CaptureEditorContent(
            image: Self.stripedImage(),
            capture: .standard,
            redactionStyle: .blur)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: content.preferredSize),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = content
        window.confineToPrimaryScreen()
        content.layoutSubtreeIfNeeded()
        return try XCTUnwrap(content.canvas.composedImage(), "the probe composition failed")
    }
}

/// A helper that locates a drawing rectangle that is safely inside the
/// editor's fitted display for any window size: the fitted square is centred,
/// so a rect at its centre is always over the image.
private enum CanvasDrawingProbe {
    static func rect(bounds: CGRect) -> CGRect {
        let span = min(bounds.width, bounds.height)
        let size = span / 4
        return CGRect(
            x: bounds.midX - size / 2,
            y: bounds.midY - size / 2,
            width: size,
            height: size)
    }
}
