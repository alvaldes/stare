import XCTest
import CoreGraphics
@testable import Stare
import StareCore

/// The capture editor's eraser. The defect it pins: the canvas never routed
/// the eraser to `DrawingSession.erase`, so an eraser drag committed an
/// invisible no-op stroke — the user erased over a mark and nothing was
/// deleted (pre-existing, found during T9; T9 did not cause it). The tests
/// drive the real canvas the way the zoom tests do — synthesized mouse and
/// key events through `CaptureEditorCanvas` — and judge through
/// `composedImage()`, the public interface Save and Copy go through.
@MainActor
final class CaptureEditorEraserTests: XCTestCase {

    private let canvasRect = CGRect(x: 0, y: 0, width: 300, height: 200)
    private let imageBounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    // MARK: - Fixtures

    private static func solidImage(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
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
        XCTAssertEqual(canvas.bounds.size, CGSize(width: 300, height: 200))
        return Editor(canvas: canvas, state: state, window: window)
    }

    private func event(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1)
    }

    private func down(_ editor: Editor, at point: CGPoint) throws {
        editor.canvas.mouseDown(with: try XCTUnwrap(
            event(.leftMouseDown, at: point, window: editor.window)))
    }

    private func dragged(_ editor: Editor, to point: CGPoint) throws {
        editor.canvas.mouseDragged(with: try XCTUnwrap(
            event(.leftMouseDragged, at: point, window: editor.window)))
    }

    private func up(_ editor: Editor, at point: CGPoint) throws {
        editor.canvas.mouseUp(with: try XCTUnwrap(
            event(.leftMouseUp, at: point, window: editor.window)))
    }

    private func drag(_ editor: Editor, from start: CGPoint, to end: CGPoint) throws {
        try down(editor, at: start)
        try dragged(editor, to: end)
        try up(editor, at: end)
    }

    private func pressKey(
        _ editor: Editor, keyCode: Int, characters: String, ignoring: String, modifiers: NSEvent.ModifierFlags = []
    ) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: editor.window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: ignoring,
            isARepeat: false, keyCode: UInt16(keyCode)))
        editor.canvas.keyDown(with: event)
    }


    /// The composed pixels of a fresh editor over `image` — the fixture's
    /// "no marks" reference.
    private func cleanTiff(image: CGImage) throws -> Data {
        let composed = try XCTUnwrap(Self.makeEditor(image: image).canvas.composedImage())
        return try XCTUnwrap(tiff(composed))
    }

    private func tiff(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).tiffRepresentation
    }

    /// Whether any pixel of the composed image is not pure white — the
    /// presence of pen ink, measured the same way the sibling editor tests
    /// measure it.
    private func hasInk(_ image: CGImage) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if colour.redComponent < 0.92 || colour.greenComponent < 0.92 || colour.blueComponent < 0.92 {
                    return true
                }
            }
        }
        return false
    }

    /// One straight pen drag with the tool already in hand (the editor
    /// state's default), from fit-view `start` to `end`.
    private func drawPen(_ editor: Editor, from start: CGPoint, to end: CGPoint) throws {
        editor.state.tool = .pen
        try drag(editor, from: start, to: end)
    }

    /// One eraser drag over the fit-view path `start` → `end`.
    private func erase(_ editor: Editor, over start: CGPoint, to end: CGPoint) throws {
        editor.state.tool = .eraser
        try drag(editor, from: start, to: end)
    }

    /// The fit mapping of the whole 100×100 capture in the 300×200 canvas,
    /// with the canvas's current viewport composed on top — the same mapping
    /// the canvas draws, hit-tests and saves through.
    private func space(of editor: Editor) -> EditorCropSpace {
        EditorCropSpace.fitted(
            coverage: imageBounds, viewport: editor.canvas.viewportState, inCanvas: canvasRect)
    }

    /// The mapping for the fit itself (viewport identity), for reference
    /// editors that stand at the fit.
    private var fitSpace: EditorCropSpace {
        EditorCropSpace.fitted(coverage: imageBounds, viewport: .identity, inCanvas: canvasRect)
    }

    // The fit display of a 100×100 capture in the 300×200 canvas is
    // (50, 0, 200, 200), so fit-view point `p` maps to image pixel
    // `(p.x - 50, p.y) / 2`. The pen drags below sit on that arithmetic.

    /// The centre mark: fit-view (150, 100) → (160, 100), pixels (50, 50) → (55, 50).
    private let centreStart = CGPoint(x: 150, y: 100)
    private let centreEnd = CGPoint(x: 160, y: 100)
    /// The left mark: pixels (25, 50) → (31, 50).
    private let leftStart = CGPoint(x: 100, y: 100)
    private let leftEnd = CGPoint(x: 112, y: 100)
    /// The right mark: pixels (69, 50) → (75, 50).
    private let rightStart = CGPoint(x: 188, y: 100)
    private let rightEnd = CGPoint(x: 200, y: 100)

    /// A fresh editor whose only edit is the right-mark pen drag: the
    /// reference composed pixels "the left mark is gone, the right one is
    /// not" are judged against.
    private func rightMarkOnlyEditor(image: CGImage) throws -> (Editor, Data) {
        let editor = Self.makeEditor(image: image)
        try drawPen(editor, from: rightStart, to: rightEnd)
        let composed = try XCTUnwrap(editor.canvas.composedImage())
        return (editor, try XCTUnwrap(tiff(composed)))
    }

    // MARK: - The defect: the eraser must erase

    func testADraggedEraserRemovesTheMarkItPassesOver() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try drawPen(editor, from: centreStart, to: centreEnd)
        let clean = try cleanTiff(image: image)
        let drawn = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertNotEqual(tiff(drawn), clean, "the pen stroke must be on the canvas before the erase")

        try erase(editor, over: centreStart, to: CGPoint(x: 170, y: 100))

        let erased = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(tiff(erased), clean, "the eraser drag must take the mark away")
    }

    // MARK: - Neighbouring behaviours the routing change touches

    /// The drawing path shares every mouse handler the eraser now routes
    /// through: a pen stroke must still commit, and its journal step must
    /// still undo.
    func testAPenStrokeStillCommitsAndStaysUndoable() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        let clean = try cleanTiff(image: image)

        try drawPen(editor, from: centreStart, to: centreEnd)

        let drawn = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertNotEqual(tiff(drawn), clean, "the pen stroke must still commit")

        editor.canvas.undo()
        let undone = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(tiff(undone), clean, "⌘Z must still retire the committed pen stroke")
    }

    /// An eraser drag that misses every mark changes nothing — and it must
    /// leave no undo step behind either: a pre-fix ghost stroke committed an
    /// invisible mark whose journal entry ate the next ⌘Z silently.
    func testAMissedEraseLeavesNoUndoStepBehind() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try drawPen(editor, from: centreStart, to: centreEnd)
        let drawn = try XCTUnwrap(editor.canvas.composedImage())

        // The fit display starts at view x=50, so (55..65, 100) is empty
        // canvas far from the mark's pixels (50..55, 50).
        try erase(editor, over: CGPoint(x: 55, y: 100), to: CGPoint(x: 65, y: 100))

        let afterMiss = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(tiff(afterMiss), tiff(drawn), "a missed erase must change nothing")

        editor.canvas.undo()
        let undone = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertNotEqual(tiff(undone), tiff(drawn), "the next ⌘Z must retire the last real edit, not the erase's nothing")
    }

    /// Undo does not cover mark removal in the editor — `DrawingSession.undo`
    /// deliberately never restores erased marks (the eraser's rule, shared
    /// with the drawing overlay) — so an erase is not undoable and this pins
    /// that erasing then undoing brings nothing back.
    func testAnErasedMarkStaysGoneUnderUndo() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try drawPen(editor, from: centreStart, to: centreEnd)
        let clean = try cleanTiff(image: image)

        try erase(editor, over: centreStart, to: CGPoint(x: 170, y: 100))
        editor.canvas.undo()
        editor.canvas.undo()

        let after = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(tiff(after), clean, "the erased mark stays erased — undo must not resurrect it")
    }

    // MARK: - The erase goes through the viewport mapping (S16)

    /// Erasing while zoomed lands where the pointer is: at 3× the drag's
    /// view targets are computed through the same viewport mapping the marks
    /// use, so the mark under the pointer goes and the mark the pointer
    /// never touched stays.
    func testAnEraserDragAtThreeTimesLandsWhereThePointerIs() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try drawPen(editor, from: leftStart, to: leftEnd)
        try drawPen(editor, from: rightStart, to: rightEnd)
        let (_, rightOnly) = try rightMarkOnlyEditor(image: image)
        let bothDrawn = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertNotEqual(tiff(bothDrawn), rightOnly, "both marks must be down before the erase")

        editor.canvas.applyZoom(3, anchoredAt: CGPoint(x: 150, y: 100))
        let zoomed = space(of: editor)
        // At the 3× mapping the visible canvas covers pixels 25..75, so the
        // drag from pixel (28, 50) to (34, 50) crosses the left mark only.
        try erase(
            editor,
            over: zoomed.viewPoint(fromPixel: CGPoint(x: 28, y: 50)),
            to: zoomed.viewPoint(fromPixel: CGPoint(x: 34, y: 50))
        )

        let erased = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(
            tiff(erased), rightOnly,
            "the zoomed eraser must take the mark under the pointer and nothing else")
    }

    /// A mark recorded at 3× keeps the space of the moment it was drawn, so
    /// erasing it after the viewport resets to the fit must convert through
    /// that mark's own space: the fit point the pointer sits on is the pixel
    /// the mark annotates.
    func testAMarkDrawnAtThreeTimesIsErasableFromTheFit() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        let clean = try cleanTiff(image: image)

        editor.canvas.applyZoom(3, anchoredAt: CGPoint(x: 150, y: 100))
        let zoomed = space(of: editor)
        editor.state.tool = .pen
        try drag(
            editor,
            from: zoomed.viewPoint(fromPixel: CGPoint(x: 50, y: 50)),
            to: zoomed.viewPoint(fromPixel: CGPoint(x: 55, y: 50))
        )
        let drawn = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertNotEqual(tiff(drawn), clean, "the mark drawn at 3× must be on the canvas")

        editor.canvas.resetViewport()
        editor.state.tool = .eraser
        try drag(editor, from: centreStart, to: CGPoint(x: 165, y: 100))

        let erased = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(tiff(erased), clean, "the 3×-recorded mark must erase where its pixels lie at the fit")
    }

    /// The journal keys off what the document gained, and an erase gains
    /// nothing undoable: the next ⌘Z after an erase must reach the previous
    /// real edit — here the applied crop — never spend itself on the erase.
    func testUndoAfterAnEraseGetsTheNextRealEditBack() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)

        // A mark inside the region the standing crop will take, then the
        // crop itself (marquee + Return, the staged-crop route).
        try drawPen(editor, from: CGPoint(x: 90, y: 160), to: CGPoint(x: 96, y: 160))
        editor.state.selectCrop()
        try drag(editor, from: CGPoint(x: 50, y: 100), to: CGPoint(x: 150, y: 200))
        try pressKey(editor, keyCode: 36, characters: "\r", ignoring: "\r")
        let cropped = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertTrue(hasInk(cropped), "the mark must survive inside the applied crop")
        XCTAssertEqual(cropped.width, 50, "the crop must be applied before the erase")

        // After the crop the display maps the 50×50 region at 4× into
        // (50, 0, 200, 200), so the mark's pixel (20, 80) sits at view
        // (130, 120) — the erase takes it from where the crop shows it.
        try erase(editor, over: CGPoint(x: 130, y: 120), to: CGPoint(x: 140, y: 120))
        let afterErase = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(afterErase.width, 50, "the erase must not move the crop's pixels")
        XCTAssertFalse(
            hasInk(afterErase),
            "the eraser takes the mark the cropped display shows it over")

        editor.canvas.undo()
        let undone = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(undone.width, 100, "the ⌘Z after an erase must restore the previous crop")
        XCTAssertFalse(
            hasInk(undone),
            "and the erased mark stays gone under it — undo never resurrects erased marks")
    }
}
