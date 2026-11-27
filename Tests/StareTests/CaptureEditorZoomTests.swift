import AppKit
import CoreGraphics
import XCTest
@testable import Stare
import StareCore

/// S16/T9: zoom and pan over the capture in the editor. The canvas is a view
/// over the pure `EditorViewport` (StareCore), and every mark keeps the space
/// it was recorded in, so the whole risk of this feature — where a stroke
/// drawn at 3× lands in the saved pixels — is pinned here through
/// `composedImage()`, the same public interface Save and Copy use: a mark
/// drawn at 3× must land on exactly the same image pixels as the same stroke
/// drawn at the fit, whether it was drawn zoomed or panned (S16's own words).
/// Tool keys never change (S16) and the gesture vocabulary is the board's
/// (⌘+ ⌘− ⌘0, ⌘ + scroll, space-drag pan, pinch).
@MainActor
final class CaptureEditorZoomTests: XCTestCase {

    private let canvasRect = CGRect(x: 0, y: 0, width: 300, height: 200)
    private let imageBounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    // MARK: - The cursor the class leaves behind

    /// The process's cursor before the class ran, restored in teardown:
    /// the canvas's key handling arms tools through the product's own
    /// `NSCursor.set()`, and AppKit spins none of that away between classes.
    /// Whatever stands when the class ends is what the next class meets —
    /// TextSelectionWindowTests shares this process and reads
    /// `NSCursor.current` as its baseline — so the restore is the same
    /// leave-it-as-found family the activation hooks use, never a stack
    /// push/pop the product code does not participate in.
    private var foundCursor: NSCursor?

    override func setUp() {
        super.setUp()
        foundCursor = NSCursor.current
    }

    override func tearDown() {
        foundCursor?.set()
        super.tearDown()
    }

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

    /// A black left half and a white right half, so a mark that lands on the
    /// wrong side of the split shows up in the composed pixels, not just in
    /// some metadata.
    private static func splitImage(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return context.makeImage()
    }

    private struct Editor {
        let canvas: CaptureEditorCanvas
        let state: EditorState
        let window: NSWindow
    }

    private static func makeEditor(image: CGImage, size: CGSize = CGSize(width: 300, height: 200)) -> Editor {
        let canvas = CaptureEditorCanvas(image: image)
        let state = EditorState()
        canvas.state = state
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas
        XCTAssertEqual(canvas.bounds.size, size)
        return Editor(canvas: canvas, state: state, window: window)
    }

