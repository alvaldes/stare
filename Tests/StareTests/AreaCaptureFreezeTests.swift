import AppKit
import XCTest
@testable import Stare
import StareCore

/// The area drag's frozen frame (S11, T2b slice A): the instant `⇧S` starts a
/// drag the controller captures the display once and the view paints it as
/// the drag's base until the drag ends. Released on capture, on a stray
/// click, on `Esc`, on leaving the overlay and on deactivation. The windows
/// these tests open are confined to the primary screen
/// (`PrimaryScreenTestWindow`), never the user's other monitors.
@MainActor
final class AreaCaptureFreezeTests: XCTestCase {
    private let size = CGSize(width: 900, height: 600)

    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    private func makeView() -> OverlayView {
        OverlayView(
            frame: CGRect(origin: .zero, size: size),
            state: EditorState(), onEscape: {})
    }

    private func mouseEvent(
        _ type: NSEvent.EventType, at point: CGPoint,
        window: NSWindow? = nil, flags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point,
            modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 1,
            clickCount: 1, pressure: 1)!
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

    // MARK: Lifecycle

    func testTheFrameLandingBecomesTheDragBase() {
        let view = makeView()
        let image = makeImage(width: 1800, height: 1200)
        XCTAssertNil(view.frozenAreaBase)

        view.beginAreaSelection()
        XCTAssertNil(view.frozenAreaBase, "the base paints only once the frame lands")

        view.landAreaFrame(image)
        XCTAssertEqual(view.frozenAreaBase?.width, 1800)
        XCTAssertEqual(view.frozenAreaBase?.height, 1200)
    }

    func testAFrameLandingAfterTheDragEndedIsNeverPainted() {
        let view = makeView()
        let image = makeImage(width: 1800, height: 1200)

        view.landAreaFrame(image)
        XCTAssertNil(view.frozenAreaBase, "no drag, no base")

        view.beginAreaSelection()
        view.releaseAreaFrame() // the drag ended: capture, cancel or Esc
        view.landAreaFrame(image)
        XCTAssertNil(view.frozenAreaBase, "a stale frame must never become the base")
    }

    func testACaptureFailureReleasesThePendingFreeze() {
        let view = makeView()

        view.beginAreaSelection()
        view.landAreaFrame(nil) // no permission or unavailable display

        XCTAssertEqual(view.areaFrame.phase, .idle)
        XCTAssertNil(view.frozenAreaBase, "the drag runs live, as before the freeze")
    }

    func testCancelReleasesTheFrozenBaseWithoutClearingMarks() {
        let view = makeView()
        var clears = 0
        view.onClearMarks = { clears += 1 }
        let image = makeImage(width: 1800, height: 1200)

        view.beginAreaSelection()
        view.landAreaFrame(image)

        let esc = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 53)!
        view.keyDown(with: esc)

        XCTAssertNil(view.frozenAreaBase, "Esc ends the drag and releases the base")
        XCTAssertEqual(view.areaFrame.phase, .idle)
        XCTAssertEqual(clears, 0, "Esc during a drag only cancels the drag")
    }

    func testAClearReleasesTheFrozenBase() {
        // `clear()` is the leaving-the-overlay path: deactivate runs clearAll,
        // which clears every canvas.
        let view = makeView()
        let image = makeImage(width: 1800, height: 1200)

        view.beginAreaSelection()
        view.landAreaFrame(image)
        view.clear()

        XCTAssertEqual(view.areaFrame.phase, .idle)
        XCTAssertNil(view.frozenAreaBase)
    }

    // MARK: Drag end

    func testAFinishedDragHandsTheFrozenBaseToTheCaptureThenReleasesIt() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }
        var capturedAreas: [CGRect] = []
        var baseAtCapture: CGSize?
        view.onCaptureRequest = { area in
            capturedAreas.append(area ?? .zero)
            baseAtCapture = view.frozenAreaBase.map { CGSize(width: $0.width, height: $0.height) }
        }
        let image = makeImage(width: 1800, height: 1200)

        view.beginAreaSelection()
        view.landAreaFrame(image)
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 400, y: 300), window: window))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 400, y: 300), window: window))

        XCTAssertEqual(capturedAreas.count, 1)
        XCTAssertEqual(capturedAreas.first?.width, 300)
        XCTAssertEqual(
            baseAtCapture, CGSize(width: 1800, height: 1200),
            "the capture composes over the frozen base — the pixels the user framed")
        XCTAssertEqual(view.areaFrame.phase, .idle)
        XCTAssertNil(view.frozenAreaBase, "released on capture")
    }

    func testAStrayClickDragReleasesTheBaseWithoutCapturing() throws {
        let view = makeView()
        let window = try hostWindow(view)
        defer { window.orderOut(nil) }
        var captureRequests = 0
        view.onCaptureRequest = { _ in captureRequests += 1 }

        view.beginAreaSelection()
        view.landAreaFrame(makeImage(width: 1800, height: 1200))
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 102, y: 102), window: window))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 102, y: 102), window: window))

        XCTAssertEqual(captureRequests, 0, "a drag below the minimum is a stray click")
        XCTAssertEqual(view.areaFrame.phase, .idle)
        XCTAssertNil(view.frozenAreaBase, "the base never outlives the drag")
    }

    // MARK: Re-arm inside the capture's latency

    func testAFrameLandedAfterEscAndReArmNeverBecomesTheNewDragBase() {
        let view = makeView()
        let firstFrame = makeImage(width: 1800, height: 1200)
        let secondFrame = makeImage(width: 1800, height: 1200)

        view.beginAreaSelection() // arm: the drag asks for its frame
        view.releaseAreaFrame() // Esc
        view.beginAreaSelection() // re-arm while the first capture is still in flight
        view.landAreaFrame(firstFrame) // the first drag's frame lands

        XCTAssertNil(view.frozenAreaBase,
            "the first drag's frame must never become the second drag's base")

        view.landAreaFrame(secondFrame) // the second drag's own frame lands
        XCTAssertEqual(
            view.frozenAreaBase.map { CGSize(width: $0.width, height: $0.height) },
            CGSize(width: 1800, height: 1200),
            "the second drag freezes on its own frame")
    }

    // MARK: Blur over the frozen frame

    func testBlurMarksSourceFromTheFrozenFrameWhileItHolds() {
        let view = makeView()
        let stroke = Stroke(
            tool: .blur, ink: .blue,
            points: [CGPoint(x: 300, y: 200), CGPoint(x: 600, y: 400)])
        XCTAssertNil(view.blurSource(for: stroke), "no frozen frame and no live source yet")

        view.beginAreaSelection()
        view.landAreaFrame(makeImage(width: 1800, height: 1200))

        let source = view.blurSource(for: stroke)
        XCTAssertEqual(source?.image.width, 1800, "the blur reads the frozen frame's pixels")
        XCTAssertEqual(
            source?.pixelsPerPoint, 2,
            "the frozen frame is a native capture: its scale is pixels per point")
    }
}
