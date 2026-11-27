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

    // MARK: - Round four S3: the blur paints on the LIVE canvas

    /// "en el editor 'b' no pinta pero en dibujo si funciona el pixelado" —
    /// the defect: the committed capture redacted, but the live canvas only
    /// stroked the mark's geometry (a 0-width hairline), never the patch. The
    /// drag below arms through the REAL `b` key route, mints through the same
    /// `DrawingSession` dispatch — the stamp the overlay and the compositor's
    /// shared `MarkRenderer.redactionPatch` render — and the pin reads the
    /// LIVE view: inside the mark the stripes are redacted. The committed
    /// captures above already pin the composed half.
    func testTheArmedBKeyPaintsTheRedactionPatchOnTheLiveCanvas() throws {
        let image = try XCTUnwrap(Self.stripedImage())
        let editor = Self.makeEditor(image: image)
        editor.state.redactionStyle = .blur

        editor.canvas.keyDown(with: try key(editor, characters: "b"))
        XCTAssertEqual(editor.state.tool, .blur, "the key armed the blur")
        try drawBlur(editor)
        let mark = try XCTUnwrap(editor.canvas.marks.first, "the drag minted through the shared session dispatch")
        XCTAssertEqual(mark.tool, .blur)

        // The drag spans canvas view points (90,60)–(210,140); the 100×100
        // fit in the 300×200 canvas is display (50,0,200,200), so the patch
        // covers source pixels x 20–80. Stripe 10–12 stays outside it as the
        // control; the gaussian twin's radius (15 pt of view) is far past the
        // stripes' 4-pt ink width, so no near-black pixel may survive inside.
        let rep = try XCTUnwrap(renderedLive(editor.canvas)) // canvas view points, 1:1
        let darkestInside = deepestLuma(rep, in: CGRect(x: 100, y: 70, width: 100, height: 60))
        let darkestOutside = deepestLuma(rep, in: CGRect(x: 55, y: 70, width: 30, height: 60))
        XCTAssertGreaterThan(
            darkestInside, 0.45,
            "inside the blurred mark the live stripes read as a redaction — the patch painted, or the defect stands")
        XCTAssertLessThan(
            darkestOutside, 0.35,
            "just outside the mark the raw surface keeps its black stripes — the blur redacts the mark, not the picture")
    }

    // MARK: - Round four S9: the live blur samples what the compositor samples

    /// S9 (verbatim): "he hecho algunos blur pero no todos salieron como
    /// esperaba, algunos parecen un rect de color que no tiene nisiquiera
    /// nada que ver con fondo donde esta haciendo blur. Pero algo
    /// interesante es que al guardarlo si funciona" (odd/tasks/round-four.md).
    ///
    /// Cause, in the LIVE half only, exactly where the report puts it: the
    /// compositor's `drawBlur` and the overlay's `drawBlur` hand
    /// `MarkRenderer.redactionPatch` (and so `BlurEffect.crop`) the mark's
    /// rect converted into the crop's own BOTTOM-LEFT-origin bitmap space —
    /// `y = image.height − maxY × scale` — which `BlurEffect.crop` documents
    /// and demands. The editor's live draw handed it the space's TOP-DOWN
    /// view mapping untouched, so the preview sampled the VERTICALLY
    /// MIRRORED strip; over this fixture — striped above, flat red below —
    /// that is the flat unrelated colour the owner's screenshots show. The
    /// saved file rides the real compositor and was already correct.

    /// 100×100: the top half striped white with thin black stripes, the
    /// bottom half solid red — two strips the mirroring swaps.
    private static func asymmetricFixture() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: 100, height: 100, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Bitmap coordinates, bottom-left origin: red is the visible BOTTOM
        // half, the stripes the visible TOP half.
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 50, width: 100, height: 50))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for stripe in stride(from: 10, to: 90, by: 10) {
            context.fill(CGRect(x: stripe, y: 50, width: 2, height: 50))
        }
        return context.makeImage()
    }

    private static func colour(_ rep: NSBitmapImageRep, x: Int, y: Int) -> NSColor? {
        rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    }

    /// A canvas at exactly ONE pixel per view point, so the live raster, the
    /// patch pixels and the compositor's output read on the same grid.
    private func makeOneToOneEditor(image: CGImage) -> (canvas: CaptureEditorCanvas, window: NSWindow) {
        let canvas = CaptureEditorCanvas(image: image)
        canvas.state = EditorState()
        canvas.state?.redactionStyle = .blur
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.confineToPrimaryScreen()
        window.contentView = canvas
        window.orderFrontRegardless()
        return (canvas, window)
    }

    /// The LIVE preview's patch matches the compositor's own output at the
    /// same scale inside the mark, and never reads the mirrored strip's flat
    /// red: the case the owner's screenshots show.
    func testTheLiveBlurOverAnAsymmetricSurfaceMatchesTheCompositorSOutput() throws {
        let image = try XCTUnwrap(Self.asymmetricFixture())
        let editor = makeOneToOneEditor(image: image)
        defer { editor.window.orderOut(nil) }
        // NSEvent's location is WINDOW base coordinates (bottom-left origin);
        // the mark's VIEW rect (30..70 × 8..38, y downward) is what the drag
        // below delivers: fully inside the striped top half. The correct
        // sample under it is the blur of the stripes; the mirrored strip the
        // bug reads is the flat red half.
        try drawDrag(
            editor.canvas, window: editor.window,
            from: CGPoint(x: 30, y: 92), to: CGPoint(x: 70, y: 42))
        let mark = try XCTUnwrap(editor.canvas.marks.first, "the drag minted the mark")
        XCTAssertEqual(mark.tool, .blur)
        XCTAssertEqual(mark.redactionStyle, .blur, "the blur twin is the case under test")

        let live = try renderedLive(editor.canvas)
        // The compositor's own output — the path the saved file takes, at
        // the same 1-px-per-point scale: the truth the owner reports correct.
        let composed = try XCTUnwrap(editor.canvas.composedImage(), "the save side composes")
        let composedRep = NSBitmapImageRep(cgImage: composed)

        var drifted: String = ""
        var reds: String = ""
        for x in stride(from: 34, to: 66, by: 4) {
            for y in stride(from: 14, to: 32, by: 4) {
                let a = try XCTUnwrap(Self.colour(live, x: x, y: y))
                let b = try XCTUnwrap(Self.colour(composedRep, x: x, y: y))
                if abs(a.redComponent - b.redComponent) > 0.06 ||
                    abs(a.greenComponent - b.greenComponent) > 0.06 ||
                    abs(a.blueComponent - b.blueComponent) > 0.06 {
                    drifted += "(\(x),\(y)) live=\(a) compositor=\(b); "
                }
                if a.redComponent - min(a.greenComponent, a.blueComponent) > 0.35 {
                    reds += "(\(x),\(y)) live=\(a); "
                }
            }
        }
        XCTAssertTrue(
            drifted.isEmpty,
            "S9: the live patch must match the compositor's own output at the same scale inside the mark — mismatches: \(drifted)")
        XCTAssertEqual(
            reds, "",
            "S9: the mirrored strip's flat colour must never be the live patch's sample — red pixels: \(reds)")
    }

    /// The same short mouse chain the committed tests drive: a blur drag
    /// from `from` to `to`, in canvas view points.
    private func drawDrag(_ canvas: CaptureEditorCanvas, window: NSWindow, from: CGPoint, to: CGPoint) throws {
        canvas.state?.tool = .blur
        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, at: from))
        canvas.mouseDragged(with: try event(.leftMouseDragged, at: to))
        canvas.mouseUp(with: try event(.leftMouseUp, at: to))
    }

    private func renderedLive(_ canvas: CaptureEditorCanvas) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(canvas.bounds.width),
            pixelsHigh: Int(canvas.bounds.height), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        return rep
    }

    /// The darkest luma (min rgb, the fixture is gray) inside `region`, in
    /// canvas view points.
    private func deepestLuma(_ rep: NSBitmapImageRep, in region: CGRect) -> CGFloat {
        var darkest: CGFloat? = nil
        for x in Int(region.minX)...Int(region.maxX) {
            for y in Int(region.minY)...Int(region.maxY) {
                guard x >= 0, x < rep.pixelsWide, y >= 0, y < rep.pixelsHigh,
                    let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else { continue }
                let luma = min(colour.redComponent, min(colour.greenComponent, colour.blueComponent))
                darkest = min(darkest ?? 1, luma)
            }
        }
        return darkest ?? 1
    }
}

/// In-memory `PreferenceStore` double (the same isolation the preference
/// tests keep).
private final class InMemoryBlurStore: PreferenceStore {
    private var storage: [String: Any] = [:]
    func object(forKey key: String) -> Any? { storage[key] }
    func set(_ value: Any?, forKey key: String) { storage[key] = value }
}
