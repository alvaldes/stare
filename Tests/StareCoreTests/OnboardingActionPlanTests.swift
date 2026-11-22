import XCTest

@testable import StareCore

/// The Setup Guide's action hierarchy rule (S2–S3), extracted here so it is
/// testable: every permission state shows exactly one primary action, at most
/// one secondary action, and the action kinds — not the view — carry which is
/// which. With the permission granted, System Settings must not appear at
/// all: it used to stay the window's most prominent button, only `.disabled`.
///
/// The view renders `primary` prominently and `secondary` bordered; this test
/// pins the mapping `ScreenRecordingAccess → OnboardingActionPlan` itself.
final class OnboardingActionPlanTests: XCTestCase {
    // MARK: denied

    /// `.denied`: the only way forward is System Settings, so it is the
    /// single primary action with no secondary beside it.
    func testDeniedShowsSystemSettingsAsTheOnlyPrimaryAction() {
        let plan = OnboardingActionPlan.plan(for: .denied)

        XCTAssertEqual(plan.primary.kind, .openSystemSettings)
        XCTAssertEqual(plan.primary.label, "Open System Settings…")
        XCTAssertNil(plan.secondary, "denied has exactly one action")
        XCTAssertEqual(plan.all.count, 1)
    }

    // MARK: grantedPendingRestart

    /// `.grantedPendingRestart`: restarting Stare is primary; re-authorizing
    /// in System Settings (the repair that survives an app update) is the
    /// single secondary action.
    func testGrantedPendingRestartShowsRestartPrimaryAndSettingsSecondary() {
        let plan = OnboardingActionPlan.plan(for: .grantedPendingRestart)

        XCTAssertEqual(plan.primary.kind, .restartStare)
        XCTAssertEqual(plan.primary.label, "Restart Stare")
        XCTAssertEqual(plan.secondary?.kind, .openSystemSettings)
        XCTAssertEqual(plan.secondary?.label, "Open System Settings…")
        XCTAssertEqual(plan.all.count, 2, "restart primary, settings secondary, nothing else")
    }

    // MARK: granted

    /// `.granted`: Continue is primary and System Settings is absent — not
    /// primary, not secondary, not disabled. It must no longer be the
    /// window's most prominent action once it can do nothing.
    func testGrantedShowsContinuePrimaryAndNoSystemSettingsAction() {
        let plan = OnboardingActionPlan.plan(for: .granted)

        XCTAssertEqual(plan.primary.kind, .continueOnboarding)
        XCTAssertEqual(plan.primary.label, "Continue")
        XCTAssertNil(plan.secondary)
        XCTAssertFalse(
            plan.all.contains { $0.kind == .openSystemSettings },
            "with the permission granted, System Settings must not appear as an action at all"
        )
    }

    // MARK: copy

    /// The real bug's contract, pinned at the hierarchy level too: the
    /// pending-restart copy names both remedies (restart *and* System
    /// Settings), and the plan must keep offering them — restart primary,
    /// System Settings secondary — even if the wording changes later.
    func testGrantedPendingRestartPlanKeepsBothRemediesTheDetailCopyNames() {
        let detail = ScreenRecordingAccess.grantedPendingRestart.detail
        XCTAssertTrue(
            detail.localizedCaseInsensitiveContains("restart"),
            "the pending-restart detail must name the restart remedy"
        )
        XCTAssertTrue(
            detail.localizedCaseInsensitiveContains("System Settings"),
            "the pending-restart detail must also name the System Settings remedy"
        )

        let plan = OnboardingActionPlan.plan(for: .grantedPendingRestart)
        XCTAssertEqual(plan.primary.kind, .restartStare)
        XCTAssertEqual(plan.secondary?.kind, .openSystemSettings)
    }

    /// Every action carries a non-empty label for the button it becomes.
    func testEveryActionCarriesANonEmptyLabel() {
        for access in [ScreenRecordingAccess.denied, .granted, .grantedPendingRestart] {
            let plan = OnboardingActionPlan.plan(for: access)
            for action in plan.all {
                XCTAssertFalse(action.label.isEmpty, "\(access): \(action.kind) needs a label")
            }
        }
    }

    /// A granted permission is one button, and it is not Settings: the whole
    /// point of the hierarchy is that nothing competes with Continue.
    func testGrantedPlanIsExactlyOneAction() {
        let plan = OnboardingActionPlan.plan(for: .granted)

        XCTAssertEqual(plan.all.count, 1)
        XCTAssertEqual(plan.all.map(\.kind), [.continueOnboarding])
    }

    /// The order the view renders in: the primary first, then the secondary.
    /// Swapping them would put the supporting path ahead of the main one.
    func testPlanOrderIsPrimaryThenSecondary() {
        XCTAssertEqual(OnboardingActionPlan.plan(for: .denied).all.map(\.kind), [.openSystemSettings])
        XCTAssertEqual(
            OnboardingActionPlan.plan(for: .grantedPendingRestart).all.map(\.kind),
            [.restartStare, .openSystemSettings]
        )
        XCTAssertEqual(OnboardingActionPlan.plan(for: .granted).all.map(\.kind), [.continueOnboarding])
    }
}