    private func event(
        _ type: NSEvent.EventType, at point: CGPoint, window: NSWindow
    ) -> NSEvent? {
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

    /// A real key press through the canvas's key handling, the way the staged
    /// crop tests drive keys: characters, ignoring-modifiers and key code are
    /// all caller-supplied.
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

    /// A synthesized hardware-shaped scroll event, the way the board's phase
    /// tests drive `scrollWheel`. The CG phase fields are probe-verified
    /// (see `BoardScrollHardwarePhaseTests`): scroll phase 1/2/4/8 decode to
    /// `.began`/`.changed`/`.ended`/`.cancelled`, momentum phase 1/2/3 to
    /// begin/continued/end. The inversion flag has no CG field this SDK
    /// names, so synthesized events never report
    /// `isDirectionInvertedFromDevice`; the felt-direction rule is pinned at
    /// the pure seam (`ScrollPan`) instead.
    private enum CGScrollPhase {
        static let began: Int64 = 1
        static let changed: Int64 = 2
        static let ended: Int64 = 4
        static let cancelled: Int64 = 8
    }
    private enum CGMomentumPhase {
        static let begin: Int64 = 1
        static let continued: Int64 = 2
        static let end: Int64 = 3
    }

    private func scrollEvent(
        deltaY: Int32,
        command: Bool,
        scrollPhase: Int64? = nil,
        momentumPhase: Int64? = nil,
        atPoint: CGPoint? = nil
    ) -> NSEvent? {
        guard let cg = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else { return nil }
        if command { cg.flags = .maskCommand }
        if let scrollPhase { cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase) }
        if let momentumPhase { cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase) }
        if let atPoint { cg.location = atPoint }
        return NSEvent(cgEvent: cg)
    }

    private func tiff(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).tiffRepresentation
    }

    /// Draws one pen stroke with the tool already in hand (`.pen` is the
    /// editor state's default): a straight drag over the split's edge, from
    /// content `(140, 100)` to `(160, 100)` in fit-view coordinates.
    private func drawSplitStroke(_ editor: Editor, viewStart: CGPoint, viewEnd: CGPoint) throws {
        try down(editor, at: viewStart)
        try dragged(editor, to: viewEnd)
        try up(editor, at: viewEnd)
    }

    /// The fit mapping of the whole 100×100 capture in the 300×200 canvas,
    /// as the tests read it for placing gestures.
    private var fit: CGRect {
        EditorCropSpace
            .fitted(coverage: imageBounds, inCanvas: canvasRect)
            .display
    }

    // MARK: - The composed mapping keeps the anchor's pixel (S16)

    func testComposingTheViewportKeepsTheAnchorsPixel() {
        let fitSpace = EditorCropSpace.fitted(coverage: imageBounds, inCanvas: canvasRect)
        let anchor = CGPoint(x: 150, y: 100)
        let zoomed = EditorViewport.identity.zoomed(to: 3, anchoredAt: anchor, fit: fitSpace.display, canvas: canvasRect)
        let zoomedSpace = EditorCropSpace.fitted(coverage: imageBounds, viewport: zoomed, inCanvas: canvasRect)
        XCTAssertEqual(
            zoomedSpace.pixelPoint(fromView: anchor),
            fitSpace.pixelPoint(fromView: anchor),
            "zooming about the pointer must keep the pixel under the pointer")
        // At 3× the displayed mapping is three times the fit's scale.
        XCTAssertLessThan(
            zoomedSpace.pixelsPerPoint,
            fitSpace.pixelsPerPoint / 2.9,
            "zoom 3 must show the capture three times the fit's scale")
    }

    // MARK: - The save pipeline is viewport-free (the task's central risk)

    func testAPenDrawnAtThreeTimesSavesAsTheFitPixels() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 100, height: 100))
        let fitEditor = Self.makeEditor(image: image)
        try drawSplitStroke(fitEditor, viewStart: CGPoint(x: 140, y: 100), viewEnd: CGPoint(x: 160, y: 100))
        let fitComposed = try XCTUnwrap(fitEditor.canvas.composedImage())

        let zoomedEditor = Self.makeEditor(image: image)
        // Zoom 3× about (150, 100): the content point (140, 100) sits at
        // view (120, 100) afterwards — the same gesture in content space.
        zoomedEditor.canvas.applyZoom(3, anchoredAt: CGPoint(x: 150, y: 100))
        let viewport = zoomedEditor.canvas.viewportState
        XCTAssertEqual(viewport.zoom, 3)
        try drawSplitStroke(
            zoomedEditor,
            viewStart: viewport.viewPoint(fromFit: CGPoint(x: 140, y: 100), fit: fit, canvas: canvasRect),
            viewEnd: viewport.viewPoint(fromFit: CGPoint(x: 160, y: 100), fit: fit, canvas: canvasRect))

        let zoomedComposed = try XCTUnwrap(zoomedEditor.canvas.composedImage())
        XCTAssertEqual(zoomedComposed.width, 100, "the save is the capture's own pixels, never the zoomed view")
        XCTAssertEqual(zoomedComposed.height, 100)
        XCTAssertEqual(
            tiff(zoomedComposed), tiff(fitComposed),
            "the same stroke drawn at 3× must save exactly the pixels the fit drawing saves")
    }

    func testAPannedPenSavesTheSamePixelsWhenThePanIsReset() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 100, height: 100))
        let fitEditor = Self.makeEditor(image: image)
        try drawSplitStroke(fitEditor, viewStart: CGPoint(x: 140, y: 100), viewEnd: CGPoint(x: 160, y: 100))
        let fitComposed = try XCTUnwrap(fitEditor.canvas.composedImage())

        let pannedEditor = Self.makeEditor(image: image)
        pannedEditor.canvas.pan(byPointerDelta: CGSize(width: 30, height: -20))
        let viewport = pannedEditor.canvas.viewportState
        try drawSplitStroke(
            pannedEditor,
            viewStart: viewport.viewPoint(fromFit: CGPoint(x: 140, y: 100), fit: fit, canvas: canvasRect),
            viewEnd: viewport.viewPoint(fromFit: CGPoint(x: 160, y: 100), fit: fit, canvas: canvasRect))
        // The pan is reset the way ⌘0 does before the save — the mark must be
        // glued to its pixels, not to the panned screen slot.
        pannedEditor.canvas.resetViewport()

        let pannedComposed = try XCTUnwrap(pannedEditor.canvas.composedImage())
        XCTAssertEqual(
            tiff(pannedComposed), tiff(fitComposed),
            "a stroke drawn while panned must not shift when the pan is reset")
    }

    func testABlurDrawnZoomedCoversTheSameImageRectAsTheFit() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 100, height: 100))
        let fitEditor = Self.makeEditor(image: image)
        fitEditor.state.tool = .blur
        try drawSplitStroke(fitEditor, viewStart: CGPoint(x: 140, y: 80), viewEnd: CGPoint(x: 160, y: 120))
        let fitComposed = try XCTUnwrap(fitEditor.canvas.composedImage())

        let zoomedEditor = Self.makeEditor(image: image)
        zoomedEditor.state.tool = .blur
        zoomedEditor.canvas.applyZoom(3, anchoredAt: CGPoint(x: 150, y: 100))
        let viewport = zoomedEditor.canvas.viewportState
        try drawSplitStroke(
            zoomedEditor,
            viewStart: viewport.viewPoint(fromFit: CGPoint(x: 140, y: 80), fit: fit, canvas: canvasRect),
            viewEnd: viewport.viewPoint(fromFit: CGPoint(x: 160, y: 120), fit: fit, canvas: canvasRect))
        let zoomedComposed = try XCTUnwrap(zoomedEditor.canvas.composedImage())
        XCTAssertEqual(
            tiff(zoomedComposed), tiff(fitComposed),
            "a blur patch drawn at 3× must diffuse exactly the image pixels the fit blur diffuses")
    }

    // MARK: - The keyboard and wheel vocabulary (S16: tool keys unchanged)

    func testCommandPlusMinusAndZeroDriveTheViewport() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)

        try pressKey(editor, keyCode: 24, characters: "=", ignoring: "=", modifiers: .command)
        XCTAssertEqual(editor.canvas.viewportState.zoom, EditorViewport.zoomStep, "⌘= zooms in one step")
        try pressKey(editor, keyCode: 24, characters: "+", ignoring: "+", modifiers: .command)
        XCTAssertEqual(editor.canvas.viewportState.zoom, EditorViewport.zoomStep * EditorViewport.zoomStep, accuracy: 0.0001)

        try pressKey(editor, keyCode: 27, characters: "-", ignoring: "-", modifiers: .command)
        XCTAssertEqual(editor.canvas.viewportState.zoom, EditorViewport.zoomStep, accuracy: 0.0001, "⌘− zooms out one step")

        try pressKey(editor, keyCode: 29, characters: "0", ignoring: "0", modifiers: .command)
        XCTAssertEqual(editor.canvas.viewportState, EditorViewport.identity, "⌘0 resets pan and zoom together")
    }

    func testCommandMinusAtTheFitChangesNothing() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try pressKey(editor, keyCode: 27, characters: "-", ignoring: "-", modifiers: .command)
        XCTAssertEqual(editor.canvas.viewportState, EditorViewport.identity, "⌘− at the fit has nothing to zoom out to")
    }

    func testPlainScrollPansButNeverZoomsAndCommandScrollZooms() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 300, height: 100))
        let editor = Self.makeEditor(image: image, size: CGSize(width: 300, height: 200))

        // Plain scroll pans (the image is fitted wide, so the y axis has
        // letterbox slack); it never moves the zoom.
        editor.canvas.scrollWheel(with: try XCTUnwrap(scrollEvent(deltaY: 200, command: false)))
        XCTAssertEqual(editor.canvas.viewportState.zoom, 1, "plain scroll never zooms")
        XCTAssertEqual(
            editor.canvas.viewportState.pan.height, 50, accuracy: 0.5,
            "plain scroll pans the fitted image inside its letterbox slack")

        // ⌘ + scroll zooms, through the same anchored zoom as every other
        // input: 200 precise points are 25 zoom steps of 1.25, past the
        // ceiling.
        editor.canvas.resetViewport()
        editor.canvas.scrollWheel(with: try XCTUnwrap(scrollEvent(deltaY: 200, command: true)))
        XCTAssertEqual(editor.canvas.viewportState.zoom, EditorViewport.maxZoom)
    }

    func testSpaceOpensAPanDragThatDoesNotDraw() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)

        try pressKey(editor, keyCode: 49, characters: " ", ignoring: " ")
        // A pen is armed; the drag must pan, never draw.
        try down(editor, at: CGPoint(x: 100, y: 100))
        try dragged(editor, to: CGPoint(x: 180, y: 140))
        try up(editor, at: CGPoint(x: 180, y: 140))
        try pressKey(editor, keyCode: 49, characters: " ", ignoring: " ") // release

        // The clamp: the fitted x axis (200 in 300) keeps the image at its
        // right edge after an 80 pt rightward drag; the covered y axis is
        // pinned at the fit.
        let display = editor.canvas.viewportState.displayRect(fit: fit, canvas: canvasRect)
        XCTAssertEqual(display.maxX, canvasRect.maxX)
        XCTAssertEqual(display.minY, fit.minY)
        XCTAssertEqual(editor.canvas.viewportState.pan, CGSize(width: 50, height: 0))

        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(composed.width, 100, "the space drag must not have altered the picture")
        XCTAssertEqual(composed.height, 100)
        XCTAssertNil(NSBitmapImageRep(cgImage: composed).firstNonWhitePixel(), "nothing may be painted by a pan drag")
    }

    func testMomentumAfterACommandScrollZoomDoesNotPan() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 300, height: 100))
        let editor = Self.makeEditor(image: image, size: CGSize(width: 300, height: 200))
        editor.window.confineToPrimaryScreen()

        // ⌘ + scroll zooms to the ceiling, anchored at the canvas centre so
        // the zoomed pan sits interior to its clamp on both axes (the
        // synthesized events' default location is off-canvas, which pins the
        // pan at edges and would freeze any kick); then the closing `.ended`
        // event tears the gesture down exactly as the trackpad delivers it.
        let centre = CGPoint(x: 150, y: 100)
        editor.canvas.scrollWheel(with: try XCTUnwrap(
            scrollEvent(deltaY: 200, command: true, scrollPhase: CGScrollPhase.changed, atPoint: centre)))
        editor.canvas.scrollWheel(with: try XCTUnwrap(
            scrollEvent(deltaY: 200, command: true, scrollPhase: CGScrollPhase.ended, atPoint: centre)))
        XCTAssertEqual(editor.canvas.viewportState.zoom, EditorViewport.maxZoom, "the zoom completed")
        let atRest = editor.canvas.viewportState

        // The momentum tail arrives with no ⌘ and the gesture already gone:
        // raw feeding would kick the viewport right after the zoom finished.
        // The zoom's clamp glues the covered y axis to the canvas edge its
        // anchor pinned, so the kick is tested away from that glued edge —
        // the one direction the clamp allows to move.
        let forward = try XCTUnwrap(
            scrollEvent(deltaY: -400, command: false, momentumPhase: CGMomentumPhase.continued))
        editor.canvas.scrollWheel(with: forward)
        XCTAssertEqual(
            editor.canvas.viewportState, atRest,
            "the momentum tail that follows the zoom's .ended belongs to no live gesture and must not kick the viewport")
    }

    // MARK: - The viewport is relative to the current fit

    func testAWindowResizeResetsTheViewportToTheNewFit() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        editor.canvas.applyZoom(2, anchoredAt: CGPoint(x: 150, y: 100))
        XCTAssertNotEqual(editor.canvas.viewportState, EditorViewport.identity)

        editor.canvas.setFrameSize(CGSize(width: 400, height: 300))
        XCTAssertEqual(
            editor.canvas.viewportState, EditorViewport.identity,
            "the fit changed, so the zoomed view is stale — ⌘0's state is the only safe ground to stand on")
    }

    func testApplyingACropResetsTheViewport() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        editor.canvas.applyZoom(3, anchoredAt: CGPoint(x: 150, y: 100))
        XCTAssertNotEqual(editor.canvas.viewportState, EditorViewport.identity)

        // Stage and confirm a crop the way the staged-crop tests do — the
        // canvas is flipped, so the drag's interior endpoints below are what
        // the marquee spans.
        editor.state.selectCrop()
        try down(editor, at: CGPoint(x: 50, y: 60))
        try dragged(editor, to: CGPoint(x: 150, y: 150))
        try up(editor, at: CGPoint(x: 150, y: 150))
        try pressKey(editor, keyCode: 36, characters: "\r", ignoring: "\r")
        XCTAssertNotEqual(try XCTUnwrap(editor.canvas.composedImage()).width, 100, "the crop must have applied")

        XCTAssertEqual(
            editor.canvas.viewportState, EditorViewport.identity,
            "a new fit is a new ground state: the viewport resets when a crop applies")
    }

    // MARK: - S16: the tool keys never change

    func testToolKeysKeepWorkingWhileZoomedAndSpaceNeverArmsOne() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        editor.canvas.applyZoom(3, anchoredAt: CGPoint(x: 150, y: 100))

        try pressKey(editor, keyCode: 35, characters: "p", ignoring: "p")
        XCTAssertEqual(editor.state.tool, .pen, "the tool keys must resolve exactly as before at any zoom")

        try pressKey(editor, keyCode: 49, characters: " ", ignoring: " ")
        XCTAssertEqual(editor.state.tool, .pen, "space is the pan key: it never arms or switches a tool")
        XCTAssertEqual(
            editor.canvas.viewportState.zoom, 3,
            "space press must not touch the viewport either")
    }
}

/// Pixel probe for the pan-drag test: the first pixel that is not white, in
/// the image's own coordinate space.
private extension NSBitmapImageRep {
    func firstNonWhitePixel() -> (x: Int, y: Int)? {
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                guard let colour = colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if colour.greenComponent < 0.92 || colour.blueComponent < 0.92 { return (x, y) }
            }
        }
        return nil
    }
}
