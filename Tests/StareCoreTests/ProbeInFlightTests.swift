import XCTest
@testable import StareCore

/// The probe's in-flight guard, headless. The wiring that obeys it lives in the
/// untested `Stare` target; this rule must not live only there, so `StareCore`
/// owns it and these tests pin it.
///
/// R3-002/R4-3: the probe's bounded wait does not cancel the detached capture,
/// so a persistently stalled ScreenCaptureKit call would accumulate one
/// orphaned capture per refresh tick while the caller has already returned.
/// While a probe is in flight the guard hands back the last known answer
/// instead of letting the caller start another capture.
///
/// The lifecycle these tests pin: `begin` starts a pass; a wait that expired
/// (`timeOut`) records what the caller answered but keeps the pass in flight,
/// because the capture it abandoned is still running; the capture's real
/// completion (`finish`) records the real answer and frees the next probe. A
/// completion from a pass a newer probe displaced is ignored.
final class ProbeInFlightTests: XCTestCase {
    /// An idle guard lets the first probe run: `begin` says proceed and marks
    /// the guard busy.
    func testIdleBeginTellsTheCallerToProceed() {
        var probe = ProbeInFlight()

        guard case .proceed = probe.begin() else {
            return XCTFail("an idle guard lets the probe run")
        }
        XCTAssertTrue(probe.isBusy)
    }

    /// A second call while a pass is in flight gets the last known answer and
    /// starts no capture: the busy guard stays busy.
    func testBeginWhileBusyReturnsTheLastKnownAnswer() {
        var probe = ProbeInFlight()
        guard case .proceed(let pass) = probe.begin() else {
            return XCTFail("setup: the first begin proceeds")
        }
        probe.timeOut(pass, answer: false)

        guard case .answer(let known) = probe.begin() else {
            return XCTFail("a busy guard must answer instead of proceeding")
        }
        XCTAssertEqual(known, false, "the refresh repeats the last known answer instead of launching another probe")
        XCTAssertTrue(probe.isBusy, "the pass this answer came from is still in flight")
    }

    /// While the very first probe is still in flight there is no known answer
    /// yet; the refresh gets `false`, because nothing has been captured and
    /// nothing may be claimed.
    func testBeginWhileBusyWithNoKnownAnswerAnswersFalse() {
        var probe = ProbeInFlight()
        _ = probe.begin()

        guard case .answer(let known) = probe.begin() else {
            return XCTFail("a busy guard must answer instead of proceeding")
        }
        XCTAssertEqual(known, false)
        XCTAssertTrue(probe.isBusy)
    }

    /// An expired wait records what the caller answered but keeps the pass in
    /// flight: the capture it abandoned is still running, so the next refresh
    /// must repeat the answer instead of starting another capture.
    func testTimeOutRecordsTheAnswerAndKeepsThePassInFlight() {
        var probe = ProbeInFlight()
        guard case .proceed(let pass) = probe.begin() else {
            return XCTFail("setup: the first begin proceeds")
        }

        probe.timeOut(pass, answer: false)

        XCTAssertEqual(probe.lastAnswer, false)
        XCTAssertTrue(probe.isBusy, "the abandoned capture is still running")

        guard case .answer(let known) = probe.begin() else {
            return XCTFail("the pass is still in flight, so the next begin answers")
        }
        XCTAssertEqual(known, false)
    }

    /// When the abandoned capture actually completes, its real answer is
    /// recorded and the next probe is freed to run.
    func testCompletionAfterTimeOutRecordsTheRealAnswerAndFreesTheGuard() {
        var probe = ProbeInFlight()
        guard case .proceed(let pass) = probe.begin() else {
            return XCTFail("setup: the first begin proceeds")
        }
        probe.timeOut(pass, answer: false)

        probe.finish(pass, answer: true)

        XCTAssertFalse(probe.isBusy)
        XCTAssertEqual(probe.lastAnswer, true)

        guard case .proceed = probe.begin() else {
            return XCTFail("a finished pass frees the next probe to run")
        }
        XCTAssertTrue(probe.isBusy)
    }

    /// A pass whose capture answered within the wait is finished directly, and
    /// the answer it recorded survives.
    func testFinishRecordsTheAnswerAndFreesTheGuard() {
        var probe = ProbeInFlight()
        guard case .proceed(let pass) = probe.begin() else {
            return XCTFail("setup: the first begin proceeds")
        }

        probe.finish(pass, answer: false)

        XCTAssertFalse(probe.isBusy)
        XCTAssertEqual(probe.lastAnswer, false)

        guard case .proceed = probe.begin() else {
            return XCTFail("a finished pass frees the next probe to run")
        }
    }

    /// A completion from a pass a newer probe displaced is ignored: it must not
    /// free the newer pass or overwrite its answer.
    func testStalePassFinishIsIgnored() {
        var probe = ProbeInFlight()
        guard case .proceed(let first) = probe.begin() else {
            return XCTFail("setup: the first begin proceeds")
        }
        probe.finish(first, answer: true)

        guard case .proceed(let second) = probe.begin() else {
            return XCTFail("setup: the second begin proceeds")
        }

        probe.finish(first, answer: false)

        XCTAssertTrue(probe.isBusy, "the second pass is still in flight")
        XCTAssertEqual(probe.lastAnswer, true, "the stale completion changed nothing")
        _ = second
    }

    /// The same for an expired wait from a displaced pass.
    func testStalePassTimeOutIsIgnored() {
        var probe = ProbeInFlight()
        guard case .proceed(let first) = probe.begin() else {
            return XCTFail("setup: the first begin proceeds")
        }
        probe.finish(first, answer: true)

        guard case .proceed(let second) = probe.begin() else {
            return XCTFail("setup: the second begin proceeds")
        }

        probe.timeOut(first, answer: false)

        XCTAssertTrue(probe.isBusy)
        XCTAssertEqual(probe.lastAnswer, true, "the stale wait expiry changed nothing")
        _ = second
    }

    /// A finished `false` pass still frees the guard: one bounded failure must
    /// not wedge the probe closed forever.
    func testAFinishedFalseProbeDoesNotStick() {
        var probe = ProbeInFlight()
        guard case .proceed(let first) = probe.begin() else {
            return XCTFail("setup: the first begin proceeds")
        }
        probe.finish(first, answer: false)

        guard case .proceed(let second) = probe.begin() else {
            return XCTFail("a finished false pass frees the next probe")
        }
        probe.finish(second, answer: true)

        XCTAssertEqual(probe.lastAnswer, true)

        guard case .proceed(let third) = probe.begin() else {
            return XCTFail("the guard is idle after finish; begin must proceed")
        }
        XCTAssertTrue(probe.isBusy)
        _ = third
    }
}
