import XCTest
@testable import StareCore

final class PointerPulseTests: XCTestCase {
    func testNoClickMeansScaleOneForever() {
        var pulse = PointerPulse()
        XCTAssertFalse(pulse.isPulsing(at: 0))
        XCTAssertEqual(pulse.scale(at: 0), 1)
        XCTAssertEqual(pulse.scale(at: 60), 1)
        XCTAssertEqual(pulse.scale(at: 100_000), 1)
    }

    func testClickAtT0GivesScaleOneAtT0() {
        var pulse = PointerPulse()
        pulse.start(at: 100)
        XCTAssertTrue(pulse.isPulsing(at: 100))
        XCTAssertEqual(pulse.scale(at: 100), 1)
    }

    func testScaleReachesPeakShortlyAfterTheClickAndNowhereEarlier() {
        var pulse = PointerPulse()
        pulse.start(at: 0)
        // Before the rise ends nothing exceeds the peak.
        var t: TimeInterval = 0
        while t < pulse.riseDuration {
            XCTAssertLessThanOrEqual(pulse.scale(at: t), pulse.peakScale + 0.001)
            t += pulse.riseDuration / 10
        }
        // The peak itself is reached at the end of the rise, shortly after
        // the click, and stays there exactly one instant.
        XCTAssertEqual(pulse.scale(at: pulse.riseDuration), pulse.peakScale, accuracy: 0.001)
    }

    func testPulseIsBackToOneByTheEndAndStaysThere() {
        var pulse = PointerPulse()
        pulse.start(at: 0)
        XCTAssertEqual(pulse.scale(at: pulse.duration), 1, accuracy: 0.001)
        XCTAssertEqual(pulse.scale(at: pulse.duration + 0.5), 1)
        XCTAssertEqual(pulse.scale(at: pulse.duration + 100), 1)
        XCTAssertFalse(pulse.isPulsing(at: pulse.duration))
    }

    func testEverySampleDuringThePulseStaysBetweenDipAndPeak() {
        var pulse = PointerPulse()
        pulse.start(at: 0)
        var t: TimeInterval = 0
        while t <= pulse.duration {
            let scale = pulse.scale(at: t)
            XCTAssertGreaterThanOrEqual(scale, pulse.dipScale - 0.001)
            XCTAssertLessThanOrEqual(scale, pulse.peakScale + 0.001)
            t += pulse.duration / 200
        }
    }

    func testClickDuringAPulseRestartsItFromTheNewInstant() {
        var pulse = PointerPulse()
        pulse.start(at: 0)
        // A second click mid-pulse: the scale restarts from rest at the new
        // anchor, regardless of where the old pulse was.
        pulse.start(at: pulse.duration / 2)
        XCTAssertEqual(pulse.scale(at: pulse.duration / 2), 1)
        XCTAssertEqual(pulse.scale(at: pulse.duration / 2 + pulse.riseDuration), pulse.peakScale, accuracy: 0.001)
        // Times before the new anchor read as rest.
        XCTAssertEqual(pulse.scale(at: 0), 1)
    }

    func testScaleIsStrictlyBiggerThanOneSomeWhereInTheRise() {
        var pulse = PointerPulse()
        pulse.start(at: 0)
        let midRise = pulse.scale(at: pulse.riseDuration / 2)
        XCTAssertGreaterThan(midRise, 1)
        XCTAssertLessThan(midRise, pulse.peakScale)
    }
}
