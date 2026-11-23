import XCTest
import CoreGraphics
@testable import Stare
import StareCore

/// S19 slice 3: ⌘V in the editor reads an image from the general pasteboard
/// and routes it through the same layer surface a drop uses —
/// `receiveCapture`, so the placement, the clamps, the crop-armed refusal
/// and the ONE journal are the drop's own rules, not a second path.
///
/// The rules under test:
///
/// - A paste lands centred in the visible canvas area — the display rect the
///   current space maps, viewport included — at the image's own pixel size,
///   clamped exactly like a dropped layer.
/// - A pasteboard carrying no image — text, a file URL, nothing — changes
///   nothing and journals no undo step.
/// - ⌘V matches the editor's existing ⌘ keys: it steals nothing from them
///   and stays silent while a text field has the focus.
/// - Each paste is one `.canvas` step: paste twice, undo twice, reverse order.
@MainActor
final class CaptureCanvasPasteTests: XCTestCase {

    private let canvasRect = CGRect(x: 0, y: 0, width: 300, height: 200)
    private let imageBounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    // MARK: - Fixtures (the drop tests' own vocabulary)

    private static func solidImage(
        _ colour: (CGFloat, CGFloat, CGFloat), width: Int, height: Int
    ) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: colour.0, green: colour.1, blue: colour.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private static let white = (CGFloat(1), CGFloat(1), CGFloat(1))
    private static let green = (CGFloat(0), CGFloat(1), CGFloat(0))
    private static let blue = (CGFloat(0), CGFloat(0), CGFloat(1))

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
            contentRect: CGRect(origin: .zero, size: CGSize(width: 300, height: 200)),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.confineToPrimaryScreen()
        window.contentView = canvas
        window.makeFirstResponder(canvas)
        return Editor(canvas: canvas, state: state, window: window)
    }

    private func pressKey(
        _ editor: Editor,
        keyCode: UInt16,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags
    ) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifierFlags,
            timestamp: 0, windowNumber: editor.window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode))
        editor.canvas.keyDown(with: event)
    }

    /// Puts `data` alone on the general pasteboard, the way a real clipboard
    /// arrives: cleared first, one declared type.
    private func putOnPasteboard(data: Data?, type: NSPasteboard.PasteboardType) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard let data else { return }
        pasteboard.declareTypes([type], owner: nil)
        pasteboard.setData(data, forType: type)
    }

    private func putImage(_ image: CGImage) {
        putOnPasteboard(
            data: NSBitmapImageRep(cgImage: image).tiffRepresentation, type: .tiff)
    }

    private func clearPasteboard() {
        NSPasteboard.general.clearContents()
    }

    override func tearDown() {
        clearPasteboard()
        super.tearDown()
    }

    /// The fit mapping of the whole 100×100 capture in the 300×200 canvas:
    /// display (50, 0, 200, 200), 0.5 px/pt.
    private var fit: CGRect {
        EditorCropSpace.fitted(coverage: imageBounds, inCanvas: canvasRect).display
    }

    private func space(of editor: Editor) -> EditorCropSpace {
        var coverage = imageBounds
        if !editor.state.isCropMarked, let region = editor.canvas.croppedRegion {
            coverage = region
        }
        return EditorCropSpace.fitted(
            coverage: coverage, viewport: editor.canvas.viewportState, inCanvas: canvasRect)
    }

    // MARK: - The paste lands centred and clamped (R1/R2)

    func testPasteCentresTheLayerInTheVisibleCanvasAreaClamped() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        clearPasteboard()
        putImage(Self.solidImage(Self.green, width: 40, height: 40))
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)

        XCTAssertEqual(editor.canvas.canvasLayers.count, 1, "⌘V with an image pastes one layer")
        let visible = space(of: editor)
        let centre = visible.pixelPoint(fromView: CGPoint(x: fit.midX, y: fit.midY))
        let placement = try XCTUnwrap(editor.canvas.canvasLayers.first).placement
        XCTAssertEqual(
            placement,
            CanvasComposition.clampedPlacement(
                CGRect(x: centre.x - 20, y: centre.y - 20, width: 40, height: 40),
                in: imageBounds),
            "the paste is centred in the VISIBLE canvas area and clamped like a drop")
        XCTAssertEqual(editor.canvas.selectedCanvasLayer?.id, editor.canvas.canvasLayers.first?.id,
            "the pasted layer takes the selection, like the drop does")
    }

    func testPasteCentresInTheVisibleAreaWhileZoomed() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        editor.canvas.applyZoom(3, anchoredAt: CGPoint(x: 150, y: 100))
        clearPasteboard()
        putImage(Self.solidImage(Self.green, width: 40, height: 40))
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)

        let visible = space(of: editor)
        let centre = visible.pixelPoint(fromView: CGPoint(
            x: visible.display.midX, y: visible.display.midY))
        let placement = try XCTUnwrap(editor.canvas.canvasLayers.first).placement
        XCTAssertEqual(
            placement,
            CanvasComposition.clampedPlacement(
                CGRect(x: centre.x - 20, y: centre.y - 20, width: 40, height: 40),
                in: imageBounds),
            "zoomed or not, the paste centres on what is visible right now")
    }

    func testAPasteTooBigForTheCanvasClampsLikeADrop() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        clearPasteboard()
        putImage(Self.solidImage(Self.green, width: 200, height: 200))
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)

        XCTAssertEqual(
            editor.canvas.canvasLayers.first?.placement,
            CanvasComposition.clampedPlacement(
                CGRect(x: -50, y: -50, width: 200, height: 200), in: imageBounds),
            "an oversized paste is clamped, never rejected — the drop's own answer")
    }

    // MARK: - Nothing pasted that is not an image (R3)

    func testPasteWithTextOnThePasteboardChangesNothingAndJournalsNothing() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        putImage(Self.solidImage(Self.green, width: 40, height: 40))
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)
        XCTAssertEqual(editor.canvas.canvasLayers.count, 1)

        putOnPasteboard(data: "just words".data(using: .utf8)!, type: .string)
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)
        XCTAssertEqual(editor.canvas.canvasLayers.count, 1, "a text-only pasteboard pastes nothing")

        try pressKey(editor, keyCode: 6, characters: "z", modifierFlags: [.command])
        XCTAssertEqual(editor.canvas.canvasLayers.count, 0,
            "the refusal left no undo step: ⌘Z pops the paste that preceded it, exactly one")
    }

    func testPasteWithAFileURLChangesNothingAndJournalsNothing() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        putImage(Self.solidImage(Self.green, width: 40, height: 40))
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)
        XCTAssertEqual(editor.canvas.canvasLayers.count, 1)

        let url = URL(fileURLWithPath: "/tmp/whatever.png")
        putOnPasteboard(
            data: try JSONEncoder().encode(url.absoluteString),
            type: .fileURL)
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)
        XCTAssertEqual(editor.canvas.canvasLayers.count, 1, "a file-URL pasteboard pastes nothing")

        try pressKey(editor, keyCode: 6, characters: "z", modifierFlags: [.command])
        XCTAssertEqual(editor.canvas.canvasLayers.count, 0,
            "the refusal left no undo step: ⌘Z pops the paste that preceded it, exactly one")
    }

    func testPasteWithAnEmptyPasteboardChangesNothingAndJournalsNothing() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        putImage(Self.solidImage(Self.green, width: 40, height: 40))
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)
        XCTAssertEqual(editor.canvas.canvasLayers.count, 1)

        clearPasteboard()
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)
        XCTAssertEqual(editor.canvas.canvasLayers.count, 1, "an empty pasteboard pastes nothing")

        try pressKey(editor, keyCode: 6, characters: "z", modifierFlags: [.command])
        XCTAssertEqual(editor.canvas.canvasLayers.count, 0,
            "the refusal left no undo step: ⌘Z pops the paste that preceded it, exactly one")
    }

    // MARK: - ⌘V matches the editor's own ⌘ keys (R4)

    func testPasteStaysSilentWhileATextFieldHasFocus() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        clearPasteboard()
        putImage(Self.solidImage(Self.green, width: 40, height: 40))
        let field = NSTextView(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        editor.window.contentView?.addSubview(field)
        editor.window.makeFirstResponder(field)
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)
        XCTAssertEqual(editor.canvas.canvasLayers.count, 0,
            "a text field owning the editor makes the paste its own business")
    }

    func testPasteDoesNotStealTheWindowsOtherCommandKeys() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        clearPasteboard()
        putImage(Self.solidImage(Self.green, width: 40, height: 40))

        editor.canvas.applyZoom(3, anchoredAt: CGPoint(x: 150, y: 100))
        XCTAssertNotEqual(editor.canvas.viewportState, .identity)
        try pressKey(editor, keyCode: 82, characters: "0", modifierFlags: .command)
        XCTAssertEqual(editor.canvas.viewportState, .identity, "⌘0 still resets the viewport")

        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)
        XCTAssertEqual(editor.canvas.canvasLayers.count, 1)
        try pressKey(editor, keyCode: 6, characters: "z", modifierFlags: [.command])
        XCTAssertEqual(editor.canvas.canvasLayers.count, 0, "⌘Z still undoes")
    }

    func testPasteIsRefusedWhileTheCropIsArmed() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        editor.state.selectCrop()
        clearPasteboard()
        putImage(Self.solidImage(Self.green, width: 40, height: 40))
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)
        XCTAssertEqual(editor.canvas.canvasLayers, [],
            "the armed crop owns the pointer: a paste adds nothing, as a drop does")
    }

    // MARK: - One undo step per paste, reverse order (R5)

    func testPasteTwiceUndoTwiceReversesTheOrder() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        clearPasteboard()
        putImage(Self.solidImage(Self.green, width: 40, height: 40))
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)
        let first = try XCTUnwrap(editor.canvas.canvasLayers.first)

        putImage(Self.solidImage(Self.blue, width: 40, height: 40))
        try pressKey(editor, keyCode: 9, characters: "v", modifierFlags: .command)
        let layers = editor.canvas.canvasLayers
        XCTAssertEqual(layers.count, 2, "the second paste stacks on top")
        XCTAssertEqual(layers.first?.id, first.id, "the first pasted layer stays below")

        try pressKey(editor, keyCode: 6, characters: "z", modifierFlags: [.command])
        XCTAssertEqual(editor.canvas.canvasLayers.ids(), [first.id],
            "⌘Z pops the newest paste first")
        try pressKey(editor, keyCode: 6, characters: "z", modifierFlags: [.command])
        XCTAssertEqual(editor.canvas.canvasLayers, [], "then the first one")
    }
}

private extension [CanvasLayer] {
    func ids() -> [UUID?] { map(\.id) }
}
