import CoreGraphics
import XCTest
@testable import StareCore

/// The remembered rectangle (S11, T2b slice B): the last confirmed area
/// becomes the starting marquee of the next `⇧S` — a plain `Return` confirms
/// and captures it with no drag, a newer confirmation replaces it, and
/// deactivation clears it. Session-scoped pure state: nothing persists,
/// nothing reaches Settings.
final class AreaCaptureMemoryTests: XCTestCase {
    func testAFreshMemoryHasNothingToPreload() {
        var memory = AreaCaptureMemory()
        XCTAssertNil(memory.preload)
    }

    func testAConfirmedAreaBecomesThePreload() {
        var memory = AreaCaptureMemory()
        let rect = CGRect(x: 100, y: 100, width: 300, height: 200)
        memory.confirm(rect)
        XCTAssertEqual(memory.preload, rect)
    }

    func testANewerConfirmationReplacesTheRememberedArea() {
        var memory = AreaCaptureMemory()
        memory.confirm(CGRect(x: 100, y: 100, width: 300, height: 200))
        let newer = CGRect(x: 400, y: 300, width: 120, height: 70)
        memory.confirm(newer)
        XCTAssertEqual(memory.preload, newer, "one rectangle is remembered: the newest")
    }

    func testAStrayClickNeverPoisonsTheMemory() {
        var memory = AreaCaptureMemory()
        let worthy = CGRect(x: 100, y: 100, width: 300, height: 200)
        memory.confirm(worthy)

        XCTAssertFalse(
            memory.confirm(CGRect(x: 50, y: 50, width: 3, height: 3)),
            "below the capture minimum is a stray click, not a confirmed area")
        XCTAssertEqual(memory.preload, worthy)

        // The minimum itself counts, the rule the drag already trusts.
        XCTAssertTrue(memory.confirm(CGRect(x: 50, y: 50, width: 4, height: 4)))
    }

    func testDeactivationClearsTheMemory() {
        var memory = AreaCaptureMemory()
        memory.confirm(CGRect(x: 100, y: 100, width: 300, height: 200))

        XCTAssertTrue(memory.clear())
        XCTAssertNil(memory.preload, "the memory dies with the overlay session")
        XCTAssertFalse(memory.clear(), "clearing an empty memory changes nothing")
    }

    func testAfterAClearANewConfirmationWorksAgain() {
        var memory = AreaCaptureMemory()
        memory.confirm(CGRect(x: 100, y: 100, width: 300, height: 200))
        memory.clear()

        let fresh = CGRect(x: 10, y: 10, width: 40, height: 40)
        memory.confirm(fresh)
        XCTAssertEqual(memory.preload, fresh)
    }
}
