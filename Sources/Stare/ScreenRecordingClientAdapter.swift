import AppKit
import StareCore

/// The real `ScreenRecordingClient` Stare ships: every method answers the same
/// TCC question with the same call the capture path makes, so the onboarding
/// model observes exactly what a real capture would run into.
///
/// - `preflight()` is `CGPreflightScreenCaptureAccess()`, the non-prompting
///   check `CaptureService.hasPermission` uses.
/// - `request()` is `CGRequestScreenCaptureAccess()`, what
///   `CaptureService.requestPermission()` does at launch.
/// - `canCapture()` runs the smallest real capture the app knows how to do:
///   the live-blur frame path (`CaptureService.captureDisplay(_:downscale:)`,
///   which is `SCShareableContent.excludingDesktopWindows` +
///   `ScreenContent.prepare` + `SCScreenshotManager.captureImage`, only at a
///   handful of pixels instead of full framebuffer size). It is a fair probe
///   because it is the production capture path end to end — sharing content,
///   own-windows filter and screenshot included — so a pass means a real
///   capture succeeds, which is exactly what drawing over the screen needs,
///   and a per-process grant that has not landed yet fails it. It blocks the
///   calling thread on a semaphore, the same way the synchronous
///   `CaptureService.captureDisplay(_:)` already blocks its caller.
/// - `openPrivacySettings()` opens System Settings exactly on the Screen
///   Recording privacy pane.
final class SystemScreenRecordingClient: ScreenRecordingClient, @unchecked Sendable {
    /// The probe capture is downscaled until it is a few pixels wide; any
    /// current display divided by this still yields a valid 1×1 configuration.
    private static let probeDownscale: CGFloat = 1000

    private let captureService: CaptureService

    /// Reuses the app's own capture service, so the probe cannot drift from
    /// what capturing actually does.
    init(captureService: CaptureService) {
        self.captureService = captureService
    }

    func preflight() -> Bool {
        captureService.hasPermission
    }

    func request() -> Bool {
        captureService.requestPermission()
        return captureService.hasPermission
    }

    func canCapture() -> Bool {
        guard let displayID = Self.primaryDisplayID() else { return false }

        // `captureDisplay(_:downscale:)` is async and this protocol is not, so
        // a detached task does the work and the caller waits, mirroring the
        // synchronous capture path. The main thread is not doing anything else
        // in between: the probe runs from the permission model's refresh.
        let semaphore = DispatchSemaphore(value: 0)
        var captured = false

        Task.detached(priority: .userInitiated) { [captureService] in
            defer { semaphore.signal() }
            do {
                _ = try await captureService.captureDisplay(
                    displayID,
                    downscale: Self.probeDownscale
                )
                captured = true
            } catch {
                captured = false
            }
        }

        semaphore.wait()
        return captured
    }

    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
        Diag.log("opened screen recording privacy pane")
    }

    /// The primary display, the one a capture of "the screen" starts from.
    private static func primaryDisplayID() -> CGDirectDisplayID? {
        guard let screen = NSScreen.screens.first else { return nil }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
