/// The Setup Guide's action hierarchy, decided once per permission state
/// (T3/S2–S3). This is the tested rule the guide's view renders: every state
/// shows exactly one **primary** action and at most one **secondary** action,
/// and "Not now" — which the view keeps constant in the window's footer — is
/// deliberately not part of the per-state hierarchy.
///
/// Pure and AppKit-free: it turns a `ScreenRecordingAccess` into kinds and
/// labels, and the view adds nothing of its own beyond mapping each kind to
/// its existing callback. The rules it pins:
///
/// - `.denied` → "Open System Settings…" is the one primary action.
/// - `.grantedPendingRestart` → "Restart Stare" is primary; re-authorizing in
///   System Settings is the single secondary action (the copy in
///   `ScreenRecordingAccess.detail` names both remedies, and the hierarchy
///   must keep offering them in the same order of prominence).
/// - `.granted` → "Continue" is primary and System Settings is absent — not
///   disabled, not visible. It must no longer be the window's most prominent
///   button once the permission already works.
public struct OnboardingAction: Equatable, Sendable {
    /// What pressing the button does; the view maps each kind to its one
    /// existing path (System Settings, `onRestart`, `onContinue`).
    public enum Kind: Equatable, Sendable {
        /// Prompts for Screen Recording if needed, then opens the Screen
        /// Recording pane in System Settings.
        case openSystemSettings
        /// Relaunches Stare so the per-process TCC grant takes effect.
        case restartStare
        /// Reports the guide as finished and closes it into the app.
        case continueOnboarding
    }

    /// Which single thing the button does.
    public let kind: Kind
    /// The button's label.
    public let label: String

    public init(kind: Kind, label: String) {
        self.kind = kind
        self.label = label
    }
}

/// One primary action, at most one secondary, for a permission state. See
/// `OnboardingAction` for the rules.
public struct OnboardingActionPlan: Equatable, Sendable {
    /// The action the view renders prominently (`.borderedProminent`), the
    /// one Return triggers.
    public let primary: OnboardingAction
    /// The at-most-one Supporting action the view renders bordered, beside
    /// the primary; `nil` when the state has exactly one way forward.
    public let secondary: OnboardingAction?

    /// Every action in the plan, primary first — the shape tests and the
    /// view's exhaustive checks read.
    public var all: [OnboardingAction] {
        [primary] + (secondary.map { [$0] } ?? [])
    }

    private init(primary: OnboardingAction, secondary: OnboardingAction?) {
        self.primary = primary
        self.secondary = secondary
    }

    /// The hierarchy for `access` (S2–S3).
    public static func plan(for access: ScreenRecordingAccess) -> OnboardingActionPlan {
        switch access {
        case .denied:
            OnboardingActionPlan(
                primary: OnboardingAction(
                    kind: .openSystemSettings,
                    label: "Open System Settings…"
                ),
                secondary: nil
            )
        case .grantedPendingRestart:
            OnboardingActionPlan(
                primary: OnboardingAction(
                    kind: .restartStare,
                    label: "Restart Stare"
                ),
                secondary: OnboardingAction(
                    kind: .openSystemSettings,
                    label: "Open System Settings…"
                )
            )
        case .granted:
            OnboardingActionPlan(
                primary: OnboardingAction(
                    kind: .continueOnboarding,
                    label: "Continue"
                ),
                secondary: nil
            )
        }
    }
}
