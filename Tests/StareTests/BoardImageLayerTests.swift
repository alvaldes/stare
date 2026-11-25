import AppKit
import CoreGraphics
import XCTest

@testable import Stare
import StareCore

/// T2b/S2: the image layer as part of everything the board shows — the
/// capture composes it beneath the marks at the page transform, a blur mark
/// diffuses it as content beneath — plus the panel-to-board routing on the
/// real view: ⌥-drag moves, a corner ⌥-drag resizes, ⌫ deletes.
@MainActor
final class BoardImageLayerTests: XCTestCase {
    private let size = CGSize(width: 900, height: 600)

    // MARK: Helpers

    private func solid(_ width: Int, _ height: Int, _ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A pixel in BOTTOM-LEFT coordinates — the bitmap context's own space,
    /// the one the compositor draws in.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let representation = NSBitmapImageRep(cgImage: image)
        let colour = representation.colorAt(x: x, y: image.height - 1 - y)!.usingColorSpace(.deviceRGB)!
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue)
    }

    private func buttonEvent(
        _ type: NSEvent.EventType, at point: CGPoint, option: Bool, window: NSWindow
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: CGPoint(x: point.x, y: size.height - point.y),
            modifierFlags: option ? [.option] : [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1,
            clickCount: 1, pressure: 1
        )
    }

    private func drag(
        _ view: WhiteboardView, window: NSWindow, from start: CGPoint, to end: CGPoint, option: Bool = true
    ) {
        view.mouseDown(with: buttonEvent(.leftMouseDown, at: start, option: option, window: window)!)
        view.mouseDragged(with: buttonEvent(.leftMouseDragged, at: end, option: option, window: window)!)
        view.mouseUp(with: buttonEvent(.leftMouseUp, at: end, option: option, window: window)!)
    }

    private func backspace(_ view: NSView) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}",
            isARepeat: false, keyCode: 51
        )!
        view.keyDown(with: event)
    }

    /// A capture-shaped image with two bands: the TOP half `top`, the BOTTOM
    /// half `bottom`, in the image's own top-down sense. The bitmap context is
    /// bottom-left, so the bottom band is the one drawn at y = 0.
    private func bands(
        _ width: Int, _ height: Int,
        top: (red: CGFloat, green: CGFloat, blue: CGFloat),
        bottom: (red: CGFloat, green: CGFloat, blue: CGFloat)
    ) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: bottom.red, green: bottom.green, blue: bottom.blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(CGColor(srgbRed: top.red, green: top.green, blue: top.blue, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return context.makeImage()!
    }

    /// A colour in VIEW space (top-left origin, the flipped view's own) read
    /// off a cached display. Measured, not assumed: `NSBitmapImageRep.colorAt`
    /// row 0 is the visual TOP, and a flipped view's cache maps view y straight
    /// onto it, so only the backing scale stands between the two.
    private func viewColour(
        _ rep: NSBitmapImageRep, view: NSView, at point: CGPoint
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let x = min(max(Int(point.x * scale), 0), rep.pixelsWide - 1)
        let y = min(max(Int(point.y * scale), 0), rep.pixelsHigh - 1)
        let colour = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue)
    }

    private func shiftEvent(
        _ type: NSEvent.EventType, at point: CGPoint, window: NSWindow
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: CGPoint(x: point.x, y: size.height - point.y),
            modifierFlags: [.shift],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1,
            clickCount: 1, pressure: 1
        )
    }

    private func escape(_ view: NSView) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false, keyCode: 53
        )!
        view.keyDown(with: event)
    }

    /// The real view in a real window, so the gesture path runs whole. Window
    /// order is never asserted — only the model through the view.
    private func makeBoardView(tool: Tool = .pen) throws -> (view: WhiteboardView, board: WhiteboardPages, window: NSWindow) {
        try XCTSkipIf(NSScreen.main == nil, "no display: the window-backed gesture paths cannot run")
        let state = EditorState()
        state.tool = tool
        let board = WhiteboardPages()
        let view = WhiteboardView(
            frame: CGRect(origin: .zero, size: size), state: state, board: board, onEscape: {}
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return (view, board, window)
    }

    // MARK: Rule 2 — the capture composes the layer beneath the marks

    func testTheCaptureComposesTheLayerBeneathTheMarksAtThePageTransform() throws {
        // The capture path's own pipeline: a solid page base at display pixel
        // size, the image layer composited onto it at the page transform, then
        // the marks composed over that at the same transform.
        let scale: CGFloat = 2
        let transform = BoardTransform(offset: CGSize(width: 2, height: 1), zoom: 1)
        let base = try XCTUnwrap(BoardBackground.white.captureBase(width: 32, height: 32))
        let layer = BoardImage(image: solid(2, 2, 1, 0, 0), rect: CGRect(x: 5, y: 5, width: 2, height: 2))
        let withImage = try XCTUnwrap(layer.composited(over: base, transform: transform, scale: scale))
        // view rect = (5−2, 5−1, 2, 2) = (3, 4, 2, 2) in top-left view points;
        // at scale 2 that is pixels x ∈ [6, 10), and — view y is top-left —
        // bottom-left rows y ∈ [32−12, 32−8) = [20, 24).
        let composed = try XCTUnwrap(
            MarkCompositor.composite(
                marks: [],
                over: withImage,
                scale: scale,
                diffusesContent: true,
                offset: transform.offset,
                zoom: transform.zoom
            )
        )
        XCTAssertEqual(pixel(composed, x: 6, y: 20).red, 1, accuracy: 0.01, "the layer is in the capture")
        XCTAssertLessThan(pixel(composed, x: 6, y: 20).green, 0.2, "the layer's pixel is the layer's colour")
        XCTAssertEqual(pixel(composed, x: 9, y: 23).red, 1, accuracy: 0.01)
        XCTAssertLessThan(pixel(composed, x: 9, y: 23).green, 0.2)
        XCTAssertEqual(pixel(composed, x: 9, y: 24).red, 1, accuracy: 0.01, "a pixel past the layer stays page colour")
        XCTAssertEqual(pixel(composed, x: 9, y: 24).green, 1, accuracy: 0.01)
        XCTAssertEqual(pixel(composed, x: 5, y: 20).green, 1, accuracy: 0.01, "a pixel before the layer stays page colour")
    }

    func testABlurMarkDiffusesTheImageLayerAsContentBeneathIt() throws {
        // blurSource(for:) composes exactly this stack: page colour, the image
        // layer, then the marks before the blur — so a blur mark diffuses the
        // image the way it diffuses marks. The layer is large against the
        // blur radius (15 px at scale 1) so the patch's centre is blurred
        // layer, not a half-mix with the page colour around it.
        let base = try XCTUnwrap(BoardBackground.white.captureBase(width: 256, height: 256))
        let layer = BoardImage(image: solid(120, 120, 1, 0, 0), rect: CGRect(x: 68, y: 68, width: 120, height: 120))
        let withImage = try XCTUnwrap(layer.composited(over: base, transform: .identity, scale: 1))
        let blur = Stroke(tool: .blur, ink: .red, points: [CGPoint(x: 68, y: 68), CGPoint(x: 188, y: 188)])

        let composed = try XCTUnwrap(
            MarkCompositor.composite(marks: [blur], over: withImage, scale: 1, diffusesContent: true)
        )
        let centre = pixel(composed, x: 128, y: 128)
        XCTAssertGreaterThan(centre.red, 0.6, "the blurred patch must show the image layer beneath")
        XCTAssertLessThan(centre.green, 0.35, "the patch must be diffused image, not page colour")

        // The control: the same blur over a page with no layer stays page
        // colour, so the red above can only have come from the layer.
        let plain = try XCTUnwrap(
            MarkCompositor.composite(marks: [blur], over: base, scale: 1, diffusesContent: true)
        )
        XCTAssertGreaterThan(pixel(plain, x: 128, y: 128).red, 0.95)
        XCTAssertGreaterThan(pixel(plain, x: 128, y: 128).green, 0.95)
    }

    // MARK: Rule 4 — ⌥-drag moves, a corner ⌥-drag resizes, ⌫ deletes

    func testTheSelectToolMovesTheImageAndBackspaceDeletesIt() throws {
        let (view, board, window) = try makeBoardView(tool: .select)
        defer { window.orderOut(nil) }

        view.pasteImage(solid(100, 80, 1, 0, 0))
        let pasted = try XCTUnwrap(board.currentPage.image)
        XCTAssertEqual(pasted.viewRect(for: board.viewTransform), CGRect(x: 400, y: 260, width: 100, height: 80))

        // A plain drag with the select tool (V) from inside the layer: it
        // follows the pointer in page space, with no modifier to remember.
        drag(view, window: window, from: CGPoint(x: 450, y: 300), to: CGPoint(x: 480, y: 330), option: false)
        let moved = try XCTUnwrap(board.currentPage.image)
        XCTAssertEqual(moved.rect, CGRect(x: 430, y: 290, width: 100, height: 80), "the same size, moved by the drag")
        XCTAssertEqual(moved.image.width, 100, "a move never resamples the image")

        // ⌫ with the layer still selected deletes it.
        backspace(view)
        XCTAssertNil(board.currentPage.image, "⌫ deletes the selected layer")
    }

    func testTheSelectToolResizesTheImageFromACorner() throws {
        let (view, board, window) = try makeBoardView(tool: .select)
        defer { window.orderOut(nil) }

        view.pasteImage(solid(100, 80, 0, 0, 1))
        _ = try XCTUnwrap(board.currentPage.image)

        // A drag from the top-left corner (within the editor's grip reach)
        // resizes with the opposite corner pinned — on the plain select tool.
        drag(view, window: window, from: CGPoint(x: 400, y: 260), to: CGPoint(x: 380, y: 240), option: false)
        let resized = try XCTUnwrap(board.currentPage.image)
        XCTAssertEqual(resized.rect, CGRect(x: 380, y: 240, width: 120, height: 100))
        XCTAssertEqual(resized.image.width, 100, "a resize keeps the same image")
    }

    func testAPlainClickStillDrawsAndTheLayerSurvivesPageChanges() throws {
        let (view, board, window) = try makeBoardView(tool: .pen)
        defer { window.orderOut(nil) }

        view.pasteImage(solid(100, 80, 1, 0, 0))
        try XCTUnwrap(board.currentPage.image)

        // A plain click-drag with the pen draws a mark, exactly as before T2b.
        drag(view, window: window, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 140, y: 140), option: false)
        XCTAssertEqual(board.currentPage.session.strokes.count, 1, "drawing without ⌥ is untouched")

        // Changing pages and coming back keeps the layer.
        view.selectNextPage()
        XCTAssertNil(board.currentPage.image)
        view.selectPreviousPage()
        XCTAssertNotNil(board.currentPage.image, "the layer survives a round trip over the pages")
        XCTAssertEqual(board.currentPage.session.strokes.count, 1, "so do the marks")
    }

    // MARK: B4 — the V tool's move and resize

    /// The layer follows the pointer exactly: the drag is applied as an
    /// absolute destination from where it started, so a drag told the same
    /// place twice does not add the travel twice (the first cut applied the
    /// absolute delta per event and the layer ran away from the pointer).
    func testTheDragKeepsTheLayerUnderThePointerAtAnyZoom() throws {
        let (view, board, window) = try makeBoardView(tool: .select)
        defer { window.orderOut(nil) }
        view.pasteImage(solid(100, 80, 1, 0, 0))
        let pasted = try XCTUnwrap(board.currentPage.image)
        XCTAssertEqual(pasted.viewRect(for: board.viewTransform), CGRect(x: 400, y: 260, width: 100, height: 80))

        // Zoom in, so a view point is half a page point.
        view.zoomPageIn()
        XCTAssertEqual(board.viewTransform.zoom, 1.25, accuracy: 0.001)
        let before = board.viewTransform.rect(fromPage: try XCTUnwrap(board.currentPage.image).rect)

        // Down, then three dragged events of the same travel — the shape of a
        // real drag, which fires many events.
        let start = CGPoint(x: before.midX, y: before.midY)
        view.mouseDown(with: buttonEvent(.leftMouseDown, at: start, option: false, window: window)!)
        let end = CGPoint(x: start.x + 40, y: start.y + 25)
        for _ in 0..<3 {
            view.mouseDragged(with: buttonEvent(.leftMouseDragged, at: end, option: false, window: window)!)
        }
        view.mouseUp(with: buttonEvent(.leftMouseUp, at: end, option: false, window: window)!)

        let after = board.viewTransform.rect(fromPage: try XCTUnwrap(board.currentPage.image).rect)
        XCTAssertEqual(after.origin.x - before.origin.x, 40, accuracy: 0.5,
            "the layer travels exactly what the pointer travelled on screen")
        XCTAssertEqual(after.origin.y - before.origin.y, 25, accuracy: 0.5)
        XCTAssertEqual(after.width, before.width, accuracy: 0.5)
        XCTAssertEqual(after.height, before.height, accuracy: 0.5)
        let moved = try XCTUnwrap(board.currentPage.image)
        XCTAssertEqual(moved.image.width, 100, "a move never resamples the image")
        XCTAssertEqual(moved.image.height, 80)
    }

    /// Shift holds the shape while a corner grip resizes: the pointer drives
    /// one axis and the other follows the start rect's ratio.
    func testShiftOnACornerGripKeepsTheAspectRatio() throws {
        let (view, board, window) = try makeBoardView(tool: .select)
        defer { window.orderOut(nil) }
        view.pasteImage(solid(100, 80, 1, 0, 0))
        XCTAssertEqual(try XCTUnwrap(board.currentPage.image).rect, CGRect(x: 400, y: 260, width: 100, height: 80))

        let start = CGPoint(x: 400, y: 260)
        let end = CGPoint(x: 380, y: 100)
        view.mouseDown(with: buttonEvent(.leftMouseDown, at: start, option: false, window: window)!)
        view.mouseDragged(with: shiftEvent(.leftMouseDragged, at: end, window: window)!)
        view.mouseUp(with: shiftEvent(.leftMouseUp, at: end, window: window)!)

        let resized = try XCTUnwrap(board.currentPage.image).rect
        XCTAssertEqual(resized.width / resized.height, 100.0 / 80.0, accuracy: 0.01,
            "the shape is held, so the image is never distorted by a Shift resize")
        XCTAssertEqual(resized.maxX, 500, accuracy: 0.5, "the opposite corner stays put")
        XCTAssertEqual(resized.maxY, 340, accuracy: 0.5)
    }

    // MARK: B5 — the layer paints the right way up

    func testThePageImagePaintsTheRightWayUp() throws {
        let (view, board, window) = try makeBoardView()
        defer { window.orderOut(nil) }

        // Red on top, blue underneath, in the image's own sense.
        view.pasteImage(bands(100, 80, top: (1, 0, 0), bottom: (0, 0, 1)))
        let rect = try XCTUnwrap(board.currentPage.image).viewRect(for: board.viewTransform)
        XCTAssertEqual(rect, CGRect(x: 400, y: 260, width: 100, height: 80), "the frame was never the defect")

        view.displayIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)

        // The view is flipped, so `minY` is the top edge of the frame.
        let top = viewColour(rep, view: view, at: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.25))
        let bottom = viewColour(rep, view: view, at: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.75))
        XCTAssertGreaterThan(top.red, 0.5, "the top of the frame shows the image's top band, not the bottom one: \(top) over \(bottom)")
        XCTAssertGreaterThan(bottom.blue, 0.5, "the bottom of the frame shows its bottom band, not the top one: \(bottom) over \(top)")
    }

    // MARK: B6 — Escape clears the page, the image included

    func testEscapeOnTheBoardClearsTheImageWithTheMarks() throws {
        let (view, board, window) = try makeBoardView()
        defer { window.orderOut(nil) }

        view.pasteImage(solid(100, 80, 1, 0, 0))
        XCTAssertNotNil(board.currentPage.image)

        escape(view)
        XCTAssertNil(board.currentPage.image, "esc promises 'clear page': the image layer goes with it")
    }

    func testEscapeWithAMarkSelectedOnlyDropsTheSelectionAndKeepsTheImage() throws {
        let (view, board, window) = try makeBoardView()
        defer { window.orderOut(nil) }

        view.pasteImage(solid(100, 80, 1, 0, 0))
        drag(view, window: window, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 140, y: 140), option: false)
        let mark = try XCTUnwrap(board.currentPage.session.strokes.first)
        view.restoreSelection([mark.id])
        XCTAssertFalse(view.selectedMarkIDs.isEmpty)

        escape(view)
        XCTAssertTrue(view.selectedMarkIDs.isEmpty, "esc gives the selection up first")
        XCTAssertEqual(board.currentPage.session.strokes.count, 1, "and clearing waits for the next press")
        XCTAssertNotNil(board.currentPage.image, "a stray click never costs the page's image either")

        // The next press is the clear, and it takes the image too.
        escape(view)
        XCTAssertNil(board.currentPage.image)
    }
}
