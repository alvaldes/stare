import CoreGraphics
import XCTest
@testable import StareCore

/// The pure decisions behind pinning the captured image (T4/S6): where the
/// floating window lands, how scroll resizes it, how opacity steps, the
/// click-through lock state machine, which pinned window a lock toggle
/// reaches, and where the hover controls sit. No AppKit here — the window is
/// thin glue over these decisions, covered in StareTests.
final class PinnedImageTests: XCTestCase {

    // MARK: - Initial size

    func testInitialSizeUsesTheNaturalPointSizeWhenItAlreadyFits() {
        let size = PinnedImageGeometry.initialSize(
            imageSize: CGSize(width: 400, height: 300),
            bounds: CGSize(width: 2000, height: 1200)
        )
        XCTAssertEqual(size, CGSize(width: 400, height: 300))
    }

    func testInitialSizeScalesAnOversizedImageDownAndKeepsTheAspect() {
        let size = PinnedImageGeometry.initialSize(
            imageSize: CGSize(width: 2240, height: 1680),
            bounds: CGSize(width: 2000, height: 1200)
        )
        XCTAssertEqual(size.width, PinnedImageGeometry.maxInitialSize.width, accuracy: 1)
        XCTAssertEqual(size.height, PinnedImageGeometry.maxInitialSize.height, accuracy: 1)
    }

    func testInitialSizeNeverExceedsTheScreenItWillLandOn() {
        let size = PinnedImageGeometry.initialSize(
            imageSize: CGSize(width: 2000, height: 1000),
            bounds: CGSize(width: 300, height: 200)
        )
        XCTAssertLessThanOrEqual(size.width, 300)
        XCTAssertLessThanOrEqual(size.height, 200)
        let aspect = Double(size.width) / Double(size.height)
        XCTAssertEqual(aspect, 2.0, accuracy: 0.05, "the resize keeps the image's aspect")
    }

    // MARK: - Initial placement

    // T4 corner fix: the human's report was that a pin centred on the display
    // "queda raro". The rule now: a pin opens against the same bottom-right
    // corner the capture card occupies, offset from the card's slot so both
    // are readable — it only reaches the middle of the display if the user
    // drags it there.
    func testInitialOriginNestsThePinBesideTheCaptureCardCorner() {
        let origin = PinnedImageGeometry.initialOrigin(
            size: CGSize(width: 300, height: 200),
            in: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        // The card's corner inset plus its widest plate plus the gap kept
        // between the two — the pin's right edge sits left of that slot.
        XCTAssertEqual(
            origin.x,
            1000 - PinnedImageGeometry.cardCornerInset - PinnedImageGeometry.cardSlotWidth
                - PinnedImageGeometry.pinCardGap - 300)
        // The bottom edge aligns with the card's own bottom margin.
        XCTAssertEqual(origin.y, PinnedImageGeometry.cardCornerInset)
    }

    func testInitialOriginKeepsTheCornerRuleOnADisplayThatDoesNotStartAtTheOrigin() {
        // A second display's visible frame has nonzero insets; the rule is
        // about the corner, not about a zero origin.
        let origin = PinnedImageGeometry.initialOrigin(
            size: CGSize(width: 200, height: 150),
            in: CGRect(x: 1440, y: 30, width: 1000, height: 800)
        )
        XCTAssertEqual(
            origin.x,
            1440 + 1000 - PinnedImageGeometry.cardCornerInset
                - PinnedImageGeometry.cardSlotWidth - PinnedImageGeometry.pinCardGap - 200)
        XCTAssertEqual(origin.y, 30 + PinnedImageGeometry.cardCornerInset)
    }

    func testTheInitialPlacementNeverCoversTheCaptureCardSlot() {
        let bounds = CGRect(x: 100, y: 50, width: 1400, height: 900)
        let size = CGSize(width: 400, height: 300)
        let frame = CGRect(
            origin: PinnedImageGeometry.initialOrigin(size: size, in: bounds),
            size: size)
        // The widest card the controller can show, at the corner the
        // controller nests it in: inset from the edges, its own height.
        let cardSlot = CGRect(
            origin: CGPoint(
                x: bounds.maxX - PinnedImageGeometry.cardCornerInset - PinnedImageGeometry.cardSlotWidth,
                y: bounds.minY + PinnedImageGeometry.cardCornerInset),
            size: CGSize(
                width: PinnedImageGeometry.cardSlotWidth,
                height: PinnedImageGeometry.cardSlotHeight))
        XCTAssertFalse(
            frame.intersects(cardSlot),
            "\(frame) covers the card slot \(cardSlot) — the pin must sit beside it, both readable")
    }

    func testInitialOriginStaysInsideTheScreen() {
        let origin = PinnedImageGeometry.initialOrigin(
            size: CGSize(width: 900, height: 700),
            in: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let frame = CGRect(origin: origin, size: CGSize(width: 900, height: 700))
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1000, height: 800).contains(frame))
    }

