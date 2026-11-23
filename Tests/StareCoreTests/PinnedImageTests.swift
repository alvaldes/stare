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

    func testInitialOriginCentersTheWindowInsideTheScreen() {
        let origin = PinnedImageGeometry.initialOrigin(
            size: CGSize(width: 300, height: 200),
            in: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        XCTAssertEqual(origin.x, 350)
        XCTAssertEqual(origin.y, 300)
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

    func testLockTogglesAndDrivesClickThrough() {
        var lock = PinnedImageLockState.floating
        XCTAssertTrue(lock.acceptsMouseEvents, "a fresh pinned image receives clicks")
        lock = lock.toggled
        XCTAssertEqual(lock, .locked)
        XCTAssertFalse(lock.acceptsMouseEvents, "locked means every click goes underneath")
        lock = lock.toggled
        XCTAssertEqual(lock, .floating)
        XCTAssertTrue(lock.acceptsMouseEvents)
    }

    // MARK: - Which window a lock toggle reaches

    func testTheLockToggleReachesTheTopmostWindowUnderThePointer() {
        let frames = [
            CGRect(x: 0, y: 0, width: 400, height: 300),
            CGRect(x: 50, y: 50, width: 400, height: 300),
        ]
        // The later window is the frontmost one; it wins the point.
        XCTAssertEqual(
            PinnedImageFocus.topmostIndex(containing: CGPoint(x: 100, y: 100), in: frames), 1)
        XCTAssertEqual(
            PinnedImageFocus.topmostIndex(containing: CGPoint(x: 10, y: 10), in: frames), 0)
        XCTAssertNil(
            PinnedImageFocus.topmostIndex(containing: CGPoint(x: 900, y: 900), in: frames),
            "a point over no pinned image toggles nothing")
    }

    // MARK: - Hover controls

    func testTheLockAndCloseControlsSitInTheTopRightCornerInsideTheWindow() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 220)
        let close = PinnedImageControls.rect(for: .close, in: bounds)
        let lock = PinnedImageControls.rect(for: .lock, in: bounds)
        for rect in [close, lock] {
            XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(rect), "\(rect) outside \(bounds)")
        }
        XCTAssertLessThan(
            lock.maxX, close.minX + 1,
            "the lock control sits to the left of the close control, same row")
        XCTAssertEqual(lock.minY, close.minY)
    }

    // MARK: - Hotkey defaults

    func testThePinnedImageShortcutsDoNotCollideWithEveryExistingOne() {
        // The two new fixed bindings: ⌥⇧I pins the latest capture, ⌥⇧L toggles
        // the lock of the pinned image under the pointer.
        XCTAssertEqual(PinnedImageHotkeyDefaults.pin.key, .i)
        XCTAssertEqual(PinnedImageHotkeyDefaults.pin.modifiers, [.option, .shift])
        XCTAssertEqual(PinnedImageHotkeyDefaults.lock.key, .l)
        XCTAssertEqual(PinnedImageHotkeyDefaults.lock.modifiers, [.option, .shift])

        // The four registered global actions can never share a binding with
        // the new ones.
        for action in HotkeyAction.allCases {
            XCTAssertNotEqual(PinnedImageHotkeyDefaults.pin, action.defaultBinding)
            XCTAssertNotEqual(PinnedImageHotkeyDefaults.lock, action.defaultBinding)
        }
        // ⌥⇧O is reserved for OCR later; the single-key capture flow (S, ⇧S,
        // ⌥S) has no modifiers this design would accept, so the collision
        // check that matters beside the four actions is O itself.
        XCTAssertNotEqual(PinnedImageHotkeyDefaults.pin.key, .o)
        XCTAssertNotEqual(PinnedImageHotkeyDefaults.lock.key, .o)
    }
}
