import AppKit
import XCTest
@testable import Stare
@testable import StareCore

/// The OCR selection surface (T5/S7): its own lightweight window — never a
/// rewired drawing overlay — that lives on one display only (the pointer's),
/// dismisses on Escape, and delivers the chosen rectangle in screen
/// coordinates to its owner. Every window a test shows sits on the primary
/// screen through `PrimaryScreenTestWindow` and is closed by the test.
@MainActor
final class TextSelectionWindowTests: XCTestCase {
    private var windows: [TextSelectionWindow] = []
    private var hints: [TextRecognitionHintWindow] = []

    override func tearDown() {
        for window in windows {
            window.closeWithoutCallbacks()
        }
        windows = []
        for hint in hints {
            hint.closeSelf()
        }
        hints = []
        super.tearDown()
    }

    // MARK: - Choosing the pointer's display

    func testThePureScreenChoiceFollowsThePointerAndRefusesEverythingElse() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1200, height: 800)
        // Two side-by-side displays: a pointer in the right one chooses the
        // right one — never the primary by default, never both.
        XCTAssertEqual(
            TextSelectionWindow.screenFrame(containing: CGPoint(x: 1500, y: 400), in: [left, right]),
            right)
        XCTAssertEqual(
            TextSelectionWindow.screenFrame(containing: CGPoint(x: 500, y: 400), in: [left, right]),
            left)
        // A pointer between displays (the dead corner) refuses the gesture
        // instead of guessing a display.
        XCTAssertNil(TextSelectionWindow.screenFrame(containing: CGPoint(x: 1000, y: -5), in: [left, right]))
        XCTAssertNil(TextSelectionWindow.screenFrame(containing: CGPoint(x: 3000, y: 0), in: [left, right]))
        // And without any display at all there is nothing to open on.
        XCTAssertNil(TextSelectionWindow.screenFrame(containing: CGPoint(x: 0, y: 0), in: []))
    }

    // MARK: - The window shape

    func testTheSelectionSurfaceIsItsOwnLightweightWindowOnOneDisplay() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the shape needs a real display")
        let primary = try XCTUnwrap(NSScreen.screens.first)
        let window = makeWindow(pointerFrame: primary.frame)
        XCTAssertEqual(window.styleMask, [.borderless, .nonactivatingPanel])
        XCTAssertEqual(window.level, .floating)
        XCTAssertEqual(window.frame.width, primary.frame.width, accuracy: 0.5)
        XCTAssertEqual(window.frame.height, primary.frame.height, accuracy: 0.5)
        XCTAssertEqual(window.frame.minX, primary.frame.minX, accuracy: 0.5)
        XCTAssertEqual(window.frame.minY, primary.frame.minY, accuracy: 0.5)
        XCTAssertFalse(window.canBecomeKey, "the surface never steals typing focus")
        XCTAssertFalse(window.hidesOnDeactivate)
        for screen in NSScreen.screens.dropFirst() {
            XCTAssertFalse(
                window.frame.intersects(screen.frame),
                "a selection surface injected with one display must never reach another: \(window.frame)")
        }
    }

    // MARK: - Escape, and only a real drag, finishes the gesture

    func testEscapeDismissesWithoutSelectingAnything() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the shape needs a real display")
        let frame = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: CGSize(width: 600, height: 400)))
        let window = makeWindow(pointerFrame: frame)
        var cancelled = 0
        window.onCancelled = { cancelled += 1 }
        var selected: [CGRect] = []
        window.onSelected = { selected.append($0) }

        XCTAssertTrue(window.handleEscapeKey())
        XCTAssertTrue(window.isDismissed)
        XCTAssertEqual(cancelled, 1)
        XCTAssertTrue(selected.isEmpty, "Escape never delivers a rectangle")

        // A second Escape is a no-op: the gesture is already over.
        XCTAssertFalse(window.handleEscapeKey())
        XCTAssertEqual(cancelled, 1)
    }

    func testADragDeliversItsRectangleInScreenCoordinates() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the shape needs a real display")
        let frame = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: CGSize(width: 600, height: 400)))
        let window = makeWindow(pointerFrame: frame)
        var selected: [CGRect] = []
        window.onSelected = { selected.append($0) }
        var cancelled = 0
        window.onCancelled = { cancelled += 1 }

        let view = try XCTUnwrap(window.surfaceView)
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 20, y: 20), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 120, y: 90), window: window))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 120, y: 90), window: window))

        XCTAssertEqual(selected, [CGRect(x: frame.minX + 20, y: frame.minY + 20, width: 100, height: 70)])
        XCTAssertEqual(cancelled, 0)
        XCTAssertTrue(window.isDismissed, "the gesture ends with the drag")
    }

    func testAStrayClickDismissesWithoutSelecting() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the shape needs a real display")
        let frame = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: CGSize(width: 600, height: 400)))
        let window = makeWindow(pointerFrame: frame)
        var selected: [CGRect] = []
        window.onSelected = { selected.append($0) }
        var cancelled = 0
        window.onCancelled = { cancelled += 1 }

        let view = try XCTUnwrap(window.surfaceView)
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 40, y: 40), window: window))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 41, y: 41), window: window))

        XCTAssertTrue(selected.isEmpty, "a stray click is not a selection")
        XCTAssertEqual(cancelled, 1)
        XCTAssertTrue(window.isDismissed)
    }

    func testShiftForcesASquareSelection() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the shape needs a real display")
        let frame = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: CGSize(width: 600, height: 400)))
        let window = makeWindow(pointerFrame: frame)
        var selected: [CGRect] = []
        window.onSelected = { selected.append($0) }

        let view = try XCTUnwrap(window.surfaceView)
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 10, y: 10), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 210, y: 80), window: window, shift: true))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 210, y: 80), window: window, shift: true))

        let rect = try XCTUnwrap(selected.first)
        XCTAssertEqual(rect.width, rect.height, accuracy: 0.5, "⇧ forces a square")
    }

    // MARK: - The hint surface

    func testTheHintSurfaceSitsOnTheScreenItIsGivenAndLeavesOnDemand() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the hint needs a real display")
        let primary = try XCTUnwrap(NSScreen.screens.first)
        let hint = TextRecognitionHintWindow(
            screenFrame: primary.frame,
            message: TextRecognitionFeedback.nothingFound.title,
            duration: 60)
        hints.append(hint)
        hint.orderFrontRegardless()
        // Centred on, and wholly inside, the display it was given.
        XCTAssertTrue(primary.frame.contains(hint.frame), "\(hint.frame) outside \(primary.frame)")
        for screen in NSScreen.screens.dropFirst() {
            XCTAssertFalse(hint.frame.intersects(screen.frame))
        }
        hint.closeSelf()
        XCTAssertTrue(hint.isDismissed)
    }

    // MARK: - Helpers

    private func makeWindow(pointerFrame: CGRect) -> TextSelectionWindow {
        let window = TextSelectionWindow(pointerFrame: pointerFrame)
        windows.append(window)
        return window
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        at point: CGPoint,
        window: NSWindow?,
        shift: Bool = false
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: shift ? [.shift] : [],
            timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1)!
    }
}
