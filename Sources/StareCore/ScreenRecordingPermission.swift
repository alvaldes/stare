import Foundation

/// A client the app implements to answer the three Screen Recording questions
/// with real system calls, so the permission model can be tested with a fake
/// (T4/S1–S2). Each method stands for one TCC query on
/// `kTCCServiceScreenCapture`:
///
/// - `preflight()` — `CGPreflightScreenCaptureAccess`: a non-prompting,
///   synchronous "does TCC say this process may capture?" check.
/// - `request()` — `CGRequestScreenCaptureAccess`: shows the TCC consent
///   prompt if the decision is still undecided; its return value only
///   reflects the current process, and a fresh grant usually lands only
///   after the user flips the switch and the app restarts.
/// - `canCapture()` — a real capture probe (whatever the app already tries
///   when it captures a frame): answers whether a capture actually succeeds
///   right now, which can be false even when preflight is true, because TCC
///   applies the grant per process.
/// - `openPrivacySettings()` — opens System Settings on the Screen Recording
///   pane (`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`).
public protocol ScreenRecordingClient: Sendable {
    /// Non-prompting TCC check: may this process capture the screen?
    func preflight() -> Bool
    /// Prompts the TCC consent dialog if undecided and reports whether the
    /// current process can capture afterwards.
    func request() -> Bool
    /// Real probe: does an actual capture succeed right now?
    func canCapture() -> Bool
    /// Opens System Settings on the Screen Recording privacy pane.
    func openPrivacySettings()
}

/// What Screen Recording looks like from inside this process, with English
/// copy for the onboarding and Settings UI.
public enum ScreenRecordingAccess: Equatable, Sendable {
    /// TCC has not granted Screen Recording to this app.
    case denied
    /// TCC granted it and a capture actually succeeds in this process.
    case granted
    /// TCC granted it, but this process still cannot capture: the app has to
    /// be restarted for the per-process grant to take effect.
    case grantedPendingRestart

    public var title: String {
        switch self {
        case .denied: "Screen Recording off"
        case .granted: "Screen Recording on"
        case .grantedPendingRestart: "Screen Recording on"
        }
    }

    public var detail: String {
        switch self {
        case .denied:
            "Stare needs Screen Recording to draw over the screen."
        case .granted:
            "Stare can draw over the screen."
        case .grantedPendingRestart:
            "The permission is granted, but Stare has to be restarted before it can capture."
        }
    }

    /// Invariant: true only for `.granted`. A pending-restart state must
    /// never be mistaken for a working permission.
    public var isGranted: Bool {
        if case .granted = self { return true }
        return false
    }
}

/// Observable state machine over the injected `ScreenRecordingClient`
/// (T4/S1–S2). This class is **`@MainActor`-confined**: the app reads and
/// drives it from AppKit callbacks on the main thread, so `onChange` always
/// fires there too.
///
/// It owns no timers and no AppKit: nothing refreshes itself. The app (T5)
/// calls `refresh()` when the onboarding window is open — on a short interval
/// and on `NSApplication.didBecomeActiveNotification`, so returning from
/// System Settings re-reads the state — calls `requestAccess()` from the
/// guide's primary button, and calls `openSettings()` to send the user to the
/// Screen Recording pane.
@MainActor
public final class ScreenRecordingPermission {
    private let client: any ScreenRecordingClient
    public private(set) var access: ScreenRecordingAccess = .denied

    /// Called on the main thread whenever `access` actually changes; a
    /// repeated `refresh()` with the same answers fires nothing.
    public var onChange: ((ScreenRecordingAccess) -> Void)?

    /// - Parameter client: the system-backed answers (`ScreenRecordingClient`
    ///   documents which TCC query each method stands for).
    public init(client: any ScreenRecordingClient) {
        self.client = client
    }

    /// Re-reads the permission and returns the new state.
    ///
    /// Rules:
    /// - `preflight()` false → `.denied`; the probe and nothing else are
    ///   consulted.
    /// - `preflight()` true and `canCapture()` true → `.granted`.
    /// - `preflight()` true and `canCapture()` false → `.grantedPendingRestart`.
    ///   Documented rule, applied regardless of the grant's age: preflight
    ///   true means TCC already granted the permission, so `.denied` would
    ///   contradict the system, and the only other truthful state is "granted
    ///   but this process cannot capture yet". Whether the grant appeared
    ///   mid-session or predates this launch (e.g. after an app update that
    ///   re-registered TCC), the UI copy — "restart Stare" — is accurate, so
    ///   the state does not depend on the grant's age; the fresh-instance
    ///   test pins this.
    ///
    /// `onChange` fires only when the value actually changes.
    @discardableResult
    public func refresh() -> ScreenRecordingAccess {
        let granted = client.preflight()
        let newState: ScreenRecordingAccess
        if granted {
            newState = client.canCapture() ? .granted : .grantedPendingRestart
        } else {
            newState = .denied
        }
        if newState != access {
            access = newState
            onChange?(newState)
        }
        return access
    }

    /// Asks the system for the permission (`request()`, exactly once per
    /// call) and then refreshes, so the caller observes the post-request
    /// state — which is `.grantedPendingRestart` or `.denied` in practice,
    /// because a fresh TCC grant only becomes usable after a restart.
    @discardableResult
    public func requestAccess() -> ScreenRecordingAccess {
        _ = client.request()
        return refresh()
    }

    /// Forwards to the client exactly once per call: opens System Settings on
    /// the Screen Recording privacy pane.
    public func openSettings() {
        client.openPrivacySettings()
    }
}
