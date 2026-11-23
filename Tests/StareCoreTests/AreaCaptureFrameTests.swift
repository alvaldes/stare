import XCTest

@testable import StareCore

/// The frozen-frame lifecycle of the area drag (S11, T2b slice A): `⇧S` takes
/// one frame the instant the drag starts and the drag runs on it until the
/// drag ends. The lifecycle is pure logic here; the image itself and the
/// AppKit glue live in `OverlayView` / `OverlayController`.
final class AreaCaptureFrameTests: XCTestCase {
    func testBeginArmsAPendingDragFromIdle() {
        var state = AreaCaptureFrameState()
        XCTAssertEqual(state.phase, .idle)

        state.begin()

        XCTAssertEqual(state.phase, .pending, "the drag is armed and a frame was requested")
    }

    func testALandedFrameFreezesOnlyAPendingDrag() {
        var state = AreaCaptureFrameState()
        let token = state.begin()

        XCTAssertTrue(state.land(token))

        XCTAssertEqual(state.phase, .frozen)
    }

    func testAFrameLandingAfterTheDragEndedIsStaleAndIgnored() {
        // The drag ended before the capture came back: the late frame must
        // never become the base, or the overlay would freeze over nothing.
        var state = AreaCaptureFrameState()
        let token = state.begin()
        state.release()

        XCTAssertFalse(state.land(token))
        XCTAssertEqual(state.phase, .idle)
    }

    func testAFrameLandingWithoutADragIsIgnored() {
        var state = AreaCaptureFrameState()

        XCTAssertFalse(state.land(nil))
        XCTAssertEqual(state.phase, .idle)
    }

    func testReleaseEndsAFrozenDrag() {
        var state = AreaCaptureFrameState()
        let token = state.begin()
        XCTAssertTrue(state.land(token))

        XCTAssertTrue(state.release())

        XCTAssertEqual(state.phase, .idle)
    }

    func testReleaseEndsAPendingDragToo() {
        // Capture failed or the frame never landed: the release still holds,
        // so the drag can never wait on a base that will not come.
        var state = AreaCaptureFrameState()
        state.begin()

        XCTAssertTrue(state.release())

        XCTAssertEqual(state.phase, .idle)
    }

    func testReleaseFromIdleIsANoOp() {
        var state = AreaCaptureFrameState()

        XCTAssertFalse(state.release())
        XCTAssertEqual(state.phase, .idle)
    }

    func testANewDragSupersedesAStillFrozenFrame() {
        var state = AreaCaptureFrameState()
        let token = state.begin()
        state.land(token)

        state.begin()

        XCTAssertEqual(state.phase, .pending, "the old base must not survive as the new drag's frame")
    }

    // MARK: Tokens

    // A frame that lands after its drag ended — or after `Esc` and a re-arm
    // while its capture was still in flight — must never become the next
    // drag's base: each armed drag carries a token, and `land` accepts only
    // the still-pending one.

    func testEachBeginMintsAFreshTokenAndItsOwnFrameStillFreezes() {
        var state = AreaCaptureFrameState()
        let first = state.begin()
        state.release()
        let second = state.begin()

        XCTAssertNotEqual(first, second, "each armed drag carries its own identity")
        XCTAssertTrue(state.land(second), "the frame of the drag in flight freezes it")
        XCTAssertEqual(state.phase, .frozen)
    }

    func testAFrameLandedAfterReArmIsStaleForTheNewDrag() {
        // Esc, re-arm inside one capture's latency, then the first drag's
        // frame lands: it must not become the new drag's base, which keeps
        // waiting for its own frame — and freezes when that arrives.
        var state = AreaCaptureFrameState()
        let first = state.begin()
        state.release()
        let second = state.begin()

        XCTAssertFalse(state.land(first))
        XCTAssertEqual(state.phase, .pending, "the second drag still waits for its own frame")

        XCTAssertTrue(state.land(second))
        XCTAssertEqual(state.phase, .frozen)
    }

    func testALandingWithNoTokenIsStale() {
        var state = AreaCaptureFrameState()
        state.begin()

        XCTAssertFalse(state.land(nil), "a landing whose drag cannot be identified never freezes")
        XCTAssertEqual(state.phase, .pending)
    }
}
