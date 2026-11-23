import AppKit
import XCTest
@testable import Stare
import StareCore

/// The remembered rectangle and the loupe at the view layer (S11, T2b slice
/// B): pressing `⇧S` again pre-loads the last confirmed area, a plain
/// `Return` confirms and captures it with no drag, starting a drag replaces
/// it, and deactivation clears it. The loupe itself is pixels — its geometry
/// is pinned in `AreaCaptureLoupeTests`; here only the wiring that decides
/// whether it can paint at all is exercised, plus a smoke render of the
/// drawing path. The windows these tests open are confined to the primary
/// screen (`PrimaryScreenTestWindow`), never the user's other monitors.
@MainActor
final class AreaCaptureLoupeViewTests: XCTestCase {
    private let size = CGSize(width: 900, height: 600)

    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    /// A plain overlay canvas wired the way the controller wires a display:
    /// the freeze ask exists (a no-op here), which is what marks the canvas
    /// as one that remembers its confirmed areas. Board canvases never get
    /// this wiring, so they never remember.
    private func makeView() -> OverlayView {
        let view = OverlayView(
            frame: CGRect(origin: .zero, size: size),
            state: EditorState(), onEscape: {})
        view.onAreaSelectionFrame = {}
        return view
    }

    private func mouseEvent(
        _ type: NSEvent.EventType, at viewPoint: CGPoint, window: NSWindow
    ) -> NSEvent {
        // The events speak window coordinates (bottom-left origin); the
        // flipped view converts them, so tests state points in view space.
        let windowPoint = CGPoint(x: viewPoint.x, y: size.height - viewPoint.y)
        return NSEvent.mouseEvent(
            with: type, location: windowPoint,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1,
            clickCount: 1, pressure: 1)!
    }

