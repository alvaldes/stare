import OSLog
import ServiceManagement

/// Starts Stare when the user logs in, through the system login items
/// (T10/S6). The service is the real `SMAppService.mainApp`; the model only
/// reads its status and surfaces registration errors — a refused registration
/// is reported to the pane, never swallowed.
///
/// Notes for the Settings row: registration is meaningful when the app runs
/// from `/Applications` (that is what the login item points at and what the
/// system honours). It is never blocked elsewhere, but the row detail says
/// when the running app is outside `/Applications`.
@MainActor
final class LaunchAtLogin: ObservableObject {
    private(set) var status = SMAppService.mainApp.status
    /// The last registration or unregistration failure, for the pane to show.
    private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.alvaldes.stare", category: "settings")

    /// The toggle's value: an entry that needs approval still means the user
    /// asked for it, so it reads as on.
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    /// The user must allow Stare in System Settings → General → Login Items.
    var needsApproval: Bool { status == .requiresApproval }

    /// The app is running from /Applications, where the system keeps the
    /// login-item registration across reinstalls.
    var runsFromApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    var statusDescription: String {
        switch status {
        case .enabled: "On"
        case .requiresApproval: "Needs approval"
        case .notRegistered, .notFound: "Off"
        @unknown default: "Off"
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            // Registration failures are user-visible state — a pane row that
            // silently does nothing is worse than one that explains itself.
            lastError = error.localizedDescription
            logger.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
