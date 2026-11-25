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
    private func makeView(state: EditorState = EditorState()) -> OverlayView {
        let view = OverlayView(
            frame: CGRect(origin: .zero, size: size),
            state: state, onEscape: {})
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

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    // MARK: The remembered rectangle is visible and Return captures it

    /// Symptom report: after a capture, the second ⇧S shows nothing framed and
    /// Return does nothing. This arms the view with a remembered rect through
    /// a real drag, then asserts the preloaded marquee is actually drawn (the
    /// shroud covers everything but the remembered rect, and its border is
    /// stroked) and that a real Return key event captures exactly that rect.
    func testThePreloadedMarqueeIsDrawnAndReturnCapturesExactlyThatRect() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }
        var captures: [CGRect] = []
        view.onCaptureRequest = { captures.append($0 ?? .zero) }

        view.beginAreaSelection()
        dragRect(view, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300), window: window)
        XCTAssertEqual(captures.count, 1)

        // ⇧S again: the remembered area must be on screen already, no drag.
        view.beginAreaSelection()
        let rep = try render(view)

        // Inside the remembered rect: clear — the shroud's even-odd hole.
        let inside = try XCTUnwrap(rep.colorAt(x: 250, y: 200))
        XCTAssertLessThan(inside.alphaComponent, 0.05,
            "the preloaded marquee must be drawn: the shroud opens a hole over the remembered rect")

        // Far outside it: the armed shroud (the same even-odd shroud a drag
        // paints, since the preloaded rect exists).
        let outside = try XCTUnwrap(rep.colorAt(x: 50, y: 550))
        XCTAssertEqual(outside.alphaComponent, 0.32, accuracy: 0.08,
            "the armed drag's shroud covers the view outside the remembered rect")

        // The marquee's own border stroke on the rect's left edge.
        let border = try XCTUnwrap(rep.colorAt(x: 100, y: 200))
        XCTAssertGreaterThan(border.alphaComponent, 0.5,
            "the preloaded marquee's border must be visible on screen")

        // Return captures exactly the remembered rectangle.
        view.keyDown(with: returnKey())
        XCTAssertEqual(captures.count, 2, "Return confirms the preloaded marquee")
        XCTAssertEqual(captures[1], CGRect(x: 100, y: 100, width: 300, height: 200),
            "exactly the rectangle the user saw framed")
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

    /// The loupe really paints during a drag — a bitmap assertion, not just a
    /// smoke render: the frozen frame here is magenta (min channel 0), so the
    /// loupe's bright-first ring and crosshair are the only near-white pixels
    /// in their neighbourhoods. Geometry: the last drag point (460, 310) in
    /// the 900×600 view fits below-right, so the loupe's frame is
    /// (484, 334, 120, 120) (`AreaCaptureLoupeTests` pins the plan).
    func testTheLoupePaintsItsRingAndCrosshairDuringADrag() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        view.landAreaFrame(makeImage(width: 1800, height: 1200))
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 450, y: 300), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 460, y: 310), window: window))

        let rep = try render(view)
        // The ring's top edge runs across the loupe frame's top.
        XCTAssertTrue(
            hasRingPixel(rep, near: CGPoint(x: 544, y: 335)),
            "the loupe's ring must paint during a drag")
        // The crosshair marks the pixel being chosen at the loupe's centre.
        XCTAssertTrue(
            hasRingPixel(rep, near: CGPoint(x: 544, y: 394)),
            "the loupe's crosshair must mark the pixel being chosen")
    }

    /// Whether the bitmap carries a near-white chrome pixel within `radius`
    /// points of `point`: over a magenta frozen frame nothing but the loupe's
    /// chrome (and the guides) can be nearly white everywhere.
    private func hasRingPixel(_ rep: NSBitmapImageRep, near point: CGPoint, radius: CGFloat = 3) -> Bool {
        for x in Int(point.x - radius)...Int(point.x + radius) {
            for y in Int(point.y - radius)...Int(point.y + radius) {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                    let color = rep.colorAt(x: x, y: y)
                else { continue }
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.6 { return true }
            }
        }
        return false
    }

    /// `showAreaLoupe` off, through a real preferences model: the ring and the
    /// crosshair vanish, while the guides — the other piece of chrome — keep
    /// painting, so turning one off removes EXACTLY that piece.
    func testTurningTheLoupeOffRemovesOnlyTheLoupe() throws {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.capture.showAreaLoupe = false
        let state = EditorState(preferences: model)
        let view = makeView(state: state)
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }

        view.beginAreaSelection()
        view.landAreaFrame(makeImage(width: 1800, height: 1200))
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 450, y: 300), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 460, y: 310), window: window))

        let rep = try render(view)
        XCTAssertFalse(
            hasRingPixel(rep, near: CGPoint(x: 544, y: 335)),
            "with the preference off, no loupe ring paints where one did")
        XCTAssertFalse(
            hasRingPixel(rep, near: CGPoint(x: 544, y: 394)),
            "with the preference off, no loupe crosshair paints where one did")
        // The guides survive: the drag rect (450, 300)–(460, 310) grows a
        // right-edge rule at x = 460 running below it, and its dim white
        // dotted top stroke clears the 0.45 guide threshold there.
        XCTAssertTrue(
            hasGuideDot(rep, near: CGPoint(x: 460, y: 350)),
            "turning the loupe off must not take the guides down with it")
    }

    /// The guides' dimmer chrome threshold (α 0.55 white tops out ≈0.55 in
    /// the min channel); the loupe's ring is brighter on purpose.
    private func hasGuideDot(_ rep: NSBitmapImageRep, near point: CGPoint, radius: CGFloat = 3) -> Bool {
        for x in Int(point.x - radius)...Int(point.x + radius) {
            for y in Int(point.y - radius)...Int(point.y + radius) {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                    let color = rep.colorAt(x: x, y: y)
                else { continue }
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.45 { return true }
            }
        }
        return false
    }
}

/// The same in-memory store the settings render tests use, so the probe never
/// touches the user's real preferences.
private final class InMemoryPreferenceStore: PreferenceStore {
    private var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
