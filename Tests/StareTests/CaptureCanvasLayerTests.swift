import XCTest
import CoreGraphics
@testable import Stare
import StareCore

/// S19 slice 2: the canvas is componible in the editor — a capture dropped on
/// the window (the route that exists today: AppKit drag-and-drop; the app has
/// no capture-history store and clipboard paste is slice 3) becomes a
/// `CanvasLayer` of the canvas' `CanvasComposition`, and the user can move,
/// resize, delete and restack it, with every step reversable through the ONE
/// journal ⌘Z already pops from.
///
/// The rules under test:
///
/// - A layer's placement lives in the capture's pixel space and rides the
///   existing `EditorCropSpace`/`EditorViewport` mapping to the view, so a
///   drag hits where the pointer is at any zoom or pan — no second mapping.
/// - The gestures claim with ⌥ held: drag to move, drag a grip to resize
///   (the model clamps), ⌥-click selects. Keys ⌫, `[`, `]` — none of them a
///   tool key — delete and restack the selection.
/// - `composedImage()` flattens through `CanvasComposition.flattened()`, so
///   what is previewed is what is saved — and with no layers the base image
///   is still the identity.
///
/// The tests drive the real canvas the way the zoom and eraser tests do —
/// synthesized mouse and key events through `CaptureEditor`'s canvas — and
/// judge through `composedImage()`, the public interface Save and Copy use.
@MainActor
final class CaptureCanvasLayerTests: XCTestCase {

    private let canvasRect = CGRect(x: 0, y: 0, width: 300, height: 200)
    private let imageBounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    // MARK: - Fixtures

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
    private static let red = (CGFloat(1), CGFloat(0), CGFloat(0))
    private static let green = (CGFloat(0), CGFloat(1), CGFloat(0))
    private static let blue = (CGFloat(0), CGFloat(0), CGFloat(1))

    private struct RGB: Equatable {
        let r: UInt8, g: UInt8, b: UInt8
        static let white = RGB(r: 255, g: 255, b: 255)
        static let red = RGB(r: 255, g: 0, b: 0)
        static let green = RGB(r: 0, g: 255, b: 0)
        static let blue = RGB(r: 0, g: 0, b: 255)
    }

