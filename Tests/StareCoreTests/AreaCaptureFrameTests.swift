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
        state.begin()

        XCTAssertTrue(state.land())

        XCTAssertEqual(state.phase, .frozen)
    }

    func testAFrameLandingAfterTheDragEndedIsStaleAndIgnored() {
        // The drag ended before the capture came back: the late frame must
        // never become the base, or the overlay would freeze over nothing.
        var state = AreaCaptureFrameState()
        state.begin()
        state.release()

        XCTAssertFalse(state.land())
        XCTAssertEqual(state.phase, .idle)
    }

    func testAFrameLandingWithoutADragIsIgnored() {
        var state = AreaCaptureFrameState()

        XCTAssertFalse(state.land())
        XCTAssertEqual(state.phase, .idle)
    }

    func testReleaseEndsAFrozenDrag() {
        var state = AreaCaptureFrameState()
        state.begin()
        state.land()

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
        state.begin()
        state.land()

        state.begin()

        XCTAssertEqual(state.phase, .pending, "the old base must not survive as the new drag's frame")
    }
}
