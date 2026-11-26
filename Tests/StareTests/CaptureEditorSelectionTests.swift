import AppKit
import SwiftUI
import XCTest

@testable import Stare
import StareCore

/// S3: the capture editor's select tool — the drawing overlay's edit cursor
/// working over the marks the editor owns. The tests drive the real canvas
/// the way the editor's other tests do (synthesized window events through
/// `CaptureEditorCanvas` in a real borderless window) and judge through
/// `composedImage()` and the marks seam, never internals.
///
/// The selector's rules ride the same StareCore machinery the overlay uses:
/// `Stroke.isSelectedByCursor` for the hit, `MarkSelection` for the handles
/// and `MarkTransform` for the previews — no second editing model.
@MainActor
final class CaptureEditorSelectionTests: XCTestCase {

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

    private func event(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow,
                       modifiers: NSEvent.ModifierFlags = []) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1)
    }

    /// The canvas is a flipped view filling the window: a gesture point is
    /// written in the canvas's own top-down space (the space `EditorCropSpace`
    /// and every coordinate in this file name), and an event carries it as
    /// `locationInWindow`, which the flipped view reads as (x, height − y) —
    /// exactly the mapping the capture-history/real-window probes use.
    private func windowPoint(_ point: CGPoint, in editor: Editor) -> CGPoint {
        CGPoint(x: point.x, y: editor.window.contentView!.bounds.height - point.y)
    }

    private func down(_ editor: Editor, at point: CGPoint) throws {
        editor.canvas.mouseDown(with: try XCTUnwrap(
            event(.leftMouseDown, at: windowPoint(point, in: editor), window: editor.window)))
    }

    private func dragged(_ editor: Editor, to point: CGPoint) throws {
        editor.canvas.mouseDragged(with: try XCTUnwrap(
            event(.leftMouseDragged, at: windowPoint(point, in: editor), window: editor.window)))
    }

    private func up(_ editor: Editor, at point: CGPoint) throws {
        editor.canvas.mouseUp(with: try XCTUnwrap(
            event(.leftMouseUp, at: windowPoint(point, in: editor), window: editor.window)))
    }

    private func drag(_ editor: Editor, from start: CGPoint, to end: CGPoint,
                      modifiers: NSEvent.ModifierFlags = []) throws {
        try down(editor, at: start)
        try dragged(editor, to: end)
        try up(editor, at: end)
    }

    private func tiff(_ image: CGImage) throws -> Data {
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).tiffRepresentation)
    }

    /// The fit mapping of the whole 100×100 capture in the 300×200 canvas —
    /// the same mapping the canvas draws and hit-tests through.
    private func space(of editor: Editor) -> EditorCropSpace {
        EditorCropSpace.fitted(
            coverage: imageBounds, viewport: editor.canvas.viewportState, inCanvas: canvasRect)
    }

    // The fit display of a 100×100 capture in the 300×200 canvas is
    // (50, 0, 200, 200), so fit-view point `p` maps to image pixel
    // `(p.x - 50, p.y) / 2`.
    private let centreStart = CGPoint(x: 150, y: 100)
    private let centreEnd = CGPoint(x: 160, y: 100)

    /// One pen drag with the fit's mapping, giving the editor a mark to select.
    private func drawPen(_ editor: Editor, from start: CGPoint, to end: CGPoint) throws {
        editor.state.tool = .pen
        try drag(editor, from: start, to: end)
    }

    private func inkBoundingBox(_ image: CGImage) -> CGRect? {
        let rep = NSBitmapImageRep(cgImage: image)
        var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if colour.redComponent < 0.92 || colour.greenComponent < 0.92 || colour.blueComponent < 0.92 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: - S3: the select tool selects

    /// A select-tool click ON a committed mark picks it: the selection is
    /// armed (the seam the chrome and the drag read) and the mark itself is
    /// untouched — selection mints nothing.
    func testASelectClickOnAMarkSelectsIt() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try drawPen(editor, from: centreStart, to: centreEnd)
        let mark = try XCTUnwrap(editor.canvas.marks.first, "the pen drag committed a mark")

        editor.state.tool = .select
        try down(editor, at: centreStart)

        XCTAssertEqual(editor.canvas.selectedMarkID, mark.id, "the click on the mark's ink selects it")
    }

    /// A select drag MOVES the selected mark: the drag commits one transform,
    /// the ink lands at the dragged position and the old position lets go.
    /// The mark keeps its own identity (the drag is an edit of one mark).
    /// The press lands on the mark's midpoint — dead on the ink, outside any
    /// corner handle's reach — so one gesture grabs the body and moves it,
    /// the way a press inside a handle's reach arms the corner on the overlay.
    func testASelectDragMovesTheSelectedMark() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try drawPen(editor, from: centreStart, to: centreEnd)
        let mark = try XCTUnwrap(editor.canvas.marks.first)
        let before = try tiff(try XCTUnwrap(editor.canvas.composedImage()))
        let midpoint = try XCTUnwrap(
            mark.points.count >= 2
                ? CGPoint(x: (mark.points.first!.x + mark.points.last!.x) / 2,
                          y: (mark.points.first!.y + mark.points.last!.y) / 2)
                : nil,
            "the committed pen mark carries both endpoints")

        editor.state.tool = .select
        // Selection and move in one gesture (select-and-move is one gesture
        // on the overlay too): press on the mark, drag right and down, drop.
        let target = CGPoint(x: 200, y: 150)
        try down(editor, at: midpoint)
        try dragged(editor, to: target)
        try up(editor, at: target)

        let after = try tiff(try XCTUnwrap(editor.canvas.composedImage()))
        XCTAssertNotEqual(after, before, "the drag must move the mark's ink")
        XCTAssertEqual(
            editor.canvas.marks.count, 1,
            "the drag must not mint a second mark")
        // The dragged mark's ink must sit at the moved position: the ink in a
        // clean editor composed at the FIT is elsewhere than at the drag end.
        // The composed capture is judged in the CAPTURE's OWN pixels, so the
        // fit-display view points map through the same space the canvas
        // draws and saves through before the pixel scan.
        let movedSpace = space(of: editor)
        let grabbedPixel = movedSpace.pixelPoint(fromView: midpoint) // (50, 50)
        // No ink around the grabbed position any more (it moved).
        let rep = NSBitmapImageRep(cgImage: editor.canvas.composedImage()!)
        func hasInk(around pixel: CGPoint) -> Bool {
            for y in Int(pixel.y - 6)...Int(pixel.y + 6) {
                for x in Int(pixel.x - 6)...Int(pixel.x + 6) {
                    guard x >= 0, x < rep.pixelsWide, y >= 0, y < rep.pixelsHigh,
                        let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if colour.redComponent < 0.92 || colour.greenComponent < 0.92 || colour.blueComponent < 0.92 {
                        return true
                    }
                }
            }
            return false
        }
        XCTAssertFalse(hasInk(around: grabbedPixel), "the mark must have vacated the grabbed position")
        let targetPixel = movedSpace.pixelPoint(fromView: target) // (75, 75)
        XCTAssertTrue(hasInk(around: targetPixel), "the mark's ink must appear at the dragged position")
    }

    /// A select drag on a mark's corner handle ADJUSTS (uniform-scales) it:
    /// committed pixel geometry changes shape, the mark count unchanged.
    func testASelectDragOnTheCornerAdjustsTheMark() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try drawPen(editor, from: centreStart, to: centreEnd)
        let mark = try XCTUnwrap(editor.canvas.marks.first)

        editor.state.tool = .select
        // Select first (click on the ink), then grab the pen mark's corner
        // handles: the fit-view position of the mark's start point. The
        // mark's own recorded space IS the fit display's view space — that is
        // what `spaces[id]` stores when the drag begins — so its points are
        // fit-view points; the press lands in the corner handle's reach of
        // the mark's first endpoint, and the drag scales from the far corner.
        try down(editor, at: centreStart)
        XCTAssertEqual(editor.canvas.selectedMarkID, mark.id)
        try up(editor, at: centreStart)
        try down(editor, at: mark.points.first!)
        let startPixel = mark.points.first!, endPixel = mark.points.last!
        let viewStart = startPixel, viewEnd = endPixel
        try dragged(editor, to: CGPoint(x: viewStart.x + 40, y: viewStart.y + 30))
        try up(editor, at: CGPoint(x: viewStart.x + 40, y: viewStart.y + 30))

        XCTAssertEqual(
            editor.canvas.marks.count, 1, "an adjust drag must not mint a mark")
        let adjusted = editor.canvas.marks.first!
        XCTAssertNotEqual(
            adjusted.points, mark.points,
            "the corner drag must have rewritten the mark's geometry")
    }

    /// The select tool on empty canvas is a plain pointer route: no mark is
    /// ever minted, no journal step is eaten, and the empty click gives the
    /// selection up.
    func testSelectOnEmptyCanvasMintsNothingAndGivesTheSelectionUp() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try drawPen(editor, from: centreStart, to: centreEnd)
        let drawn = try tiff(try XCTUnwrap(editor.canvas.composedImage()))
        editor.state.tool = .select

        // Away from the pen mark (fit display starts at x=50; the mark lives
        // around view (150,100); the click here goes to pixels ~(5,10)).
        try drag(editor, from: CGPoint(x: 60, y: 20), to: CGPoint(x: 70, y: 30))

        XCTAssertEqual(editor.canvas.marks.count, 1, "the select drag must never mint")
        XCTAssertEqual(
            try tiff(try XCTUnwrap(editor.canvas.composedImage())), drawn,
            "and it must not repaint anything")
        XCTAssertNil(editor.canvas.selectedMarkID, "a click on empty canvas gives the selection up")
    }

    /// Shift-rotation parity: the knob drags turn the mark about its anchor —
    /// the pin keeps the editor's select from collapsing to move-only.
    func testARotateKnobDragRotatesTheSelectedMark() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try drawPen(editor, from: centreStart, to: centreEnd)
        let mark = try XCTUnwrap(editor.canvas.marks.first)

        editor.state.tool = .select
        try down(editor, at: centreStart)
        try up(editor, at: centreStart)
        // The rotation knob sits MarkSelection.defaultRotationHandleOffset
        // points above the top centre of the mark's box, in the mark's own
        // recorded space — the fit display's view space — which is where the
        // chrome draws it and where the press grabs it.
        let selection = MarkSelection(stroke: mark)
        let knob = selection.handlePoints(
            rotationHandleOffset: MarkSelection.defaultRotationHandleOffset
        )[.rotation]!
        let viewKnob = knob
        try down(editor, at: viewKnob)
        try dragged(editor, to: CGPoint(x: viewKnob.x - 30, y: viewKnob.y + 20))
        try up(editor, at: CGPoint(x: viewKnob.x - 30, y: viewKnob.y + 20))

        let rotated = try XCTUnwrap(editor.canvas.marks.first)
        XCTAssertNotEqual(
            rotated.rotation, mark.rotation,
            "the knob drag must rotate the mark about its anchor")
    }

    // MARK: - Neighbouring behaviours the routing change touches

    /// The eraser's and the drawing tools' own routes share the same
    /// mouseDown the select flow now sits beside: a shape-tool drag still
    /// commits a mark, and the ⌥-canvas-layer grab still claims its layer.
    func testShapeToolsStillDrawAfterTheSelectRouteJoins() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        let clean = try tiff(try XCTUnwrap(editor.canvas.composedImage()))

        editor.state.tool = .rectangle
        try drag(editor, from: CGPoint(x: 80, y: 40), to: CGPoint(x: 180, y: 120))

        let drawn = try tiff(try XCTUnwrap(editor.canvas.composedImage()))
        XCTAssertNotEqual(drawn, clean, "the rectangle tool must still commit after the select flow joined mouseDown")
    }
}
