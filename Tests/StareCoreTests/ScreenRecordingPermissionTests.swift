import XCTest

@testable import StareCore

/// Tests for the Screen Recording permission state machine (T4/S1–S2): an
/// injected client answers the three TCC questions (preflight, request, real
/// capture probe) and the model turns the answers into an observable
/// `ScreenRecordingAccess`. Every test asserts both the observed state and the
/// exact client call log — what the client was asked, and what it was not.

/// Recording fake: every method increments a counter and returns a value the
/// test set beforehand, so each rule can assert the calls that happened *and*
/// the calls that must not happen. Tests confine it to the main actor, so the
/// mutable state never races.
private final class FakeScreenRecordingClient: ScreenRecordingClient, @unchecked Sendable {
    var preflightResult = false
    var requestResult = false
    var canCaptureResult = false

    private(set) var preflightCalls = 0
    private(set) var requestCalls = 0
    private(set) var canCaptureCalls = 0
    private(set) var openSettingsCalls = 0

    func preflight() -> Bool {
        preflightCalls += 1
        return preflightResult
    }

    func request() -> Bool {
        requestCalls += 1
        return requestResult
    }

    func canCapture() -> Bool {
        canCaptureCalls += 1
        return canCaptureResult
    }

    func openPrivacySettings() {
        openSettingsCalls += 1
    }
}

@MainActor
final class ScreenRecordingPermissionTests: XCTestCase {
    // MARK: refresh — denied

    /// First refresh with preflight false → `.denied`, and nothing else is
    /// asked: no capture probe, no request, no settings round trip.
    func testFirstRefreshPreflightFalseIsDeniedWithoutProbeRequestOrSettings() {
        let client = FakeScreenRecordingClient()
        client.preflightResult = false
        client.canCaptureResult = true  // must not be consulted
        let permission = ScreenRecordingPermission(client: client)
        var changes: [ScreenRecordingAccess] = []
        permission.onChange = { changes.append($0) }

        permission.refresh()

        XCTAssertEqual(permission.access, .denied)
        XCTAssertEqual(client.preflightCalls, 1)
        XCTAssertEqual(client.canCaptureCalls, 0)
        XCTAssertEqual(client.requestCalls, 0)
        XCTAssertEqual(client.openSettingsCalls, 0)
        XCTAssertTrue(changes.isEmpty, "denied → denied is not a change")
    }

    // MARK: refresh — granted

    /// Preflight true and the capture probe succeeds → `.granted`, with
    /// exactly one probe and no request.
    func testPreflightTrueAndProbeTrueIsGranted() {
        let client = FakeScreenRecordingClient()
        client.preflightResult = true
        client.canCaptureResult = true
        let permission = ScreenRecordingPermission(client: client)

        permission.refresh()

        XCTAssertEqual(permission.access, .granted)
        XCTAssertEqual(client.preflightCalls, 1)
        XCTAssertEqual(client.canCaptureCalls, 1)
        XCTAssertEqual(client.requestCalls, 0)
        XCTAssertEqual(client.openSettingsCalls, 0)
    }

    // MARK: refresh — granted but this process still cannot capture

    /// The grant appeared mid-session (a previous refresh saw preflight
    /// false) and the probe still fails → `.grantedPendingRestart`.
    func testGrantAppearedMidSessionAndProbeFailsIsGrantedPendingRestart() {
        let client = FakeScreenRecordingClient()
        let permission = ScreenRecordingPermission(client: client)

        client.preflightResult = false
        client.canCaptureResult = true
        permission.refresh()
        XCTAssertEqual(permission.access, .denied)

        // The user flips the switch in System Settings; TCC now says granted,
        // but this process predates the grant and the probe still fails.
        client.preflightResult = true
        client.canCaptureResult = false
        permission.refresh()

        XCTAssertEqual(permission.access, .grantedPendingRestart)
        XCTAssertEqual(client.preflightCalls, 2)
        XCTAssertEqual(client.canCaptureCalls, 1, "the probe runs only when preflight is true")
        XCTAssertEqual(client.requestCalls, 0)
    }

