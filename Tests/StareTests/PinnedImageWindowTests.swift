import AppKit
import CoreGraphics
import XCTest
@testable import Stare
@testable import StareCore

/// The pinned capture image window and its entry points (T4/S6). Every
/// window a test shows is placed inside the primary screen through
/// `PrimaryScreenTestWindow` and closed before the test ends — the rule L9
/// fixed for the whole suite, because the human watches the secondary
/// monitors while tests run.
@MainActor
final class PinnedImageWindowTests: XCTestCase {

    private var coordinator: PinnedImageCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = PinnedImageCoordinator()
    }

    override func tearDown() {
        coordinator.closeAll()
        coordinator = nil
        super.tearDown()
    }

    private func solidImage(_ width: Int, _ height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow?) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1)!
    }

    // MARK: - Window shape

    func testAPinnedImageIsABorderlessAlwaysOnTopWindowThatNeverStealsFocus() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the shape needs a real display")
        let image = try XCTUnwrap(solidImage(160, 120))
        coordinator.pin(image, on: NSScreen.screens.first)
        let window = try XCTUnwrap(coordinator.windows.first)
        XCTAssertEqual(window.styleMask, [.borderless, .nonactivatingPanel])
        XCTAssertEqual(window.level, .floating, "a pinned image floats above normal windows")
        XCTAssertFalse(window.hidesOnDeactivate, "it survives the app losing focus")
        XCTAssertTrue(window.isMovableByWindowBackground, "it drags by any part of its surface")
        XCTAssertFalse(window.canBecomeKey, "it never steals typing focus from the app underneath")

        // The placement the coordinator chose sits wholly inside the screen it
        // was given — never on another display.
        if let primary = NSScreen.screens.first {
            XCTAssertTrue(primary.visibleFrame.contains(window.frame), "\(window.frame) outside \(primary.visibleFrame)")
        }
    }

    // MARK: - Several coexist, each closes on its own

    func testSeveralPinnedImagesCoexistAndCloseOnTheirOwn() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "coexistence needs a real display")
        let image = try XCTUnwrap(solidImage(120, 90))
        coordinator.pin(image, on: NSScreen.screens.first)
        coordinator.pin(image, on: NSScreen.screens.first)
        XCTAssertEqual(coordinator.windows.count, 2)
        let first = try XCTUnwrap(coordinator.windows.first)
        let second = try XCTUnwrap(coordinator.windows.last)
        XCTAssertEqual(first.lockState, .floating)
        XCTAssertEqual(second.lockState, .floating)

        first.closeSelf()
        XCTAssertFalse(first.isVisible, "the closed one stays closed")
        XCTAssertTrue(second.isVisible, "the other one is untouched")
        XCTAssertEqual(second.lockState, .floating)
        XCTAssertEqual(coordinator.windows.count, 1, "the closed one leaves the coordinator")
    }

    // MARK: - The lock

    func testLockMakesTheWindowClickThroughAndUnlockRestoresIt() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the lock needs a real display")
        let image = try XCTUnwrap(solidImage(120, 90))
        coordinator.pin(image, on: NSScreen.screens.first)
        let window = try XCTUnwrap(coordinator.windows.first)
        XCTAssertFalse(window.ignoresMouseEvents, "unlocked, it receives clicks")

        let point = CGPoint(x: window.frame.midX, y: window.frame.midY)
        coordinator.toggleLock(at: point)
        XCTAssertEqual(window.lockState, .locked, "locked, the body passes clicks to the app underneath")

        coordinator.toggleLock(at: point)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertEqual(window.lockState, .floating)
    }

    func testTheLockToggleReachesTheFrontmostPinnedImageUnderThePointer() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the toggle needs a real display")
        let image = try XCTUnwrap(solidImage(120, 90))
        coordinator.pin(image, on: NSScreen.screens.first)
        coordinator.pin(image, on: NSScreen.screens.first)
        let back = coordinator.windows[0]
        let front = coordinator.windows[1]
        let point = CGPoint(x: front.frame.midX, y: front.frame.midY)

        coordinator.toggleLock(at: point)
        XCTAssertEqual(front.lockState, .locked, "the frontmost window under the point locks")
        XCTAssertEqual(back.lockState, .floating, "the window behind is untouched")
    }

    // MARK: - The ⌥⇧I toggle (T4 closing fix)

    func testASecondKeyboardPinTakesTheTopmostPinnedImageDown() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the toggle needs a real display")
        let image = try XCTUnwrap(solidImage(120, 90))
        let history = CaptureHistory(capacity: 2)
        history.record(image, at: Date())

        coordinator.togglePin(from: history)
        XCTAssertEqual(coordinator.windows.count, 1, "a clear screen pins the latest capture")

        coordinator.togglePin(from: history)
        XCTAssertEqual(coordinator.windows.count, 0, "the second press takes the pin down")

        coordinator.togglePin(from: history)
        XCTAssertEqual(coordinator.windows.count, 1, "the third press pins again")
    }

    func testTheKeyboardDismissReachesALockedPinnedImage() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the lock needs a real display")
        let image = try XCTUnwrap(solidImage(120, 90))
        let history = CaptureHistory(capacity: 2)
        history.record(image, at: Date())
        coordinator.togglePin(from: history)
        let window = try XCTUnwrap(coordinator.windows.first)
        window.toggleLock()
        XCTAssertEqual(window.lockState, .locked)

        coordinator.togglePin(from: history)
        XCTAssertEqual(
            coordinator.windows.count, 0,
            "a click-through window cannot be reached by the pointer, so the keyboard must close it")
    }

    // MARK: - The lock never covers the way out (T4 closing fix)

    func testALockedPinnedImageTakesTheCloseClickAndPassesTheBodyThrough() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the lock needs a real display")
        let image = try XCTUnwrap(solidImage(120, 90))
        coordinator.pin(image, on: NSScreen.screens.first)
        let window = try XCTUnwrap(coordinator.windows.first)
        let view = try XCTUnwrap(window.pinnedView)

        window.toggleLock()
        XCTAssertFalse(
            window.ignoresMouseEvents,
            "the lock is per point now, not a blanket switch that removes the window from the input path")

        // Top-down control coordinates (the flipped surface's own space)
        // mapped onto the window coordinates the events and hit tests speak.
        func windowPoint(topDown rect: CGRect) -> CGPoint {
            CGPoint(x: rect.midX, y: view.bounds.height - rect.midY)
        }
        let closePoint = windowPoint(topDown: PinnedImageControls.rect(for: .close, in: view.bounds))
        let lockPoint = windowPoint(topDown: PinnedImageControls.rect(for: .lock, in: view.bounds))
        let bodyPoint = CGPoint(x: view.bounds.midX, y: view.bounds.height - view.bounds.midY)

        XCTAssertIdentical(view.hitTest(closePoint), view, "locked, the ✕ still takes the click")
        XCTAssertIdentical(view.hitTest(lockPoint), view, "locked, the 🔒 still takes the click")
        XCTAssertNil(view.hitTest(bodyPoint), "locked, the body passes the click to the app underneath")

        // The routed click on the locked window's ✕ closes it for real.
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: closePoint, window: window))
        XCTAssertEqual(coordinator.windows.count, 0, "the ✕ closes the locked pin — the reported trap")
    }

    func testALockedPinnedImageKeepsItsControlsDrawnWithoutHover() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the lock needs a real display")
        let image = try XCTUnwrap(solidImage(120, 90))
        coordinator.pin(image, on: NSScreen.screens.first)
        let window = try XCTUnwrap(coordinator.windows.first)
        let view = try XCTUnwrap(window.pinnedView)
        XCTAssertFalse(view.showsIdleControls, "floating, the controls are a hover affordance")

        window.toggleLock()
        XCTAssertTrue(
            view.showsIdleControls,
            "a click-through surface cannot be hovered, so while locked the controls stay drawn")
    }

    // MARK: - The no-op feedback (T4 closing fix)

    func testALockToggleOverNoPinnedImageIsSaidInsteadOfSwallowed() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the feedback needs a real display")
        let image = try XCTUnwrap(solidImage(120, 90))
        var reported: [PinnedImageFeedback] = []
        coordinator.onFeedback = { reported.append($0) }

        coordinator.pin(image, on: NSScreen.screens.first)
        let frame = try XCTUnwrap(coordinator.windows.first).frame

        coordinator.toggleLock(at: CGPoint(x: frame.maxX + 500, y: frame.midY))
        XCTAssertEqual(
            reported, [.noPinnedImageUnderPointer],
            "⌥⇧L over nothing says so — never a dead key")

        coordinator.toggleLock(at: CGPoint(x: frame.midX, y: frame.midY))
        XCTAssertEqual(reported, [.noPinnedImageUnderPointer], "a hit stays quiet")
    }

    func testAPinWithoutACaptureSaysNothingCapturedYet() {
        var reported: [PinnedImageFeedback] = []
        coordinator.onFeedback = { reported.append($0) }
        let history = CaptureHistory(capacity: 1)

        coordinator.togglePin(from: history)
        XCTAssertEqual(reported, [.nothingCapturedYet], "the empty-session press says why")
        XCTAssertEqual(coordinator.windows.count, 0)
    }

    // MARK: - Scroll resize and opacity

    func testScrollResizesTheWindowInsideItsScreen() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the resize needs a real display")
        let image = try XCTUnwrap(solidImage(200, 100))
        coordinator.pin(image, on: NSScreen.screens.first)
        let window = try XCTUnwrap(coordinator.windows.first)
        let view = try XCTUnwrap(window.contentView as? PinnedImageView)
        let before = window.frame
        let bounds = NSScreen.screens.first!.visibleFrame

        view.handleScroll(deltaY: 4, optionDown: false)
        XCTAssertGreaterThan(window.frame.width, before.width, "scroll grows the image")

        for _ in 0..<15 { view.handleScroll(deltaY: -4, optionDown: false) }
        XCTAssertGreaterThanOrEqual(window.frame.width, PinnedImageGeometry.minWidth)
        XCTAssertLessThanOrEqual(window.frame.width, PinnedImageGeometry.resizedFrame(
            before, steps: 1_000, in: bounds).width + 1,
            "growth clamps at the screen, and the scroll walker stops at the floor it is given")
        XCTAssertTrue(bounds.contains(window.frame), "\(window.frame) left \(bounds)")
    }

    func testOptionScrollStepsTheWindowOpacityBetweenItsLimits() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the opacity needs a real display")
        let image = try XCTUnwrap(solidImage(120, 90))
        coordinator.pin(image, on: NSScreen.screens.first)
        let window = try XCTUnwrap(coordinator.windows.first)
        let view = try XCTUnwrap(window.contentView as? PinnedImageView)

        view.handleScroll(deltaY: -1, optionDown: true)
        XCTAssertEqual(window.alphaValue, 0.9, accuracy: 0.001)
        for _ in 0..<20 { view.handleScroll(deltaY: -1, optionDown: true) }
        XCTAssertEqual(window.alphaValue, PinnedImageGeometry.minimumOpacity, accuracy: 0.001)
        for _ in 0..<20 { view.handleScroll(deltaY: 1, optionDown: true) }
        XCTAssertEqual(window.alphaValue, 1.0, accuracy: 0.001)
    }

    // MARK: - The capture card's pin action

    func testTheCardPinButtonFloatsTheImageAndTheRestOfTheCardStillOpens() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the card needs a real display")
        let image = try XCTUnwrap(solidImage(120, 90))
        let card = CaptureCardController()
        var pinnedImages: [CGImage] = []
        card.onPin = { pinnedImage, _ in pinnedImages.append(pinnedImage) }

        var opened = 0
        card.onOpen = { _ in opened += 1 }
        let screen = try XCTUnwrap(NSScreen.screens.first)
        card.show(image, on: screen)
        let cardWindow = try XCTUnwrap(card.openCards.first)
        defer { cardWindow.close() }

        // The placement the controller chose is confined to the screen it was
        // given, exactly like the pinned window's.
        XCTAssertTrue(screen.visibleFrame.contains(cardWindow.frame), "\(cardWindow.frame) outside \(screen.visibleFrame)")

        let view = try XCTUnwrap(cardWindow.contentView as? CaptureCardView)
        // pinButtonRect is top-down (the card is flipped); the event's
        // locationInWindow is bottom-up — convert the point before pressing.
        let pinRect = CaptureCardView.pinButtonRect(in: view.bounds)
        let pinPointInWindow = CGPoint(
            x: pinRect.midX,
            y: view.bounds.height - pinRect.midY
        )
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: pinPointInWindow, window: cardWindow))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: pinPointInWindow, window: cardWindow))
        XCTAssertEqual(pinnedImages.count, 1, "the pin button floats the image")
        XCTAssertEqual(opened, 0, "the pin button never opens the editor")

        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: view.bounds.midX, y: view.bounds.midY), window: cardWindow))
        XCTAssertEqual(opened, 1, "a click anywhere else keeps opening the editor")
        XCTAssertEqual(pinnedImages.count, 1)
    }

    // MARK: - The card path through the controller

    func testThePinnedImageOutlivesTheDrawingSessionItWasCapturedIn() throws {
        let image = try XCTUnwrap(solidImage(120, 90))
        let history = CaptureHistory(capacity: 2)
        let controller = OverlayController(
            captureService: CaptureService(),
            history: history,
            editorHandoff: { _, _ in }
        )
        controller.pinLatestCapture()
        XCTAssertEqual(controller.pinnedImageCount, 0, "no capture yet, nothing floats")

        history.record(image, at: Date())
        controller.pinLatestCapture()
        XCTAssertEqual(controller.pinnedImageCount, 1, "the latest capture floats")

        if let primary = NSScreen.screens.first {
            let window = try XCTUnwrap(controller.pinnedImages.windows.first)
            XCTAssertTrue(primary.visibleFrame.contains(window.frame), "\(window.frame) outside \(primary.visibleFrame)")
        }

        // The drawing session's exits never touch the pinned image: the
        // coordinator's windows are not the canvases.
        controller.pinnedImages.closeAll()
        XCTAssertEqual(controller.pinnedImageCount, 0)
    }
}
