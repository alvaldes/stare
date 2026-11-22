import Combine
import Foundation

/// Observable shell over `ScreenRecordingPermission` for the Setup Guide's
/// SwiftUI view. `ScreenRecordingPermission` is a plain `@MainActor` class with
/// an `onChange` callback, so the window keeps publishing `access` from it and
/// the UI updates without polling races.
///
/// Lives in the core module rather than next to the window so the mirroring
/// rules — a model created after the grant landed, and a refresh into an
/// unchanged state — are covered by tests instead of only by a screenshot.
@MainActor
public final class OnboardingModel: ObservableObject {
    public let permission: ScreenRecordingPermission

    @Published public private(set) var access: ScreenRecordingAccess = .denied

    /// Also read by the window controller, which stops refreshing once the
    /// state is terminal for this session.
    public var onAccessChanged: ((ScreenRecordingAccess) -> Void)?

    public init(permission: ScreenRecordingPermission) {
        self.permission = permission
        // Seed from the shared state: the guide can open after Settings
        // already refreshed, and `onChange` only fires on a *change*, so
        // starting at `.denied` would leave this model permanently behind.
        access = permission.access
        permission.onChange = { [weak self] access in
            self?.publish(access)
        }
    }

    /// Forwards to the permission model: re-reads the three TCC answers, and
    /// mirrors the answer it returns.
    ///
    /// `refresh()` is the only way to observe a state the permission already
    /// held: `onChange` stays silent when nothing changed, so a model that only
    /// listened to it would keep showing an older state — the guide saying "no"
    /// while Settings already said yes.
    @discardableResult
    public func refresh() -> ScreenRecordingAccess {
        let access = permission.refresh()
        publish(access)
        return access
    }

    /// Mirrors a state and reports it to the controller, which stops polling
    /// on a terminal state. A repeated same value changes nothing.
    private func publish(_ newValue: ScreenRecordingAccess) {
        guard newValue != access else { return }
        access = newValue
        onAccessChanged?(newValue)
    }

    /// The guide's primary button: prompt the system, then land the user on
    /// the Screen Recording pane so they only have to flip the switch (S1).
    public func requestAccess() {
        permission.requestAccess()
    }

    public func openSettings() {
        permission.openSettings()
    }

    /// The guide's action hierarchy for the current state (T3/S2–S3): exactly
    /// one primary action and at most one secondary, decided by
    /// `OnboardingActionPlan` so the view renders the rule instead of owning
    /// it.
    public var actionPlan: OnboardingActionPlan {
        OnboardingActionPlan.plan(for: access)
    }
}
