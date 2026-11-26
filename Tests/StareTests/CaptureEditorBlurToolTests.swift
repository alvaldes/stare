import AppKit
import XCTest

@testable import Stare
import StareCore

/// S4: the capture editor's blur tool. Two halves:
/// - the key: `b` arms the blur wherever the focus is in the editor's
///   window — the canvas first, and the window's own route when a chrome
///   control holds the focus, so the key works like it does on the drawing
///   overlay where the canvas never loses the keyboard;
/// - the dispatch: the armed tool mints its mark through the same
///   `DrawingSession.begin` stamp every surface uses, so the mark redacts
///   with the state's own choice and renders through the one
///   `MarkRenderer.redactionPatch` dispatch (the mosaic here).
@MainActor
final class CaptureEditorBlurToolTests: XCTestCase {

    private let canvasRect = CGRect(x: 0, y: 0, width: 300, height: 200)
    private let imageBounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    // MARK: - Fixtures

    /// White with thin black vertical stripes, the fixture the redaction
    /// render pins draw their evidence against (letter-stroke thin, so a
    /// pixelate patch and its blur twin read unambiguously differently).
    private static func stripedImage() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: 100, height: 100, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for stripe in stride(from: 10, to: 90, by: 10) {
            context.fill(CGRect(x: stripe, y: 0, width: 2, height: 100))
        }
        return context.makeImage()
    }

    private struct Editor {
        let canvas: CaptureEditorCanvas
        let state: EditorState
        let window: NSWindow
    }

    private static func makeEditor(image: CGImage) -> Editor {
        let canvas = CaptureEditorCanvas(image: image)
        let state = EditorState()
        canvas.state = state
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas
        return Editor(canvas: canvas, state: state, window: window)
    }

    private func key(_ editor: Editor, characters: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: editor.window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: 0))
    }

    private struct WindowProbe { let window: CaptureEditorWindow; let state: EditorState }
    private func probeWindow(image: CGImage) -> WindowProbe {
        let window = CaptureEditorWindow(
            image: image, capture: .standard, redactionStyle: .blur,
            onDeliver: nil) { _ in }
        window.confineToPrimaryScreen()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        return WindowProbe(window: window, state: (window.contentView as! CaptureEditorContent).state)
    }

    private func tiff(_ image: CGImage) throws -> Data {
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).tiffRepresentation)
    }

    /// A blur-tool drag across the fit display's centre, driven through the
    /// real mouse chain.
    private func drawBlur(_ editor: Editor) throws {
        editor.state.tool = .blur
        let inset = CGRect(x: 90, y: 60, width: 120, height: 80)
        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: editor.window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
        }
        editor.canvas.mouseDown(with: try event(.leftMouseDown, at: inset.origin))
        editor.canvas.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: inset.maxX, y: inset.maxY)))
        editor.canvas.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: inset.maxX, y: inset.maxY)))
    }

    // MARK: - S4a: the key arms the blur, wherever the focus sits

    /// `b` on the canvas (the surface the open handler makes first
    /// responder) arms the blur; the states' own route — the same resolve
    /// everywhere else routes through — carries it.
    func testBOnTheCanvasArmsTheBlur() throws {
        let image = try XCTUnwrap(Self.stripedImage())
        let editor = Self.makeEditor(image: image)

        editor.canvas.keyDown(with: try key(editor, characters: "b"))

        XCTAssertEqual(editor.state.tool, .blur, "the canvas route must arm the blur")
    }

    /// `b` sent through the REAL window while the CANVAS does not own the
    /// focus — a state the editor sits in whenever a chrome control took it
    /// — still arms the blur. The window routes what the responder chain
    /// declined, exactly what the overlay's canvas never has to share.
    func testBThroughTheWindowArmsTheBlurWhenTheFocusIsNotOnTheCanvas() throws {
        let image = try XCTUnwrap(Self.stripedImage())
        let probe = probeWindow(image: image)
        let window = probe.window
        defer { window.orderOut(nil) }
        window.makeFirstResponder(window.contentView)  // not the canvas: the content itself

        window.sendEvent(try key(
            Editor(canvas: (window.contentView as! CaptureEditorContent).canvas,
                   state: probe.state, window: window),
            characters: "b"))

        XCTAssertEqual(probe.state.tool, .blur, "the window route must arm the blur from any non-canvas focus")
    }

    // MARK: - S4a: the armed tool mints through the same dispatch

    /// The blur drag commits a blur-tool mark carrying the state's own
    /// redaction choice, and the composed picture redacts under it — the
    /// pixelate choice paints the mosaic look, the blur choice its gaussian
    /// twin, through the one dispatch (`MarkRenderer.redactionPatch`, as
    /// every other surface's mark does).
    func testABlurDragMintsAMarkThatRedactsThroughTheStateSChoice() throws {
        let image = try XCTUnwrap(Self.stripedImage())
        let pixelateEditor = Self.makeEditor(image: image)
        pixelateEditor.state.redactionStyle = .randomizedPixelate
        try drawBlur(pixelateEditor)
        let pixelated = try XCTUnwrap(pixelateEditor.canvas.composedImage())

        let blurEditor = Self.makeEditor(image: image)
        blurEditor.state.redactionStyle = .blur
        try drawBlur(blurEditor)
        let blurred = try XCTUnwrap(blurEditor.canvas.composedImage())

        let mark = try XCTUnwrap(pixelateEditor.canvas.marks.first, "the blur drag must mint a mark")
        XCTAssertEqual(mark.tool, .blur)
        XCTAssertEqual(mark.redactionStyle, .randomizedPixelate, "the mark carries the state's choice from birth")
        XCTAssertNotEqual(
            try tiff(pixelated), try tiff(blurred),
            "the mosaic and the gaussian twin must render differently through the one dispatch")
        let cleanTiff = try tiff(try XCTUnwrap(Self.makeEditor(image: image).canvas.composedImage()))
        XCTAssertNotEqual(try tiff(pixelated), cleanTiff, "and the mark must actually redact over the stripes")
    }

    // MARK: - S4b: the stored blur preference decodes to pixelate now

    /// The reversal (S4): a stored `redactionStyle: "blur"` blob — the
    /// owner's own pre-default document — decodes as the shipped pixelate,
    /// so the app he runs presents the pixelated look he asked for instead
    /// of honouring an old default he never picked. The mark minted from
    /// that migrated choice renders as a mosaic, never the blur twin.
    func testAStoredBlurPreferenceDecodesToPixelateAndItsMarkRendersAsAMosaic() throws {
        let store = InMemoryBlurStore()
        store.set(Data(#"{"redactionStyle":"blur"}"#.utf8), forKey: AppPreferences.storageKey)

        let migrated = AppPreferences(store: store)
        XCTAssertEqual(
            migrated.redactionStyle, .randomizedPixelate,
            "a stored blur must decode to the shipped pixelate now (S4's deliberate reversal)")

        // The model mirror and the state the surfaces stamp from carry it.
        let model = PreferencesModel(store: store)
        XCTAssertEqual(model.redactionStyle, .randomizedPixelate)
        let state = EditorState(preferences: model)
        XCTAssertEqual(state.redactionStyle, .randomizedPixelate)

        // And a mark minted from that state redacts as a mosaic.
        let image = try XCTUnwrap(Self.stripedImage())
        let editor = Self.makeEditor(image: image)
        editor.state.redactionStyle = state.redactionStyle
        try drawBlur(editor)
        let mosaic = try XCTUnwrap(editor.canvas.composedImage())

        let blurEditor = Self.makeEditor(image: image)
        blurEditor.state.redactionStyle = .blur
        try drawBlur(blurEditor)
        let blurred = try XCTUnwrap(blurEditor.canvas.composedImage())
        XCTAssertNotEqual(
            try tiff(mosaic), try tiff(blurred),
            "the mark from the migrated preference must render as a mosaic, never the blur twin")
    }
}

/// In-memory `PreferenceStore` double (the same isolation the preference
/// tests keep).
private final class InMemoryBlurStore: PreferenceStore {
    private var storage: [String: Any] = [:]
    func object(forKey key: String) -> Any? { storage[key] }
    func set(_ value: Any?, forKey key: String) { storage[key] = value }
}
