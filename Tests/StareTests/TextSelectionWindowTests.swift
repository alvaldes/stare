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
        // The surface must take key focus without activating the app — that
        // is how Escape reaches an accessory app that is never frontmost.
        // The nonactivating panel style keeps the activation side away.
        XCTAssertTrue(window.canBecomeKey,
            "an invisible-to-keys surface leaves the gesture with no Escape")
        XCTAssertFalse(window.canBecomeMain)
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

    func testOtherKeysDuringTheGestureChangeNothing() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the shape needs a real display")
        let frame = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: CGSize(width: 600, height: 400)))
        let window = makeWindow(pointerFrame: frame)
        var cancelled = 0
        var selected: [CGRect] = []
        window.onCancelled = { cancelled += 1 }
        window.onSelected = { selected.append($0) }

        // A key that is not Escape arrives through the key panel and is
        // swallowed quietly: the gesture stays alive, nothing is cancelled.
        window.keyDown(with: mouseKeyEvent(.keyDown, keyCode: 0, at: .zero, window: window))
        XCTAssertFalse(window.isDismissed)
        XCTAssertEqual(cancelled, 0)
        XCTAssertTrue(selected.isEmpty)
        // Escape still ends it through the same channel.
        window.keyDown(with: mouseKeyEvent(.keyDown, keyCode: 53, at: .zero, window: window))
        XCTAssertTrue(window.isDismissed)
        XCTAssertEqual(cancelled, 1)
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

    // MARK: - A press is visible immediately

    func testTheSurfaceIsVisibleBeforeAnyDragAndSaysDragToSelect() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the shape needs a real display")
        let frame = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: CGSize(width: 600, height: 400)))
        let window = makeWindow(pointerFrame: frame)
        // The first visible moment of the gesture is not the drag: the
        // surface opens inviting, with the veil and the instruction up.
        XCTAssertEqual(window.phase, .inviting)
        let view = try XCTUnwrap(window.surfaceView)
        XCTAssertEqual(view.phase, .inviting)
        let instruction = TextRecognitionSurfaceCopy.instruction(for: .inviting)
        XCTAssertFalse(instruction.isEmpty, "the inviting state must carry the drag-to-select instruction")
        XCTAssertTrue(window.acceptsGestures, "the inviting surface takes mouse input for the drag")
    }

    func testTheSurfaceBecomesKeySoEscapeCanArriveWithoutActivation() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the shape needs a real display")
        let frame = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: CGSize(width: 600, height: 400)))
        let window = makeWindow(pointerFrame: frame)
        window.orderFrontRegardless()
        window.makeKey()
        // A key-capable nonactivating panel is the dismissal channel: keys
        // route to this app's panel while nothing activates.
        XCTAssertEqual(NSApp.keyWindow, window, "the surface must hold key focus so Escape arrives")
        // Escape through that channel still ends the gesture cancelled.
        var cancelled = 0
        window.onCancelled = { cancelled += 1 }
        XCTAssertTrue(window.handleEscapeKey())
        XCTAssertEqual(cancelled, 1)
        XCTAssertNil(NSApp.keyWindow)
    }

    // MARK: - The surface's cursor (T5 follow-up): crosshair while up, restored after

    func testEveryExitRestoresThePreviousCursorAfterTheCrosshair() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the cursor needs a real display")
        let frame = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: CGSize(width: 600, height: 400)))

        // Escape.
        do {
            let window = makeWindow(pointerFrame: frame)
            let baseline = NSCursor.current
            window.orderFrontRegardless()
            window.makeKey()
            XCTAssertTrue(sameCursor(NSCursor.current, NSCursor.crosshair),
                "the OCR surface shows the area capture's crosshair from the moment it appears")
            XCTAssertTrue(window.handleEscapeKey())
            XCTAssertTrue(sameCursor(NSCursor.current, baseline), "Escape restores the previous cursor")
        }
        // Commit.
        do {
            let window = makeWindow(pointerFrame: frame)
            let baseline = NSCursor.current
            window.orderFrontRegardless()
            window.makeKey()
            XCTAssertTrue(sameCursor(NSCursor.current, NSCursor.crosshair))
            let view = try XCTUnwrap(window.surfaceView)
            view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 20, y: 20), window: window))
            view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 120, y: 90), window: window))
            view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 120, y: 90), window: window))
            XCTAssertTrue(window.isDismissed)
            XCTAssertTrue(sameCursor(NSCursor.current, baseline), "a finished selection restores the previous cursor")
        }
        // Idle timeout — the machine refuses it only mid-drag, so it ends the
        // inviting state.
        do {
            let window = makeWindow(pointerFrame: frame)
            let baseline = NSCursor.current
            window.orderFrontRegardless()
            window.makeKey()
            XCTAssertTrue(sameCursor(NSCursor.current, NSCursor.crosshair))
            window.handleIdleTimeout()
            XCTAssertTrue(window.isDismissed)
            XCTAssertTrue(sameCursor(NSCursor.current, baseline), "the idle timeout restores the previous cursor")
        }
        // A second ⌥⇧O while the surface is up: a visible cancel.
        do {
            let window = makeWindow(pointerFrame: frame)
            let baseline = NSCursor.current
            window.orderFrontRegardless()
            window.makeKey()
            XCTAssertTrue(sameCursor(NSCursor.current, NSCursor.crosshair))
            window.cancelBySecondPress()
            XCTAssertTrue(window.isDismissed)
            XCTAssertTrue(sameCursor(NSCursor.current, baseline), "the second press restores the previous cursor")
        }
        // A refused stray click.
        do {
            let window = makeWindow(pointerFrame: frame)
            let baseline = NSCursor.current
            window.orderFrontRegardless()
            window.makeKey()
            XCTAssertTrue(sameCursor(NSCursor.current, NSCursor.crosshair))
            let view = try XCTUnwrap(window.surfaceView)
            view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 40, y: 40), window: window))
            view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 41, y: 41), window: window))
            XCTAssertTrue(window.isDismissed)
            XCTAssertTrue(sameCursor(NSCursor.current, baseline), "a refused stray click restores the previous cursor")
        }
    }

    func testMouseDownMovesTheSurfaceIntoDraggingAndTheInstructionLeaves() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the shape needs a real display")
        let frame = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: CGSize(width: 600, height: 400)))
        let window = makeWindow(pointerFrame: frame)
        let view = try XCTUnwrap(window.surfaceView)
        XCTAssertFalse(TextRecognitionSurfaceCopy.instruction(for: window.phase).isEmpty)

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 30, y: 30), window: window))
        // The first mouse press is the drag's start: the surface moves into
        // dragging on its own machine, and the instruction hands the stage
        // over to the rectangle.
        XCTAssertEqual(window.phase, .dragging)
        XCTAssertEqual(view.phase, .dragging)
        XCTAssertTrue(TextRecognitionSurfaceCopy.instruction(for: window.phase).isEmpty,
            "the drag carries the rectangle as its feedback, not the instruction")
    }

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

    /// Cursor identity where AppKit hands back its own instances: the same
    /// object, or the same hot spot and picture — enough to tell the
    /// crosshair from every other cursor without pretending to own the
    /// singletons.
    private func sameCursor(_ a: NSCursor, _ b: NSCursor) -> Bool {
        if a === b { return true }
        guard a.hotSpot == b.hotSpot,
            let aTiff = a.image.tiffRepresentation,
            let bTiff = b.image.tiffRepresentation else { return false }
        return aTiff == bTiff
    }

    // MARK: - The loupe (T5 follow-up): the area drag's magnifier, over the frame captured at open

    /// A display frame at 2× native scale, as `CaptureService.captureDisplay`
    /// hands it: `points` view points, `pixels` rows of real pixels.
    private func frameImage(_ points: CGFloat, _ pixels: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()!
    }

    /// The surface frame split into two horizontal bands in top-left pixel
    /// space (the reading of `CGImage.cropping(to:)`): top half green, bottom
    /// half blue — the same trick `AreaCaptureLoupeTests` uses to catch a
    /// mirrored source rect, because a bottom-left convention lands the other
    /// band.
    private func bandedFrameImage(_ pixels: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels / 2))
        context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: pixels / 2, width: pixels, height: pixels / 2))
        return try XCTUnwrap(context.makeImage())
    }

    func testTheDragMagnifiesItsFrameWithTheAreaDragGeometry() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the loupe needs a real display")
        let frame = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: CGSize(width: 600, height: 400)))
        let window = makeWindow(pointerFrame: frame)
        let view = try XCTUnwrap(window.surfaceView)
        view.loupeFrame = frameImage(600, 1200)

        // Before the drag there is nothing to magnify: the loupe exists for
        // the pixel edge being chosen, and none is being chosen yet.
        XCTAssertNil(view.loupePlan, "the loupe is a drag companion, not part of the inviting state")

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 200, y: 150), window: window))

        // The pointer at window point (200, 150) is 200 points from the
        // display's left edge and 250 from its top. The plan is exactly what
        // `AreaCaptureLoupe` answers for that point over this frame: the same
        // side, the same gap, the same projection — never a second geometry.
        XCTAssertEqual(view.loupePlan?.frame, CGRect(x: 224, y: 274, width: 120, height: 120))
        XCTAssertEqual(view.loupePlan?.source, CGRect(x: 370, y: 470, width: 60, height: 60),
            "the source square is centred on the pointer in the frame's top-left pixel space")
        XCTAssertEqual(view.loupePlan?.destination, CGRect(x: 224, y: 274, width: 120, height: 120),
            "in the open, the source lands exactly on the loupe")
        XCTAssertEqual(view.loupePlan?.crosshair, CGPoint(x: 284, y: 334),
            "the pointer's pixel sits at the loupe's centre, where the crosshair marks it")

        // Near the display's right edge, the same flips the ⇧S drag flips:
        // the loupe moves left of the pointer and the source clamps to the
        // frame's edge, magnifying only the pixels that exist.
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 595, y: 200), window: window))
        XCTAssertEqual(view.loupePlan?.frame, CGRect(x: 451, y: 224, width: 120, height: 120))
        XCTAssertEqual(view.loupePlan?.source, CGRect(x: 1160, y: 370, width: 40, height: 60))
        XCTAssertEqual(view.loupePlan?.destination, CGRect(x: 451, y: 224, width: 80, height: 120),
            "the empty rest of the loupe stays empty instead of stretching the pixels")

        // The drag ends, the surface does too: nothing keeps magnifying.
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 595, y: 200), window: window))
        XCTAssertTrue(window.isDismissed)
        XCTAssertNil(window.surfaceView?.loupePlan)
    }

    func testWithoutSurfacePixelsThereIsNothingToMagnify() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the loupe needs a real display")
        let frame = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: CGSize(width: 600, height: 400)))
        let window = makeWindow(pointerFrame: frame)
        let view = try XCTUnwrap(window.surfaceView)
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 200, y: 150), window: window))
        XCTAssertNil(view.loupePlan,
            "no pixels captured, no loupe — a magnifier over invented pixels would lie about the edge")
    }

    func testTheLoupesCrosshairPointsAtThePixelUnderThePointer() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the loupe needs a real display")
        let frame = try XCTUnwrap(PrimaryScreenTestWindow.frame(for: CGSize(width: 600, height: 400)))
        let window = makeWindow(pointerFrame: frame)
        let view = try XCTUnwrap(window.surfaceView)
        view.loupeFrame = try bandedFrameImage(1200)

        // The pointer at window (300, 120) is 280 points below the display's
        // top edge — pixel row 560 of the 1200-pixel frame at 2 px/pt, inside
        // the top band (green), and off the display's mirror axis (200) so a
        // top-left and a bottom-left source cannot agree: under a bottom-left
        // reading the same plan arithmetic would place the centre at row 640,
        // the blue band.
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 300, y: 120), window: window))

        let plan = try XCTUnwrap(view.loupePlan)
        let image = try XCTUnwrap(view.loupeFrame)
        let crop = try XCTUnwrap(image.cropping(to: plan.source))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
            bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        let bytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: crop.width * crop.height * 4)
        // The loupe's centre colour is the green top band: the crop's own
        // centre is the pixel under the pointer in the frame's top-left
        // space — no mirror anywhere.
        let centreIndex = (crop.height / 2) * crop.width * 4 + (crop.width / 2) * 4
        XCTAssertEqual(bytes[centreIndex + 1], 255, "the crop's centre is the pixel under the pointer")
        XCTAssertEqual(bytes[centreIndex + 2], 0)
        XCTAssertEqual(bytes[centreIndex], 0)
    }

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

    private func mouseKeyEvent(
        _ type: NSEvent.EventType,
        keyCode: UInt16,
        at point: CGPoint,
        window: NSWindow?
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil,
            characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: keyCode)!
    }
}