    private func returnKey() -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
    }

    private func escapeKey() -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
    }

    private func dragRect(
        _ view: OverlayView, from: CGPoint, to: CGPoint, window: NSWindow
    ) {
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: from, window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: to, window: window))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: to, window: window))
    }

    /// A primary-screen-confined window hosting `view`, ordered front and
    /// ordered out again when the test ends — the pattern L9 fixed for the
    /// whole suite (never a secondary monitor).
    private func hostWindow(_ view: NSView) throws -> NSWindow {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen to host the probe")
        let window = NSWindow(
            contentRect: try XCTUnwrap(
                PrimaryScreenTestWindow.frame(for: size),
                "the primary screen cannot host the probe"),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        return window
    }

    // MARK: Return before any area exists

    func testReturnWithoutARememberedRectangleCapturesNothing() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }
        var captures: [CGRect] = []
        view.onCaptureRequest = { captures.append($0 ?? .zero) }

        // Without a remembered rectangle the pre-loaded marquee never exists:
        // `⇧S` arms an empty drag and `Return` must not capture it.
        view.beginAreaSelection()
        view.keyDown(with: returnKey())
        XCTAssertTrue(captures.isEmpty)

        // And `Return` outside an area drag keeps today's fall-through.
        view.keyDown(with: returnKey())
        XCTAssertTrue(captures.isEmpty)
    }

    // MARK: Pre-load, confirm, replace

    func testAConfirmedDragIsRememberedAndReturnCapturesItWithNoDrag() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }
        var captures: [CGRect] = []
        view.onCaptureRequest = { captures.append($0 ?? .zero) }

        view.beginAreaSelection()
        dragRect(view, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300), window: window)
        XCTAssertEqual(captures, [CGRect(x: 100, y: 100, width: 300, height: 200)])

        // `⇧S` again: the confirmed area is the starting marquee, and a plain
        // `Return` captures it — no dragging needed.
        view.beginAreaSelection()
        view.keyDown(with: returnKey())
        XCTAssertEqual(captures.count, 2)
        XCTAssertEqual(captures[1], captures[0], "the remembered rectangle, confirmed")
    }

    func testStartingADragReplacesTheRememberedRectangle() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }
        var captures: [CGRect] = []
        view.onCaptureRequest = { captures.append($0 ?? .zero) }

        view.beginAreaSelection()
        dragRect(view, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300), window: window)

        view.beginAreaSelection()
        dragRect(view, from: CGPoint(x: 500, y: 500), to: CGPoint(x: 620, y: 570), window: window)
        XCTAssertEqual(captures[1], CGRect(x: 500, y: 500, width: 120, height: 70),
            "the drag's own rectangle, not the pre-loaded one")

        view.beginAreaSelection()
        view.keyDown(with: returnKey())
        XCTAssertEqual(captures.count, 3)
        XCTAssertEqual(captures[2], captures[1], "the newest confirmation is the one remembered")
    }

    func testReturnDoesNotConfirmWhileADragIsRunning() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }
        var captures: [CGRect] = []
        view.onCaptureRequest = { captures.append($0 ?? .zero) }

        view.beginAreaSelection()
        dragRect(view, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300), window: window)

        view.beginAreaSelection()
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 200, y: 200), window: window))
        view.keyDown(with: returnKey())
        XCTAssertEqual(captures.count, 1, "mid-drag, `Return` keeps today's meaning")

        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 300, y: 300), window: window))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 300, y: 300), window: window))
        XCTAssertEqual(
            captures,
            [CGRect(x: 100, y: 100, width: 300, height: 200), CGRect(x: 200, y: 200, width: 100, height: 100)],
            "the drag itself still finishes exactly as before")
    }

    // MARK: Cancel and deactivate

    func testEscCancelsThePreloadedMarqueeWithoutCapturing() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }
        var captures: [CGRect] = []
        view.onCaptureRequest = { captures.append($0 ?? .zero) }

        view.beginAreaSelection()
        dragRect(view, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300), window: window)

        view.beginAreaSelection()
        view.keyDown(with: escapeKey())
        view.keyDown(with: returnKey())
        XCTAssertEqual(captures.count, 1, "Esc cancelled the armed marquee; Return afterwards captures nothing")
    }

    func testDeactivationClearsTheMemory() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }
        var captures: [CGRect] = []
        view.onCaptureRequest = { captures.append($0 ?? .zero) }

        view.beginAreaSelection()
        dragRect(view, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300), window: window)
        XCTAssertEqual(captures.count, 1)

        // `clear()` is the leaving-the-overlay path: deactivate runs clearAll.
        view.clear()
        view.beginAreaSelection()
        view.keyDown(with: returnKey())
        XCTAssertEqual(captures.count, 1, "the memory is session-scoped and dies with the overlay")
    }

    // MARK: The whiteboard gains nothing

    func testACanvasWithoutTheFreezeWiringRemembersNothing() throws {
        // A board canvas's wiring: `onCaptureRequest` exists, the freeze ask
        // does not. Its area drag must capture as always and never remember.
        let view = OverlayView(
            frame: CGRect(origin: .zero, size: size),
            state: EditorState(), onEscape: {})
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }
        var captures: [CGRect] = []
        view.onCaptureRequest = { captures.append($0 ?? .zero) }

        view.beginAreaSelection()
        dragRect(view, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300), window: window)
        XCTAssertEqual(captures.count, 1, "the board's own area capture is untouched")

        view.beginAreaSelection()
        view.keyDown(with: returnKey())
        XCTAssertEqual(captures.count, 1, "no remembered rectangle on the board path")
    }

    // MARK: The loupe's paint path

    func testTheLoupeRendersOverTheFrozenFrameWithoutFailing() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        view.landAreaFrame(makeImage(width: 1800, height: 1200))
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 450, y: 300), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 460, y: 310), window: window))

        // The loupe, its border and its crosshair all live in this paint pass;
        // the pixel result is the manual check (real pixels only).
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        view.cacheDisplay(in: view.bounds, to: rep)
        XCTAssertNotNil(rep.cgImage)
    }
}
