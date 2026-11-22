import XCTest
@testable import StareCore

/// The scroll-phase tables must carry AppKit's **real** raw values, not the
/// bit indices (T1/S2 regression): `NSEvent.Phase` is a bit set — began 1,
/// stationary 2, changed 4, ended 8, cancelled 16, mayBegin 32 — and the
/// momentum phase shares the same numbering (momentum `.end` is 8). Probed
/// directly against `NSEvent` on this machine (began=1, stationary=2,
/// changed=4, ended=8, cancelled=16, mayBegin=32; a synthesized
/// `CGEvent(scrollWheelEvent2Source:)` maps its scroll-phase field 1 → 1,
/// 2 → 4, 4 → 8, 8 → 16 and its momentum field 1 → 1, 2 → 4, 3 → 8).
///
/// With the wrong table every live `.changed` event (raw 4) decoded as
/// `.ended`, so the direction lock was released on every event and the zoom
/// fluttered both ways; the momentum tail (raw 8) and `.cancelled` (raw 16)
/// decoded to `nil` → `.none`, so momentum zoomed and an interrupted gesture
/// left the lock latched. These tests decode AppKit's numbers through
/// `rawValue` the way the view does, so the tables cannot drift again.
final class ScrollZoomPhaseMappingTests: XCTestCase {
    // MARK: The tables carry AppKit's real values

    func testPhaseRawValuesMatchAppKit() {
        XCTAssertEqual(ScrollZoom.Phase.none.rawValue, 0)
        XCTAssertEqual(ScrollZoom.Phase.began.rawValue, 1, "NSEvent.Phase.began")
        XCTAssertEqual(ScrollZoom.Phase.stationary.rawValue, 2, "NSEvent.Phase.stationary")
        XCTAssertEqual(ScrollZoom.Phase.changed.rawValue, 4, "NSEvent.Phase.changed")
        XCTAssertEqual(ScrollZoom.Phase.ended.rawValue, 8, "NSEvent.Phase.ended")
        XCTAssertEqual(ScrollZoom.Phase.cancelled.rawValue, 16, "NSEvent.Phase.cancelled")
        XCTAssertEqual(ScrollZoom.Phase.mayBegin.rawValue, 32, "NSEvent.Phase.mayBegin")
    }

    func testMomentumPhaseRawValuesMatchAppKit() {
        XCTAssertEqual(ScrollZoom.MomentumPhase.none.rawValue, 0)
        XCTAssertEqual(ScrollZoom.MomentumPhase.begin.rawValue, 1, "momentum begin shares AppKit's bit numbering")
        XCTAssertEqual(ScrollZoom.MomentumPhase.stationary.rawValue, 2, "momentum stationary shares AppKit's bit numbering")
        XCTAssertEqual(ScrollZoom.MomentumPhase.continued.rawValue, 4, "momentum continued carries the changed bit")
        XCTAssertEqual(ScrollZoom.MomentumPhase.end.rawValue, 8, "momentum end carries the ended bit")
    }

    /// The values AppKit actually reports for hardware momentum
    /// (`momentumPhase` shares the `NSEvent.Phase` numbering: begin 1,
    /// continued 4, end 8) must decode to named momentum cases, never to
    /// `nil` — a `nil` decode fell back to `.none` and zoomed.
    func testHardwareMomentumRawValuesDecodeToMomentumCases() {
        XCTAssertEqual(ScrollZoom.MomentumPhase(rawValue: 1), .begin)
        XCTAssertEqual(ScrollZoom.MomentumPhase(rawValue: 4), .continued)
        XCTAssertEqual(ScrollZoom.MomentumPhase(rawValue: 8), .end)
        XCTAssertNotNil(ScrollZoom.MomentumPhase(rawValue: 2))
    }

    // MARK: A live `.changed` event keeps the gesture running

    /// raw 4 is what a live trackpad event reports (`NSEvent.Phase.changed`);
    /// it must decode as `.changed` and leave the direction lock latched.
    func testALiveChangedEventKeepsTheGestureRunning() {
        XCTAssertEqual(ScrollZoom.Phase(rawValue: 4), .changed, "raw 4 — what live hardware reports — decodes as .changed")
        var gesture = ScrollZoom.Gesture()
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: 4, phase: .began)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: 4))
        )
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: 3, phase: .changed)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: 3)),
            "a live changed event keeps the gesture running and zooms"
        )
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: -0.5, phase: .changed)),
            .noZoom,
            "the lock survived the live events: opposite jitter must not zoom"
        )
    }

    // MARK: Ending and cancelling release the lock

    func testTheEndedRawValueClosesTheGesture() {
        XCTAssertEqual(ScrollZoom.Phase(rawValue: 8), .ended, "raw 8 decodes as .ended")
        var gesture = ScrollZoom.Gesture()
        _ = gesture.decide(for: ScrollZoom.Event(deltaY: 4, phase: .began))
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: 0, phase: ScrollZoom.Phase(rawValue: 8)!)),
            .noZoom
        )
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: -4, phase: .began)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: -4)),
            "after .ended the lock is released and the next gesture may zoom out"
        )
    }

    func testTheCancelledRawValueClosesTheGesture() {
        XCTAssertEqual(ScrollZoom.Phase(rawValue: 16), .cancelled, "raw 16 decodes as .cancelled")
        var gesture = ScrollZoom.Gesture()
        _ = gesture.decide(for: ScrollZoom.Event(deltaY: 4, phase: .began))
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: 0, phase: ScrollZoom.Phase(rawValue: 16)!)),
            .noZoom
        )
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: -4, phase: .began)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: -4)),
            "after .cancelled the lock is released and the next gesture may zoom out"
        )
    }

    // MARK: Every momentum phase is recognised and never zooms

    /// Each named momentum phase — and each raw value hardware momentum
    /// reports — must be rejected without zooming and without disturbing the
    /// direction lock.
    func testEveryMomentumPhaseNeverZoomsAndNeverDisturbsTheLock() {
        let named: [ScrollZoom.MomentumPhase] = [.begin, .stationary, .continued, .end]
        let hardwareRawValues = [1, 2, 4, 8]
        XCTAssertEqual(named.map(\.rawValue), hardwareRawValues, "the cases name every nonzero value hardware reports")
        for raw in hardwareRawValues {
            var gesture = ScrollZoom.Gesture()
            _ = gesture.decide(for: ScrollZoom.Event(deltaY: 4, phase: .began))
            let momentum = ScrollZoom.MomentumPhase(rawValue: raw)
            XCTAssertNotNil(momentum, "raw \(raw) must decode to a momentum phase, never nil")
            XCTAssertEqual(
                gesture.decide(for: ScrollZoom.Event(deltaY: 300, momentumPhase: momentum!)),
                .noZoom,
                "momentum raw \(raw) must not zoom"
            )
            XCTAssertEqual(
                gesture.decide(for: ScrollZoom.Event(deltaY: 2)),
                .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: 2)),
                "after momentum raw \(raw) the lock waits untouched and keeps zooming in"
            )
        }
    }
}
