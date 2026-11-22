import XCTest
@testable import StareCore

/// The probe's attempt loop, with the capture injected so the remembering rule
/// is testable: the wiring that runs it lives in the untested `Stare` target,
/// and the first version of this code shipped the rule as dead code because
/// nothing could see the loop.
final class ProbeCapturePlanTests: XCTestCase {
    private let displayA: CGDirectDisplayID = 1
    private let displayB: CGDirectDisplayID = 2

    /// The first probe of a display whose cheap size fails: two captures, the
    /// second at full size, and the full size is what it remembers.
    func testFirstProbeFallsBackAndRemembersFullSize() {
        var plan = ProbeCapturePlan()
        var attempted: [CGFloat] = []

        let captured = plan.run(displayID: displayA, displayDownscale: 9) { downscale in
            attempted.append(downscale)
            return downscale == 1 ? nil : ProbeStubError.reducedRejected
        }

        XCTAssertTrue(captured)
        XCTAssertEqual(attempted, [9, 1])
        XCTAssertEqual(plan.lastSucceeded[displayA], 1)
    }

    /// Once a size worked, the next probe pays for one capture: the permission
    /// refresh runs about once a second and doubling it is the cost the
    /// reviewers flagged.
    func testSecondProbeUsesTheRememberedSizeOnly() {
        var plan = ProbeCapturePlan()
        _ = plan.run(displayID: displayA, displayDownscale: 9) { $0 == 1 ? nil : ProbeStubError.reducedRejected }

        var attempted: [CGFloat] = []
        let captured = plan.run(displayID: displayA, displayDownscale: 9) { downscale in
            attempted.append(downscale)
            return nil
        }

        XCTAssertTrue(captured)
        XCTAssertEqual(attempted, [1])
    }

    /// A cheap size that works is remembered too, and the full-size fallback is
    /// never paid for again.
    func testWorkingReducedSizeIsRemembered() {
        var plan = ProbeCapturePlan()
        _ = plan.run(displayID: displayA, displayDownscale: 9) { _ in nil }

        XCTAssertEqual(plan.lastSucceeded[displayA], 9)

        var attempted: [CGFloat] = []
        _ = plan.run(displayID: displayA, displayDownscale: 9) { downscale in
            attempted.append(downscale)
            return nil
        }
        XCTAssertEqual(attempted, [9])
    }

    /// Every attempt failing answers false and remembers nothing, so the next
    /// probe starts over instead of locking onto a failing size.
    func testAllAttemptsFailingRemembersNothing() {
        var plan = ProbeCapturePlan()
        var attempted: [CGFloat] = []

        let captured = plan.run(displayID: displayA, displayDownscale: 9) { downscale in
            attempted.append(downscale)
            return ProbeStubError.reducedRejected
        }

        XCTAssertFalse(captured)
        XCTAssertEqual(attempted, [9, 1], "both sizes are tried before giving up")
        XCTAssertNil(plan.lastSucceeded[displayA])
    }

    /// A display at the floor has a single attempt and never repeats it.
    func testDisplayAtTheFloorAttemptsOnce() {
        var plan = ProbeCapturePlan()
        var attempted: [CGFloat] = []

        _ = plan.run(displayID: displayA, displayDownscale: 1) { downscale in
            attempted.append(downscale)
            return nil
        }

        XCTAssertEqual(attempted, [1])
    }

    /// R3-001: the memory is per display. A factor that worked on one display
    /// must not become another display's only attempt — that display still gets
    /// the full-size fallback the baseline always gave it.
    func testEachDisplayKeepsItsOwnRememberedSize() {
        var plan = ProbeCapturePlan()
        _ = plan.run(displayID: displayA, displayDownscale: 9) { $0 == 1 ? nil : ProbeStubError.reducedRejected }
        XCTAssertEqual(plan.lastSucceeded[displayA], 1)

        var attemptedOnB: [CGFloat] = []
        let captured = plan.run(displayID: displayB, displayDownscale: 5) { downscale in
            attemptedOnB.append(downscale)
            return nil
        }

        XCTAssertTrue(captured)
        XCTAssertEqual(attemptedOnB, [5], "display B tries its own reduced size, not display A's")
        XCTAssertEqual(plan.lastSucceeded[displayB], 5)
        XCTAssertEqual(plan.lastSucceeded[displayA], 1, "display A keeps its own answer")
    }

    /// R4-1: a remembered size that fails is forgotten, and the sizes it had
    /// displaced are tried in the same pass, so a transient failure cannot leave
    /// the probe answering "cannot capture" forever.
    func testTransientFailureOfTheRememberedSizeFallsBackInTheSamePass() {
        var plan = ProbeCapturePlan()
        _ = plan.run(displayID: displayA, displayDownscale: 9) { _ in nil }
        XCTAssertEqual(plan.lastSucceeded[displayA], 9)

        var attempted: [CGFloat] = []
        let captured = plan.run(displayID: displayA, displayDownscale: 9) { downscale in
            attempted.append(downscale)
            return downscale == 9 ? ProbeStubError.reducedRejected : nil
        }

        XCTAssertTrue(captured, "the full-size fallback still answered in this pass")
        XCTAssertEqual(attempted, [9, 1])
        XCTAssertEqual(plan.lastSucceeded[displayA], 1)
    }
}

/// A capture failure the plan only has to distinguish from success.
enum ProbeStubError: Error {
    case reducedRejected
}
