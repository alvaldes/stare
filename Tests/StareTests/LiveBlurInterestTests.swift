import AppKit
import XCTest
@testable import Stare
import StareCore

/// Live blur interest (T5/S1): blur marks paint the screen through
/// `LiveFrameSource`, and the source only captures while some display has a
/// visible blur mark. Session *replacement* (the restore path on re-entry and
/// after a relaunch) must report blur interest exactly like incremental
/// drawing does, otherwise the restored marks paint the neutral fallback
/// frame after frame until a new blur is drawn.
@MainActor
final class LiveBlurInterestTests: XCTestCase {
    private let size = CGSize(width: 900, height: 600)

    private func blurStroke(at rect: CGRect) -> Stroke {
        Stroke(tool: .blur, ink: .blue, points: [rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)])
    }

    private func makeView() -> OverlayView {
        let state = EditorState()
        state.tool = .blur
        return OverlayView(frame: CGRect(origin: .zero, size: size), state: state, onEscape: {})
    }

    private func dragBlurMark(on view: OverlayView, window: NSWindow) {
        func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: CGPoint(x: point.x, y: size.height - point.y),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 300, y: 200)))
        view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 450, y: 300)))
        view.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 600, y: 400)))
    }

    /// RED for T5/S1: the restore paths assign the whole session
    /// (`canvas.view.session = restored`), bypassing every incremental
    /// mutation path. The interest report has to funnel through the session
    /// property itself.
    func testReplacingTheSessionWithBlurMarksReportsFrameInterest() {
        let view = makeView()
        var interestReports = 0
        view.onBlurMarksChanged = { interestReports += 1 }

        view.session = DrawingSession.restored(
            strokes: [blurStroke(at: CGRect(x: 300, y: 200, width: 300, height: 200))])

        XCTAssertTrue(view.hasLiveBlurMarks)
        XCTAssertGreaterThan(
            interestReports, 0,
            "a restored session holding blur marks must re-arm the frame source")
    }

    /// PRESERVE: drawing a blur mark the usual way still reports interest —
    /// the fix must not silence the incremental paths.
    func testDrawingABlurMarkStillReportsFrameInterest() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the probe shows a window, so it needs a screen")
        let window = NSWindow(
            contentRect: try XCTUnwrap(
                PrimaryScreenTestWindow.frame(for: size),
                "the primary screen cannot host the probe"),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let view = makeView()
        window.contentView = view
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        var interestReports = 0
        view.onBlurMarksChanged = { interestReports += 1 }
        dragBlurMark(on: view, window: window)

        XCTAssertTrue(view.hasLiveBlurMarks)
        XCTAssertGreaterThan(interestReports, 0)
    }
}
