import Foundation
import XCTest

@testable import StareCore

/// Tests for the update checker (T3/S6): pure semver comparison, calendar-based
/// schedule logic, and an injected feed. The app is not notarized, so the
/// checker only informs and links — it never installs anything, and a release
/// at or below the running version is never reported.

/// Gregorian UTC calendar and fixed dates, so time-dependent code has nothing
/// to inject from the environment.
private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private struct FeedError: Error {}

/// Recording fake feed: either releases a fixed value or always throws.
private actor FakeUpdateFeed: UpdateFeed {
    let release: UpdateRelease?
    let error: Error?
    private(set) var callCount = 0

    init(release: UpdateRelease? = nil, error: Error? = nil) {
        self.release = release
        self.error = error
    }

    func latestRelease() async throws -> UpdateRelease? {
        callCount += 1
        if let error { throw error }
        return release
    }
}

private func makeRelease(_ major: Int, _ minor: Int, _ patch: Int) -> UpdateRelease {
    UpdateRelease(
        version: SemanticVersion(major: major, minor: minor, patch: patch)!,
        pageURL: URL(string: "https://github.com/alvaldes/stare/releases/tag/v\(major).\(minor).\(patch)")!,
        highlights: ["New marker styles"]
    )
}

final class UpdateCheckerTests: XCTestCase {
    // MARK: SemanticVersion parsing