    // MARK: - Scroll resize

    func testScrollGrowsTheWindowAndKeepsTheAspect() {
        let frame = PinnedImageGeometry.resizedFrame(
            CGRect(x: 100, y: 100, width: 300, height: 200),
            steps: 1,
            in: CGRect(x: 0, y: 0, width: 2000, height: 1200)
        )
        XCTAssertGreaterThan(frame.width, 300)
        XCTAssertLessThanOrEqual(frame.width, 2000)
        let aspect = Double(frame.width) / Double(frame.height)
        XCTAssertEqual(aspect, 1.5, accuracy: 0.02)
    }

    func testScrollShrinksTheWindowNeverBelowTheMinimumWidth() {
        var frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        for _ in 0..<12 {
            frame = PinnedImageGeometry.resizedFrame(
                frame, steps: -1, in: CGRect(x: 0, y: 0, width: 2000, height: 1200))
        }
        XCTAssertGreaterThanOrEqual(
            frame.width, PinnedImageGeometry.minWidth,
            "shrinking stops at the floor instead of collapsing to nothing")
    }

    func testScrollGrowthNeverLeavesTheScreen() {
        var frame = CGRect(x: 100, y: 100, width: 400, height: 200)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        for _ in 0..<12 {
            frame = PinnedImageGeometry.resizedFrame(frame, steps: 1, in: bounds)
        }
        XCTAssertTrue(bounds.contains(frame), "\(frame) left \(bounds)")
    }

    func testAResizedWindowStaysInsideTheScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        // A window pinned near a corner grows toward the screen, not off it.
        let frame = PinnedImageGeometry.resizedFrame(
            CGRect(x: 650, y: 500, width: 140, height: 90),
            steps: 1,
            in: bounds
        )
        XCTAssertTrue(bounds.contains(frame), "\(frame) left \(bounds)")
    }

    // MARK: - Opacity

    func testOpacityStepsByATenthAndClampsAtBothEnds() {
        var opacity = PinnedImageGeometry.steppedOpacity(1.0, direction: 1)
        XCTAssertEqual(opacity, 1.0, accuracy: 0.001, "the ceiling is 1.0")
        opacity = PinnedImageGeometry.steppedOpacity(opacity, direction: -1)
        XCTAssertEqual(opacity, 0.9, accuracy: 0.001)
        for _ in 0..<20 { opacity = PinnedImageGeometry.steppedOpacity(opacity, direction: -1) }
        XCTAssertEqual(
            opacity, PinnedImageGeometry.minimumOpacity, accuracy: 0.001,
            "the floor is \(PinnedImageGeometry.minimumOpacity)")
    }

    // MARK: - The lock state machine

    func testLockTogglesBetweenFloatingAndLocked() {
        var lock = PinnedImageLockState.floating
        lock = lock.toggled
        XCTAssertEqual(lock, .locked, "the 🔒 control locks it")
        lock = lock.toggled
        XCTAssertEqual(lock, .floating, "the same toggle unlocks it")
    }

    // T4 closing fix: the click-through lock is per point, not a blanket
    // switch — locked, the image body passes the click to the app underneath
    // and the two controls keep answering, because a lock that covers the ✕
    // is a trap the pointer cannot leave.
    func testALockedSurfaceAnswersOnlyItsControlsAndNothingElse() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 220)
        let close = PinnedImageControls.rect(for: .close, in: bounds)
        let lock = PinnedImageControls.rect(for: .lock, in: bounds)
        let bodyPoint = CGPoint(x: bounds.midX, y: bounds.midY)
        let locked = PinnedImageLockState.locked

        XCTAssertFalse(
            locked.acceptsMouseEvents(at: bodyPoint, in: bounds),
            "locked, the body passes the click through to the app underneath")
        XCTAssertTrue(
            locked.acceptsMouseEvents(at: CGPoint(x: close.midX, y: close.midY), in: bounds),
            "the lock never covers the ✕: closing stays pointer-reachable")
        XCTAssertTrue(
            locked.acceptsMouseEvents(at: CGPoint(x: lock.midX, y: lock.midY), in: bounds),
            "the lock never covers its own 🔒: unlocking stays pointer-reachable")
        for point in [bodyPoint, CGPoint(x: close.midX, y: close.midY)] {
            XCTAssertTrue(
                PinnedImageLockState.floating.acceptsMouseEvents(at: point, in: bounds),
                "floating, the whole surface answers")
        }
    }

    // MARK: - The ⌥⇧I rule (T4 closing fix)

    func testASecondKeyboardPinTakesTheTopmostPinDownInsteadOfPinningAnother() {
        XCTAssertEqual(
            PinnedImagePinRule.keyboardPin(hasPinnedImages: false, hasCaptures: true), .pin,
            "a clear screen pins the session's latest capture")
        XCTAssertEqual(
            PinnedImagePinRule.keyboardPin(hasPinnedImages: true, hasCaptures: true), .dismissTopmost,
            "the second press takes the frontmost pin down — never a stack")
        XCTAssertEqual(
            PinnedImagePinRule.keyboardPin(hasPinnedImages: true, hasCaptures: false), .dismissTopmost,
            "the keyboard reaches through the click-through lock")
        XCTAssertEqual(
            PinnedImagePinRule.keyboardPin(hasPinnedImages: false, hasCaptures: false), .nothingToPin,
            "nothing captured yet is reportable, never a silent key")
    }

    // MARK: - The no-op feedback (T4 closing fix)

    func testThePinShortcutsSaySomethingWhenTheyCannotAct() {
        XCTAssertEqual(PinnedImageFeedback.nothingCapturedYet.title, "Nothing captured yet")
    }

    // MARK: - Hover controls

    func testThePinBadgeLockAndCloseControlsSitInARowInsideTheWindow() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 220)
        let close = PinnedImageControls.rect(for: .close, in: bounds)
        let lock = PinnedImageControls.rect(for: .lock, in: bounds)
        let pin = PinnedImageControls.rect(for: .pin, in: bounds)
        XCTAssertTrue(
            PinnedImageControls.Kind.allCases.contains(.pin),
            "a pinned image announces itself with its own badge")
        for rect in [close, lock, pin] {
            XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(rect), "\(rect) outside \(bounds)")
        }
        XCTAssertLessThan(
            lock.maxX, close.minX + 1,
            "the lock control sits to the left of the close control, same row")
        XCTAssertLessThan(
            pin.maxX, lock.minX + 1,
            "the pinned badge sits to the left of the lock control, same row")
        XCTAssertEqual(lock.minY, close.minY)
        XCTAssertEqual(pin.minY, close.minY)
    }

    // MARK: - Hotkey defaults

    func testTheCaptureHistoryOwnsTheOneFixedShortcutThePinUsedToHave() {
        // ⌥⇧I opens the capture history now. The pin registers no global key of
        // its own any more — the card's pin button and the menu's Pin Image are
        // its path — so nothing else may claim the binding the history holds.
        let optionShiftI = HotkeyBinding(key: .i, modifiers: [.option, .shift])
        XCTAssertEqual(HotkeyAction.captureHistory.defaultBinding, optionShiftI)
        for action in HotkeyAction.allCases where action != .captureHistory {
            XCTAssertNotEqual(action.defaultBinding, optionShiftI)
        }
        // ⌥⇧O stays reserved for the OCR gesture.
        XCTAssertNotEqual(HotkeyAction.captureHistory.defaultBinding.key, .o)
    }
}