    /// After a restart the state is the same: a fresh instance whose *first*
    /// refresh already sees preflight true and probe false reports
    /// `.grantedPendingRestart` too. Documented rule — `.denied` would
    /// contradict preflight, and the restart copy is accurate whatever the
    /// grant's age (see `ScreenRecordingPermission.refresh`).
    func testGrantExistedBeforeFirstLaunchAndProbeFailsIsGrantedPendingRestart() {
        let client = FakeScreenRecordingClient()
        client.preflightResult = true
        client.canCaptureResult = false
        let permission = ScreenRecordingPermission(client: client)

        permission.refresh()

        XCTAssertEqual(permission.access, .grantedPendingRestart)
        XCTAssertEqual(permission.access.isGranted, false)
        XCTAssertEqual(client.preflightCalls, 1)
        XCTAssertEqual(client.canCaptureCalls, 1)
    }

    // MARK: onChange

    /// denied → granted fires `onChange` exactly once with the new value;
    /// refreshing again with the same answers fires nothing.
    func testTransitionDeniedToGrantedFiresOnChangeOnceAndStableRefreshFiresNothing() {
        let client = FakeScreenRecordingClient()
        let permission = ScreenRecordingPermission(client: client)
        var changes: [ScreenRecordingAccess] = []
        permission.onChange = { changes.append($0) }

        client.preflightResult = false
        client.canCaptureResult = false
        permission.refresh()
        XCTAssertTrue(changes.isEmpty, "denied → denied is not a change")

        client.preflightResult = true
        client.canCaptureResult = true
        permission.refresh()
        XCTAssertEqual(changes, [.granted])

        permission.refresh()
        permission.refresh()
        XCTAssertEqual(changes, [.granted], "same answer must not notify again")
    }

    // MARK: requestAccess

    /// `requestAccess()` calls `request()` exactly once and returns the
    /// post-request state — here the grant lands immediately, so the caller
    /// observes `.granted`.
    func testRequestAccessCallsRequestOnceAndReturnsPostRequestState() {
        let client = FakeScreenRecordingClient()
        let permission = ScreenRecordingPermission(client: client)

        client.requestResult = true
        client.preflightResult = false
        client.canCaptureResult = true
        XCTAssertEqual(permission.requestAccess(), .denied)
        XCTAssertEqual(permission.access, .denied)

        // The user accepts the system prompt: preflight turns true.
        client.preflightResult = true
        let afterGrant = permission.requestAccess()

        XCTAssertEqual(afterGrant, .granted)
        XCTAssertEqual(permission.access, .granted)
        XCTAssertEqual(client.requestCalls, 2, "one call per requestAccess()")
        XCTAssertEqual(client.preflightCalls, 2, "requestAccess() refreshes exactly once")
        XCTAssertEqual(client.canCaptureCalls, 1, "the probe runs only when preflight is true")
    }

    // MARK: openSettings

    /// `openSettings()` forwards to the client exactly once per call.
    func testOpenSettingsForwardsOncePerCall() {
        let client = FakeScreenRecordingClient()
        let permission = ScreenRecordingPermission(client: client)

        permission.openSettings()
        permission.openSettings()

        XCTAssertEqual(client.openSettingsCalls, 2)
        XCTAssertEqual(client.preflightCalls, 0)
        XCTAssertEqual(client.canCaptureCalls, 0)
        XCTAssertEqual(client.requestCalls, 0)
    }

    // MARK: isGranted

    /// `isGranted` is true only for `.granted`: a pending-restart state can
    /// never be mistaken for a working permission.
    func testIsGrantedIsTrueOnlyForGranted() {
        XCTAssertFalse(ScreenRecordingAccess.denied.isGranted)
        XCTAssertTrue(ScreenRecordingAccess.granted.isGranted)
        XCTAssertFalse(ScreenRecordingAccess.grantedPendingRestart.isGranted)
    }

    // MARK: UI copy

    /// Each state carries English title/detail copy for the onboarding UI,
    /// and the pending-restart detail says the app has to be restarted.
    func testStatesCarryUITitlesAndDetails() {
        for state in [ScreenRecordingAccess.denied, .granted, .grantedPendingRestart] {
            XCTAssertFalse(state.title.isEmpty, "\(state) needs a title")
            XCTAssertFalse(state.detail.isEmpty, "\(state) needs a detail")
        }
        XCTAssertTrue(
            ScreenRecordingAccess.grantedPendingRestart.detail.localizedCaseInsensitiveContains("restart"),
            "the pending-restart detail must tell the user to restart the app"
        )
    }
}