    func testParsesCoreVersionsWithOptionalLeadingV() {
        XCTAssertEqual(SemanticVersion(string: "1.2.3"), SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(SemanticVersion(string: "v1.2.3"), SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(SemanticVersion(string: "V1.2.3"), SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(SemanticVersion(string: "0.0.0"), SemanticVersion(major: 0, minor: 0, patch: 0))
    }

    func testToleratesTrailingSuffixByComparingTheNumericCore() {
        XCTAssertEqual(SemanticVersion(string: "1.2.0-beta.1"), SemanticVersion(major: 1, minor: 2, patch: 0))
        XCTAssertEqual(SemanticVersion(string: "2.0.0+build.7"), SemanticVersion(major: 2, minor: 0, patch: 0))
    }

    func testFailsToParseAnythingElse() {
        XCTAssertNil(SemanticVersion(string: ""))
        XCTAssertNil(SemanticVersion(string: "1.2"))
        XCTAssertNil(SemanticVersion(string: "1.2.3.4"))
        XCTAssertNil(SemanticVersion(string: "abc"))
        XCTAssertNil(SemanticVersion(string: "1.2.x"))
        XCTAssertNil(SemanticVersion(string: "version 1.2.3"))
        XCTAssertNil(SemanticVersion(string: "1.2.3 "))
    }

    func testCodableRoundTripsThroughTheVersionString() throws {
        let version = SemanticVersion(major: 1, minor: 2, patch: 3)
        let data = try JSONEncoder().encode(version)
        XCTAssertEqual(try JSONDecoder().decode(SemanticVersion.self, from: data), version)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"1.2.3\"")
    }

    // MARK: Version comparison table

    func testComparisonTable() {
        let v = SemanticVersion.init(string:)
        XCTAssertLessThan(v("0.9.0")!, v("0.10.0")!)
        XCTAssertLessThan(v("1.9.9")!, v("2.0.0")!)
        XCTAssertLessThan(v("1.2.9")!, v("1.2.10")!)
        XCTAssertLessThan(v("0.9.0")!, v("0.10.0-beta.1")!) // suffix ignored
        XCTAssertEqual(v("1.2.3")!, v("1.2.3")!)
        XCTAssertEqual(v("v1.2.3")!, v("1.2.3-beta.1")!) // core comparison only
        XCTAssertFalse(v("1.2.3-beta.1")! < v("1.2.3")!)
    }

    // MARK: Schedule due logic

    func testNeverIsNeverDue() {
        XCTAssertFalse(UpdateCheckSchedule.never.isDue(lastCheck: nil, now: date(2026, 11, 21), calendar: calendar))
        XCTAssertFalse(UpdateCheckSchedule.never.isDue(lastCheck: date(2025, 1, 1), now: date(2026, 11, 21), calendar: calendar))
    }

    func testDailyIsDueWithoutAPreviousCheckAndAfterACalendarDay() {
        let last = date(2026, 11, 21, 23, 59)
        XCTAssertTrue(UpdateCheckSchedule.daily.isDue(lastCheck: nil, now: date(2026, 11, 21), calendar: calendar))
        XCTAssertFalse(UpdateCheckSchedule.daily.isDue(lastCheck: last, now: date(2026, 11, 21, 23, 59), calendar: calendar))
        XCTAssertTrue(UpdateCheckSchedule.daily.isDue(lastCheck: last, now: date(2026, 11, 22), calendar: calendar))
    }

    func testWeeklyIsDueWithoutAPreviousCheckAndAfterACalendarWeek() {
        let last = date(2026, 11, 16, 12) // Monday
        XCTAssertTrue(UpdateCheckSchedule.weekly.isDue(lastCheck: nil, now: date(2026, 11, 21), calendar: calendar))
        XCTAssertFalse(UpdateCheckSchedule.weekly.isDue(lastCheck: last, now: date(2026, 11, 21), calendar: calendar)) // same week
        XCTAssertTrue(UpdateCheckSchedule.weekly.isDue(lastCheck: last, now: date(2026, 11, 23), calendar: calendar)) // next Monday
    }

    func testScheduleCasesAndTitles() {
        XCTAssertEqual(UpdateCheckSchedule.allCases, [.never, .daily, .weekly])
        XCTAssertEqual(UpdateCheckSchedule.never.title, "Never")
        XCTAssertEqual(UpdateCheckSchedule.daily.title, "Daily")
        XCTAssertEqual(UpdateCheckSchedule.weekly.title, "Weekly")
    }

    // MARK: Status message wording (pinned)

    func testStatusMessagesArePinnedInEnglish() {
        XCTAssertEqual(
            UpdateStatus(available: nil, lastCheck: nil, lastCheckFailed: false).message,
            "Not checked yet"
        )
        XCTAssertEqual(
            UpdateStatus(available: nil, lastCheck: date(2026, 11, 21), lastCheckFailed: false).message,
            "Stare is up to date"
        )
        XCTAssertEqual(
            UpdateStatus(available: nil, lastCheck: nil, lastCheckFailed: true).message,
            "Couldn't reach GitHub"
        )
        XCTAssertEqual(
            UpdateStatus(available: makeRelease(1, 2, 0), lastCheck: date(2026, 11, 21), lastCheckFailed: false).message,
            "Stare 1.2.0 is available"
        )
    }

    // MARK: UpdateChecker with an injected feed

    func testNewerVersionIsReportedAvailableAndSetsLastCheck() async {
        let feed = FakeUpdateFeed(release: makeRelease(1, 2, 0))
        let checker = UpdateChecker(feed: feed, currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0)!)
        let now = date(2026, 11, 21, 10)
        await checker.checkNow(at: now)

        let status = await checker.status
        XCTAssertEqual(status.available, makeRelease(1, 2, 0))
        XCTAssertEqual(status.lastCheck, now)
        XCTAssertFalse(status.lastCheckFailed)
        XCTAssertEqual(status.message, "Stare 1.2.0 is available")
    }

    func testSameAndOlderVersionsAreNotReportedAvailable() async {
        let same = FakeUpdateFeed(release: makeRelease(1, 0, 0))
        let sameChecker = UpdateChecker(feed: same, currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0)!)
        await sameChecker.checkNow(at: date(2026, 11, 21))
        let sameStatus = await sameChecker.status
        XCTAssertNil(sameStatus.available)
        XCTAssertEqual(sameStatus.message, "Stare is up to date")

        let older = FakeUpdateFeed(release: makeRelease(0, 9, 0))
        let olderChecker = UpdateChecker(feed: older, currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0)!)
        await olderChecker.checkNow(at: date(2026, 11, 21))
        let olderStatus = await olderChecker.status
        XCTAssertNil(olderStatus.available)
        XCTAssertNotNil(olderStatus.lastCheck)
    }

    func testNoReleaseFromTheFeedIsUpToDate() async {
        let feed = FakeUpdateFeed(release: nil)
        let checker = UpdateChecker(feed: feed, currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0)!)
        await checker.checkNow(at: date(2026, 11, 21))
        let status = await checker.status
        XCTAssertNil(status.available)
        XCTAssertEqual(status.message, "Stare is up to date")
    }

    func testThrowingFeedOnAFreshCheckerSetsLastCheckFailed() async {
        let throwing = FakeUpdateFeed(error: FeedError())
        let checker = UpdateChecker(feed: throwing, currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0)!)
        await checker.checkNow(at: date(2026, 11, 21, 9))

        let failed = await checker.status
        XCTAssertTrue(failed.lastCheckFailed)
        XCTAssertNil(failed.available)
        XCTAssertNil(failed.lastCheck)
        XCTAssertEqual(failed.message, "Couldn't reach GitHub")
    }

    func testFailureKeepsPreviousStatusIntactIncludingLastCheckAndAvailable() async throws {
        // A feed that works the first time and throws afterwards, so the same
        // checker exercises success-then-failure.
        actor FlakyFeed: UpdateFeed {
            private var throwNext = false
            func failNext() { throwNext = true }
            func clearFailure() { throwNext = false }
            func latestRelease() async throws -> UpdateRelease? {
                if throwNext { throw FeedError() }
                return makeRelease(2, 0, 0)
            }
        }
        let feed = FlakyFeed()
        let checker = UpdateChecker(feed: feed, currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0)!)
        let first = date(2026, 11, 20, 8)
        await checker.checkNow(at: first)
        let afterSuccess = await checker.status
        XCTAssertEqual(afterSuccess.available, makeRelease(2, 0, 0))
        XCTAssertEqual(afterSuccess.lastCheck, first)

        await feed.failNext()
        let second = date(2026, 11, 21, 9)
        await checker.checkNow(at: second)
        let afterFailure = await checker.status
        XCTAssertTrue(afterFailure.lastCheckFailed)
        XCTAssertEqual(afterFailure.available, makeRelease(2, 0, 0)) // previous status intact
        XCTAssertEqual(afterFailure.lastCheck, first) // failure does not move lastCheck
        XCTAssertEqual(afterFailure.message, "Stare 2.0.0 is available") // availability wins

        // A later successful check clears the failure flag.
        await feed.clearFailure()
        let third = date(2026, 11, 22, 10)
        await checker.checkNow(at: third)
        let recovered = await checker.status
        XCTAssertFalse(recovered.lastCheckFailed)
        XCTAssertEqual(recovered.lastCheck, third)
    }

    func testCheckIfDueRespectsTheScheduleAndPassedLastCheck() async {
        let feed = FakeUpdateFeed(release: makeRelease(2, 0, 0))

        // never: the feed must not be contacted at all.
        let neverChecker = UpdateChecker(feed: feed, currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0)!)
        await neverChecker.checkIfDue(now: date(2026, 11, 21), schedule: .never, lastCheck: nil, calendar: calendar)
        let neverStatus = await neverChecker.status
        XCTAssertNil(neverStatus.lastCheck)
        XCTAssertEqual(neverStatus.message, "Not checked yet")
        let neverCalls = await feed.callCount

        // daily, checked today: not due, no call.
        let warmChecker = UpdateChecker(feed: feed, currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0)!)
        await warmChecker.checkIfDue(now: date(2026, 11, 21), schedule: .daily, lastCheck: date(2026, 11, 21, 8), calendar: calendar)
        let warmCalls = await feed.callCount

        // daily, stale or never checked: due, and the check runs.
        let dueChecker = UpdateChecker(feed: feed, currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0)!)
        await dueChecker.checkIfDue(now: date(2026, 11, 21), schedule: .daily, lastCheck: date(2026, 11, 20), calendar: calendar)
        let dueStatus = await dueChecker.status
        XCTAssertEqual(dueStatus.available, makeRelease(2, 0, 0))
        let dueCalls = await feed.callCount

        let nilChecker = UpdateChecker(feed: feed, currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0)!)
        await nilChecker.checkIfDue(now: date(2026, 11, 21), schedule: .weekly, lastCheck: nil, calendar: calendar)
        let nilCalls = await feed.callCount

        XCTAssertEqual(neverCalls, 0)
        XCTAssertEqual(warmCalls, neverCalls)
        XCTAssertEqual(dueCalls, warmCalls + 1)
        XCTAssertEqual(nilCalls, dueCalls + 1)
    }

    func testInitialStatusIsNotCheckedYet() async {
        let feed = FakeUpdateFeed(release: makeRelease(2, 0, 0))
        let checker = UpdateChecker(feed: feed, currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0)!)
        let status = await checker.status
        XCTAssertNil(status.available)
        XCTAssertNil(status.lastCheck)
        XCTAssertFalse(status.lastCheckFailed)
        XCTAssertEqual(status.message, "Not checked yet")
    }
}