    /// Top-left origin reader, the convention `CanvasCompositionTests`
    /// documents: the first row of the byte buffer is the image's top row.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> RGB {
        let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        let data = UnsafeBufferPointer(
            start: context.data!.assumingMemoryBound(to: UInt8.self),
            count: image.width * image.height * 4)
        let base = (y * image.width + x) * 4
        return RGB(r: data[base], g: data[base + 1], b: data[base + 2])
    }

    /// The colour the pipeline itself renders a swatch into, so assertions
    /// pin position and rendered colour, not colour-management byte trivia —
    /// the same reader convention `CanvasCompositionTests` documents.
    private func reference(_ colour: (CGFloat, CGFloat, CGFloat)) -> RGB {
        pixel(Self.solidImage(colour, width: 8, height: 8), x: 4, y: 4)
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
            contentRect: CGRect(origin: .zero, size: CGSize(width: 300, height: 200)),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.confineToPrimaryScreen()
        window.contentView = canvas
        return Editor(canvas: canvas, state: state, window: window)
    }

    /// A synthesized event for a VIEW point: the canvas reads
    /// `convert(event.locationInWindow, from: nil)`, and the flipped view
    /// turns a window location's y upside down — so the location that hits
    /// view (x, y) is (x, canvas height − y). Every call site below names
    /// view points, top-down, the coordinates the mapping speaks.
    private func event(
        _ type: NSEvent.EventType, at point: CGPoint, window: NSWindow,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type, location: CGPoint(x: point.x, y: canvasRect.height - point.y),
            modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1)
    }

    private func down(
        _ editor: Editor, at point: CGPoint, option: Bool = false
    ) throws {
        editor.canvas.mouseDown(with: try XCTUnwrap(
            event(.leftMouseDown, at: point, window: editor.window,
                  modifiers: option ? [.option] : [])))
    }

    private func dragged(_ editor: Editor, to point: CGPoint) throws {
        editor.canvas.mouseDragged(with: try XCTUnwrap(
            event(.leftMouseDragged, at: point, window: editor.window)))
    }

    private func up(_ editor: Editor, at point: CGPoint) throws {
        editor.canvas.mouseUp(with: try XCTUnwrap(
            event(.leftMouseUp, at: point, window: editor.window)))
    }

    /// A ⌥ press: drag with ⌥ held on the press, plain afterwards (the
    /// editor reads the modifier off the mouse-down event only).
    private func optionDrag(_ editor: Editor, from start: CGPoint, to end: CGPoint) throws {
        try down(editor, at: start, option: true)
        try dragged(editor, to: end)
        try up(editor, at: end)
    }

    private func pressKey(
        _ editor: Editor,
        keyCode: UInt16,
        characters: String,
        ignoring: String,
        modifiers: NSEvent.ModifierFlags = []
    ) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: editor.window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: ignoring,
            isARepeat: false, keyCode: keyCode))
        editor.canvas.keyDown(with: event)
    }

    /// The fit mapping of the whole 100×100 capture in the 300×200 canvas:
    /// display (100, 50, 200, 200), 0.5 px/pt.
    private var fit: CGRect {
        EditorCropSpace.fitted(coverage: imageBounds, inCanvas: canvasRect).display
    }

    /// The editor's whole-pixel coverage, recomputed with the live viewport —
    /// the same one mapping the canvas reads, never a parallel one.
    private func space(of editor: Editor) -> EditorCropSpace {
        var coverage = imageBounds
        if !editor.state.isCropMarked, let region = editor.canvas.croppedRegion {
            coverage = region
        }
        return EditorCropSpace.fitted(
            coverage: coverage, viewport: editor.canvas.viewportState, inCanvas: canvasRect)
    }

    /// A 40×40 green capture placed centred on a view point through the
    /// editor's own route, at the image's native pixel size.
    private func dropSquare(
        _ editor: Editor, green: CGImage, atView point: CGPoint
    ) throws -> CanvasLayer {
        try XCTUnwrap(editor.canvas.receiveCapture(green, atView: point))
    }

    // MARK: - The composition rides the one mapping (R1)

    func testALayerDragHitsWhereThePointerIsAtZoom() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        let layer = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 150, y: 100))
        editor.canvas.applyZoom(3, anchoredAt: CGPoint(x: 150, y: 100))
        let zoomed = space(of: editor)

        // Drag from a point inside the layer to another view point; the
        // placement must land exactly where the pointer's pixels say,
        // through the zoomed space the canvas reads — the same
        // clampedPlacement the model answers. The fixture: the fit display is
        // (50, 0, 200, 200) at 0.5 px/pt, so the drop at (150, 100) landed
        // pixel (50, 50) and the layer is (30, 30, 40, 40); zoom 3 anchored
        // at (150, 100) keeps pixel (50, 50) there (view(p) = (150, 100) +
        // (p − (50, 50)) · 6 inside the clamped zoom).
        XCTAssertEqual(zoomed.pixelPoint(fromView: CGPoint(x: 150, y: 100)), CGPoint(x: 50, y: 50))
        let start = zoomed.viewPoint(fromPixel: CGPoint(x: 50, y: 60)) // inside the layer
        let end = CGPoint(x: 210, y: 100) // pixel (60, 50): +10, −10 px
        try optionDrag(editor, from: start, to: end)
        let grab = zoomed.pixelPoint(fromView: start)
        let destination = zoomed.pixelPoint(fromView: end)
        XCTAssertEqual(destination.x - grab.x, 10, accuracy: 0.01, "the pointer's pixel delta is the zoomed space's answer")
        XCTAssertEqual(destination.y - grab.y, -10, accuracy: 0.01)
        let expected = CanvasComposition.clampedPlacement(
            layer.placement.placementShifted(from: grab, to: destination), in: imageBounds)
        XCTAssertEqual(editor.canvas.canvasLayers.first?.placement, expected,
            "the drag must land the layer where the pointer's pixels say at this zoom")
    }

    func testALayerDragHitsWhereThePointerIsWhenPanned() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        let layer = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 150, y: 100))
        editor.canvas.pan(byPointerDelta: CGSize(width: 30, height: -20))
        let panned = space(of: editor)
        // The pan slides the fit's x axis to (80, 0) and pins the covered y;
        // the scale is unchanged, so pixel (50, 60) shows at (180, 120).
        let start = panned.viewPoint(fromPixel: CGPoint(x: 50, y: 60))
        XCTAssertEqual(start, CGPoint(x: 180, y: 120))
        let end = CGPoint(x: 140, y: 160) // pixel (40, 70): −20, +10 px
        try optionDrag(editor, from: start, to: end)
        let expected = CanvasComposition.clampedPlacement(
            layer.placement.offsetBy(
                dx: panned.pixelPoint(fromView: end).x - panned.pixelPoint(fromView: start).x,
                dy: panned.pixelPoint(fromView: end).y - panned.pixelPoint(fromView: start).y),
            in: imageBounds)
        XCTAssertEqual(editor.canvas.canvasLayers.first?.placement, expected,
            "the drag must land the layer where the pointer's pixels say at this pan")
    }

    // MARK: - Add, resize, delete, restack (R2) — the route and the keys

    func testAReceivedCaptureBecomesAClampedLayerAtTheDropPoint() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        let layer = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 150, y: 100))
        XCTAssertEqual(editor.canvas.canvasLayers, [layer])
        // The drop point maps to pixel (50, 50) (fit display (50, 0, 200, 200)
        // at 0.5 px/pt); a 40×40 image centred on it is (30, 30, 40, 40),
        // wholly inside the canvas — the clamp's own answer for this input.
        XCTAssertEqual(layer.placement, CanvasComposition.clampedPlacement(
            CGRect(x: 30, y: 30, width: 40, height: 40), in: imageBounds))
        XCTAssertFalse(layer.placement.isNull)
        XCTAssertEqual(editor.canvas.selectedCanvasLayer?.id, layer.id,
            "the capture that just arrived takes the selection, so the keys act on it")

        // A layer too big for the canvas is clamped, never rejected: a
        // 200×200 neighbour image lands at the model's own clamped answer.
        let big = try dropSquare(
            editor, green: Self.solidImage(Self.blue, width: 200, height: 200),
            atView: CGPoint(x: 150, y: 100))
        XCTAssertEqual(big.placement, CanvasComposition.clampedPlacement(
            CGRect(x: -50, y: -50, width: 200, height: 200), in: imageBounds),
            "a centred request larger than the canvas is clamped, not rejected")
    }

    func testADropIsRefusedWhileTheCropIsArmed() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        editor.state.selectCrop()
        let layer = editor.canvas.receiveCapture(
            Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 150, y: 100))
        XCTAssertNil(layer, "the armed crop owns the pointer: a drop adds nothing")
        XCTAssertEqual(editor.canvas.canvasLayers, [])
    }

    func testALayerResizesWithinTheModelClamps() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        let layer = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 150, y: 100))
        // The layer's top-left corner in view points (pixel (30, 30) shows at
        // (110, 60)), grabbed with ⌥ held and dragged inward past the halfway
        // point: the resize is `place`'s business — the crop rule's gather
        // then the model's own clamps answer, exactly the pure function's value
        // (a 10 px arc floored at the 16 px grab side).
        let corner = space(of: editor).viewPoint(fromPixel: CGPoint(x: 30, y: 30))
        XCTAssertEqual(corner, CGPoint(x: 110, y: 60))
        let end = CGPoint(x: 170, y: 120) // pixel (60, 60)
        try optionDrag(editor, from: corner, to: end)
        let pointer = space(of: editor).pixelPoint(fromView: end)
        let resized = EditorCropRule.region(
            from: layer.placement, dragging: .topLeft, to: pointer, in: imageBounds)
        XCTAssertEqual(
            editor.canvas.canvasLayers.first?.placement,
            CanvasComposition.clampedPlacement(resized, in: imageBounds),
            "the resize lands inside the model's clamps — never inverted, never below a grabbable side")
        let final = editor.canvas.canvasLayers.first!.placement
        XCTAssertEqual(final.width, CanvasComposition.minimumGrabSide,
            "a resize squeezed past halfway stays at the grab floor")
        XCTAssertEqual(final.height, CanvasComposition.minimumGrabSide)
        XCTAssertTrue(imageBounds.contains(final), "the shrunken layer never leaves the canvas")
    }

    func testDeleteRemovesTheSelectedLayer() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        let first = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 130, y: 90))
        _ = try dropSquare(
            editor, green: Self.solidImage(Self.blue, width: 40, height: 40),
            atView: CGPoint(x: 180, y: 130))
        // ⌥-click the second layer's interior (the drop at (180, 130) landed
        // it on pixels 45–85), then ⌫.
        try down(editor, at: space(of: editor).viewPoint(fromPixel: CGPoint(x: 55, y: 55)), option: true)
        try up(editor, at: space(of: editor).viewPoint(fromPixel: CGPoint(x: 55, y: 55)))
        try pressKey(editor, keyCode: 51, characters: "\u{7F}", ignoring: "\u{7F}")
        XCTAssertEqual(editor.canvas.canvasLayers.map(\.id), [first.id], "exactly the selected layer leaves")
        XCTAssertNil(editor.canvas.selectedCanvasLayer)

        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(pixel(composed, x: 30, y: 45), reference(Self.green), "the survivor keeps its pixels")
        XCTAssertEqual(pixel(composed, x: 70, y: 70), reference(Self.white), "the removed layer paints nothing")
    }

    func testBracketKeysRestackTheSelectedLayer() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        let first = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 130, y: 90))
        let second = try dropSquare(
            editor, green: Self.solidImage(Self.blue, width: 40, height: 40),
            atView: CGPoint(x: 150, y: 100))
        XCTAssertEqual(editor.canvas.canvasLayers.map(\.id), [first.id, second.id], "a new capture lands on top")

        // The selection sits on `second` (it took it at the drop). `]` keeps
        // it on top — a clamped reorder; `[` sends it back one.
        try pressKey(editor, keyCode: 30, characters: "]", ignoring: "]")
        XCTAssertEqual(editor.canvas.canvasLayers.map(\.id), [first.id, second.id])
        try pressKey(editor, keyCode: 33, characters: "[", ignoring: "[")
        XCTAssertEqual(editor.canvas.canvasLayers.map(\.id), [second.id, first.id], "`[` sends the selection back")
        try pressKey(editor, keyCode: 33, characters: "[", ignoring: "[")
        XCTAssertEqual(editor.canvas.canvasLayers.map(\.id), [second.id, first.id],
            "the bottom is the clamp — nothing further to move")

        // Restacking is observable in the flattened pixels: the blue layer
        // now draws first, so the green covers their overlap and the blue
        // keeps its claim only where the green does not reach.
        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(pixel(composed, x: 35, y: 35), reference(Self.green))
        XCTAssertEqual(pixel(composed, x: 65, y: 35), reference(Self.blue))
    }

    // MARK: - What is previewed is what saves (R3)

    func testComposedImageFlattensTheLayersThroughTheComposition() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.red, width: 100, height: 100))
        _ = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 150, y: 100))
        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(composed.width, 100, "a layer never enlarges the save")
        XCTAssertEqual(composed.height, 100)
        // The drop's placement (30, 30, 40, 40) — the saved pixels answer.
        XCTAssertEqual(pixel(composed, x: 50, y: 50), reference(Self.green), "the layer's colour where it covers")
        XCTAssertEqual(pixel(composed, x: 20, y: 20), reference(Self.red), "the base's colour where it does not")
    }

    func testALayerSavesIntoTheCroppedRegionOnly() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        editor.state.selectCrop()
        try down(editor, at: CGPoint(x: 100, y: 50))
        try dragged(editor, to: CGPoint(x: 200, y: 150))
        try up(editor, at: CGPoint(x: 200, y: 150))
        try pressKey(editor, keyCode: 36, characters: "\r", ignoring: "\r")
        XCTAssertEqual(try XCTUnwrap(editor.canvas.composedImage()).width, 50, "the region (25,25,50,50) applied")

        _ = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 130, y: 80))
        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(composed.width, 50, "the crop, not the layer, sets the composed size")
        XCTAssertEqual(pixel(composed, x: 25, y: 25), reference(Self.green), "the layer lands at its absolute pixel inside the region")
        XCTAssertEqual(pixel(composed, x: 2, y: 47), reference(Self.white), "the base's colour where the layer does not reach")
    }

    func testWithNoLayersTheSaveIsStillToday() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        let mark = Stroke(tool: .pen, ink: .red, points: [CGPoint(x: 60, y: 60), CGPoint(x: 66, y: 60)])
        editor.canvas.seedMarks([mark])
        let pristine = try XCTUnwrap(editor.canvas.composedImage())

        // A capture dropped and undone again must leave the save byte-identical
        // to the no-layer state — the identity slice 1 pinned, riding the editor.
        _ = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 150, y: 100))
        try pressKey(editor, keyCode: 6, characters: "z", ignoring: "z", modifiers: .command)
        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(
            NSBitmapImageRep(cgImage: composed).tiffRepresentation,
            NSBitmapImageRep(cgImage: pristine).tiffRepresentation,
            "no layers means today's image, byte for byte")
    }

    // MARK: - The ONE journal covers the canvas (R4)

    func testUndoRemovesAReceivedCaptureThroughTheSharedJournal() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        let mark = Stroke(tool: .pen, ink: .red, points: [CGPoint(x: 60, y: 60), CGPoint(x: 66, y: 60)])
        editor.canvas.seedMarks([mark])
        let pristine = try XCTUnwrap(editor.canvas.composedImage())

        _ = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 150, y: 100))
        try pressKey(editor, keyCode: 6, characters: "z", ignoring: "z", modifiers: .command)
        XCTAssertEqual(editor.canvas.canvasLayers, [], "⌘Z undoes the drop")
        try pressKey(editor, keyCode: 6, characters: "z", ignoring: "z", modifiers: .command)
        XCTAssertNil(editor.canvas.selectedCanvasLayer, "the undone layer's selection goes with it")
        editor.canvas.redo()
        XCTAssertEqual(editor.canvas.canvasLayers.count, 1, "redo brings the capture back")
        try pressKey(editor, keyCode: 6, characters: "z", ignoring: "z", modifiers: .command)

        try pressKey(editor, keyCode: 6, characters: "z", ignoring: "z", modifiers: .command)
        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(
            NSBitmapImageRep(cgImage: composed).tiffRepresentation,
            NSBitmapImageRep(cgImage: pristine).tiffRepresentation,
            "after undoing everything the saved pixels are the pristine ones")
    }

    func testUndoRestoresADraggedLayerPlacementAndItsOrder() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        _ = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 150, y: 100))
        let before = editor.canvas.canvasLayers
        try optionDrag(editor, from: CGPoint(x: 150, y: 100), to: CGPoint(x: 200, y: 140))
        XCTAssertNotEqual(editor.canvas.canvasLayers, before, "the drag moved the layer")

        try pressKey(editor, keyCode: 6, characters: "z", ignoring: "z", modifiers: .command)
        XCTAssertEqual(editor.canvas.canvasLayers, before, "⌘Z restores the placement")
        editor.canvas.redo()
        XCTAssertNotEqual(editor.canvas.canvasLayers, before, "redo reapplies the move")
    }

    func testTheJournalPopsCanvasAndMarkStepsInRealOrder() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        _ = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 150, y: 100))
        let withLayer = try XCTUnwrap(editor.canvas.composedImage())
        editor.state.tool = .pen
        try down(editor, at: CGPoint(x: 60, y: 60))
        try dragged(editor, to: CGPoint(x: 66, y: 60))
        try up(editor, at: CGPoint(x: 66, y: 60))
        let withMark = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertNotEqual(
            NSBitmapImageRep(cgImage: withLayer).tiffRepresentation,
            NSBitmapImageRep(cgImage: withMark).tiffRepresentation)

        try pressKey(editor, keyCode: 6, characters: "z", ignoring: "z", modifiers: .command)
        XCTAssertEqual(
            NSBitmapImageRep(cgImage: try XCTUnwrap(editor.canvas.composedImage())).tiffRepresentation,
            NSBitmapImageRep(cgImage: withLayer).tiffRepresentation,
            "⌘Z pops the newest step first — the mark, not the layer")
        try pressKey(editor, keyCode: 6, characters: "z", ignoring: "z", modifiers: .command)
        XCTAssertEqual(editor.canvas.canvasLayers, [], "then the canvas step")
    }

    func testCropUndoKeepsWorkingWhileCanvasStepsShareTheJournal() throws {
        let editor = Self.makeEditor(image: Self.solidImage(Self.white, width: 100, height: 100))
        editor.state.selectCrop()
        try down(editor, at: CGPoint(x: 100, y: 62.5))
        try dragged(editor, to: CGPoint(x: 200, y: 137.5))
        try up(editor, at: CGPoint(x: 200, y: 137.5))
        try pressKey(editor, keyCode: 36, characters: "\r", ignoring: "\r")
        XCTAssertEqual(try XCTUnwrap(editor.canvas.composedImage()).width, 50)

        _ = try dropSquare(
            editor, green: Self.solidImage(Self.green, width: 40, height: 40),
            atView: CGPoint(x: 150, y: 100))
        try pressKey(editor, keyCode: 6, characters: "z", ignoring: "z", modifiers: .command)
        XCTAssertEqual(editor.canvas.canvasLayers, [], "⌘Z pops the canvas step and keeps the crop")
        XCTAssertEqual(try XCTUnwrap(editor.canvas.composedImage()).width, 50)
        try pressKey(editor, keyCode: 6, characters: "z", ignoring: "z", modifiers: .command)
        XCTAssertEqual(try XCTUnwrap(editor.canvas.composedImage()).width, 100,
            "⌘Z then pops the crop, in the order they happened")
    }
}

/// The placement shift one drag spans, expressed where the model reads it.
private extension CGRect {
    func placementShifted(from grab: CGPoint, to destination: CGPoint) -> CGRect {
        offsetBy(dx: destination.x - grab.x, dy: destination.y - grab.y)
    }
}
