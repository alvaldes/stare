import XCTest
@testable import StareCore

/// The Setup Guide mirrors `ScreenRecordingPermission` through
/// `OnboardingModel`. The permission only calls `onChange` when the value
/// actually changes, so a model that starts after the grant landed (Settings
/// refreshed first) or that refreshes into an unchanged state must still show
/// the real state. Both cases used to leave the guide stuck on "not granted"
/// while Settings showed green.
@MainActor
final class OnboardingModelTests: XCTestCase {
    /// A client whose answers the test sets directly.
    private final class StubClient: ScreenRecordingClient, @unchecked Sendable {
        var preflighted = true
        var capturable = true

        func preflight() -> Bool { preflighted }
        func request() -> Bool { capturable }
        func canCapture() -> Bool { capturable }
        func openPrivacySettings() {}
    }

    private func grantedPermission() -> ScreenRecordingPermission {
        let permission = ScreenRecordingPermission(client: StubClient())
        _ = permission.refresh()
        XCTAssertEqual(permission.access, .granted)
        return permission
    }

    /// A model created while the permission is already granted shows granted.
    /// This is the Setup Guide opened after Settings already refreshed.
    func testModelCreatedWhileGrantedShowsGranted() {
        let model = OnboardingModel(permission: grantedPermission())

        XCTAssertEqual(model.access, .granted)
    }

    /// Refreshing into a state the permission already held still mirrors it:
    /// `refresh()` is the only path that reports "no change" states.
    func testRefreshMirrorsAStateThatDidNotChange() {
        let permission = grantedPermission()
        let model = OnboardingModel(permission: permission)

        XCTAssertEqual(model.refresh(), .granted)
        XCTAssertEqual(model.access, .granted)
    }

    /// The controller stops its timer when the state becomes terminal, so a
    /// change observed through `refresh()` must reach `onAccessChanged` too.
    func testRefreshReportsAChangeToTheController() {
        let client = StubClient()
        client.preflighted = false
        let permission = ScreenRecordingPermission(client: client)
        _ = permission.refresh()
        XCTAssertEqual(permission.access, .denied)
        let model = OnboardingModel(permission: permission)
        var seen: [ScreenRecordingAccess] = []
        model.onAccessChanged = { seen.append($0) }

        // The user grants Screen Recording while the guide is open.
        client.preflighted = true
        XCTAssertEqual(model.refresh(), .granted)

        XCTAssertEqual(model.access, .granted)
        XCTAssertEqual(seen, [.granted], "the controller needs the change to stop polling")
    }
}
