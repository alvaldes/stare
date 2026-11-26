import AppKit
import CoreGraphics
import XCTest

@testable import Stare
import StareCore

/// S1/S3: the crop's frame. The blue-dotted treatment the owner named is
/// replaced by the idiom the reference is an instance of: corner brackets and
/// four edge handles in the accent colour, the region outside the crop dimmed.
/// Dragging inside the crop moves it, dragging an edge or a corner resizes
/// it, and Shift keeps the aspect ratio. The staged-crop contract itself —
/// Return confirms, Esc and a tool pick cancel, exactly one journal step — is
/// unchanged and stays pinned by `CaptureStagedCropTests`; here the frame is
/// judged in real pixels over the real editor window, and the move/resize
/// rules through real mouse events.
@MainActor
final class CaptureCropFrameTests: XCTestCase {
    // MARK: - Fixtures (the staged-crop tests' own, reused verbatim)

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
        window.confineToPrimaryScreen()
        window.contentView = canvas
        window.orderFrontRegardless()
        XCTAssertEqual(canvas.bounds.size, CGSize(width: 300, height: 200))
        return Editor(canvas: canvas, state: state, window: window)
    }

    private func event(
        _ type: NSEvent.EventType, at viewPoint: CGPoint, window: NSWindow,
        shift: Bool = false
    ) -> NSEvent? {
        // The events speak window coordinates (bottom-left origin); the flipped
        // view converts them, so tests state points in view space. The canvas
        // fills the window.
        NSEvent.mouseEvent(
            with: type, location: CGPoint(x: viewPoint.x, y: window.frame.height - viewPoint.y),
            modifierFlags: shift ? [.shift] : [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1)
    }

    private func down(_ editor: Editor, at point: CGPoint, shift: Bool = false) throws {
        editor.canvas.mouseDown(with: try XCTUnwrap(
            event(.leftMouseDown, at: point, window: editor.window, shift: shift)))
    }

    private func dragged(_ editor: Editor, to point: CGPoint, shift: Bool = false) throws {
        editor.canvas.mouseDragged(with: try XCTUnwrap(
            event(.leftMouseDragged, at: point, window: editor.window, shift: shift)))
    }

    private func up(_ editor: Editor, at point: CGPoint, shift: Bool = false) throws {
        editor.canvas.mouseUp(with: try XCTUnwrap(
            event(.leftMouseUp, at: point, window: editor.window, shift: shift)))
    }

    private func pressReturn(_ editor: Editor) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: editor.window.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36))
        editor.canvas.keyDown(with: event)
    }

    // MARK: - Raster

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func colourAt(_ rep: NSBitmapImageRep, _ point: CGPoint) -> NSColor? {
        guard point.x >= 0, point.y >= 0,
            Int(point.x) < rep.pixelsWide, Int(point.y) < rep.pixelsHigh else { return nil }
        return rep.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.deviceRGB)
    }

    /// The chrome accent (the selection blue the overlay's chrome draws:
    /// 0.25, 0.55, 1) rendered over anything the picture can put beneath.
    private func isAccent(_ colour: NSColor?) -> Bool {
        guard let colour else { return false }
        return colour.blueComponent > 0.78 && colour.redComponent < 0.55
            && colour.greenComponent > 0.31 && colour.greenComponent < 0.78
    }

    /// Whether any pixel within `radius` of `point` reads as the accent.
    private func hasAccent(_ rep: NSBitmapImageRep, near point: CGPoint, radius: CGFloat = 4) -> Bool {
        for deltaX in stride(from: -radius, through: radius, by: 1) {
            for deltaY in stride(from: -radius, through: radius, by: 1) {
                if isAccent(colourAt(rep, CGPoint(x: point.x + deltaX, y: point.y + deltaY))) {
                    return true
                }
            }
        }
        return false
    }

    /// Bright image pixels, so a leftover grip square (pure white) cannot hide
    /// against them.
    private static func grayImage(width: Int, height: Int) -> CGImage? {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func splitImage(width: Int, height: Int) -> CGImage? {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return context.makeImage()
    }

    /// White with one black square — a probe drawn for top-left image pixels
    /// (the bitmap context runs bottom-left, so the fill's y is mirrored) —
    /// so a moved crop's content can be told apart byte for byte.
    private static func probeImage(width: Int, height: Int, probe: CGRect) -> CGImage? {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(
            x: probe.minX, y: CGFloat(height) - probe.maxY,
            width: probe.width, height: probe.height))
        return context.makeImage()
    }

    private func tiff(_ image: CGImage) -> Data {
        NSBitmapImageRep(cgImage: image).tiffRepresentation!
    }

    /// The standing staged rectangle: drag view (70,110)–(130,170) over a
    /// 100×100 capture in a 300×200 window → the fit is ×2 (display
    /// (50,0,200,200)), so the staged pixel region is (10,55,30,30) and waits.
    /// The rectangle sits in the display's lower half so the confirm hint pill
    /// (drawn above the rectangle's top edge, inside the display) never
    /// overlaps the frame the tests sample.
    private func stageStandingRectangle(_ editor: Editor) throws {
        editor.state.selectCrop()
        try down(editor, at: CGPoint(x: 70, y: 110))
        try dragged(editor, to: CGPoint(x: 130, y: 170))
        try up(editor, at: CGPoint(x: 130, y: 170))
    }

    // MARK: - The frame in pixels (S1)

    // MARK: - The frame in pixels (S1)

    /// The staged rectangle's frame in real pixels: accent brackets at the
    /// corners, accent handles at the four edge midpoints, no accent anywhere
    /// between bracket and handle (no solid border), no white grip squares
    /// left, and the shipped dim outside the region.
    func testTheStagedFrameIsBracketsHandlesAndTheDim() throws {
        let image = try XCTUnwrap(Self.grayImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        defer { editor.window.orderOut(nil) }
        editor.state.selectCrop()
        // A wide staged rectangle — pixel region (5,55,90,30), view
        // (60,110,180,60) — so the frame's own gaps sit clear of the confirm
        // hint pill and of the caps that round off bracket and handle.
        try down(editor, at: CGPoint(x: 60, y: 110))
        try dragged(editor, to: CGPoint(x: 240, y: 170))
        try up(editor, at: CGPoint(x: 240, y: 170))

        let rep = try render(editor.canvas)
        let corners = [
            CGPoint(x: 60, y: 110), CGPoint(x: 240, y: 110),
            CGPoint(x: 60, y: 170), CGPoint(x: 240, y: 170),
        ]
        let midEdges = [
            CGPoint(x: 150, y: 110), CGPoint(x: 150, y: 170),
            CGPoint(x: 60, y: 140), CGPoint(x: 240, y: 140),
        ]
        for corner in corners {
            XCTAssertTrue(
                hasAccent(rep, near: corner, radius: 4),
                "an accent bracket must paint at the corner \(corner)")
        }
        for mid in midEdges {
            XCTAssertTrue(
                hasAccent(rep, near: mid, radius: 4),
                "an accent edge handle must paint at \(mid)")
        }
        // Strictly between the bracket's reach and the handle's: no accent, so
        // the frame is brackets and handles, never a solid border across them.
        XCTAssertFalse(hasAccent(rep, near: CGPoint(x: 100, y: 110), radius: 1.5),
                       "no border paints between the top-left bracket and the top handle")
        XCTAssertFalse(hasAccent(rep, near: CGPoint(x: 190, y: 110), radius: 1.5),
                       "no border paints between the top handle and the top-right bracket")
        // The white grip squares the old frame drew at these anchors are gone.
        for anchor in corners + midEdges {
            XCTAssertFalse(hasBright(rep, near: anchor, radius: 3),
                           "no white grip square may paint at the anchor \(anchor)")
        }
        // The dim outside: the same picture is dimmed outside the region and
        // not inside it (the shipped 0.35 shroud, the region's own boundary).
        // Probes sit clear of the confirm hint pill, which hangs above the
        // staged rectangle's top edge.
        let inside = brightness(colourAt(rep, CGPoint(x: 150, y: 140)))
        let outside = brightness(colourAt(rep, CGPoint(x: 56, y: 24)))
        XCTAssertGreaterThan(inside ?? 0, 0.46, "the lit region keeps the picture's own brightness")
        XCTAssertLessThan(outside ?? 1, 0.44, "the outside of the crop is dimmed")
    }

    private func hasBright(_ rep: NSBitmapImageRep, near point: CGPoint, radius: CGFloat = 4) -> Bool {
        for deltaX in stride(from: -radius, through: radius, by: 1) {
            for deltaY in stride(from: -radius, through: radius, by: 1) {
                guard let colour = colourAt(rep, CGPoint(x: point.x + deltaX, y: point.y + deltaY))
                else { continue }
                if min(colour.redComponent, colour.greenComponent, colour.blueComponent) > 0.82 {
                    return true
                }
            }
        }
        return false
    }

    private func brightness(_ colour: NSColor?) -> CGFloat? {
        colour.map { ($0.redComponent + $0.greenComponent + $0.blueComponent) / 3 }
    }

    // MARK: - The grab rules (S1), through real mouse events

    /// Dragging an edge resizes: the top edge pulled one view point up grows
    /// the staged rectangle's height, keeps its width, and Return cuts exactly
    /// the grown region.
    func testDraggingAnEdgeResizesTheStagedRectangle() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        defer { editor.window.orderOut(nil) }
        try stageStandingRectangle(editor)

        try down(editor, at: CGPoint(x: 100, y: 110)) // the top edge's midpoint
        try dragged(editor, to: CGPoint(x: 100, y: 50))
        try up(editor, at: CGPoint(x: 100, y: 50))
        try pressReturn(editor)

        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(composed.width, 30, "the width never moved")
        XCTAssertEqual(composed.height, 60, "the pulled edge grew the height: (10,25,30,60)")
        XCTAssertEqual(
            tiff(composed), tiff(try XCTUnwrap(image.cropping(
                to: CGRect(x: 10, y: 25, width: 30, height: 60)))),
            "the region the drag left is exactly what the crop cuts")
    }

    /// Dragging inside the crop moves it: one drag by (+16, −14) view points —
    /// (+8, −7) pixels — leaves the region the same size and cuts exactly the
    /// moved region's pixels.
    func testDraggingInsideMovesTheStagedRectangle() throws {
        let image = try XCTUnwrap(Self.probeImage(width: 100, height: 100, probe: CGRect(x: 18, y: 60, width: 10, height: 10)))
        let editor = Self.makeEditor(image: image)
        defer { editor.window.orderOut(nil) }
        try stageStandingRectangle(editor)

        try down(editor, at: CGPoint(x: 100, y: 140)) // the interior
        try dragged(editor, to: CGPoint(x: 116, y: 126))
        try up(editor, at: CGPoint(x: 116, y: 126))
        try pressReturn(editor)

        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(composed.width, 30, "the move never resizes")
        XCTAssertEqual(composed.height, 30)
        XCTAssertEqual(
            tiff(composed), tiff(try XCTUnwrap(image.cropping(
                to: CGRect(x: 18, y: 48, width: 30, height: 30)))),
            "the region the move left is exactly what the crop cuts")
    }

    /// Shift on a corner drag keeps the staged rectangle's aspect ratio: the
    /// start (30×30, a 1:1 square) stays a square — the drag that would make a
    /// 36×35 rectangle leaves 36×36.
    func testShiftOnACornerDragKeepsTheStagedAspectRatio() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        defer { editor.window.orderOut(nil) }
        try stageStandingRectangle(editor)

        try down(editor, at: CGPoint(x: 70, y: 110), shift: true) // the top-left corner
        try dragged(editor, to: CGPoint(x: 58, y: 100), shift: true)
        try up(editor, at: CGPoint(x: 58, y: 100), shift: true)
        try pressReturn(editor)

        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(composed.width, 36, "Shift keeps the square square")
        XCTAssertEqual(composed.height, 36)
        XCTAssertEqual(
            tiff(composed), tiff(try XCTUnwrap(image.cropping(
                to: CGRect(x: 4, y: 49, width: 36, height: 36)))),
            "the locked aspect region is exactly what the crop cuts")
    }
}
