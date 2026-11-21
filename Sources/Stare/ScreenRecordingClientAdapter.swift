import AppKit
import StareCore
import os

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
///   `ScreenContent.prepare` + `SCScreenshotManager.captureImage`, at a
///   reduced pixel size instead of full framebuffer size, falling back to the
///   full size before it answers false). It is a fair probe because it is the
///   production capture path end to end — sharing content, own-windows filter
///   and screenshot included — on the same display the capture key targets, so
///   a pass means a real capture succeeds, which is exactly what drawing over
///   the screen needs, and a per-process grant that has not landed yet fails
///   it. It blocks the calling thread on a semaphore, the same way the
///   synchronous `CaptureService.captureDisplay(_:)` already blocks its caller.
/// - `openPrivacySettings()` opens System Settings exactly on the Screen
///   Recording privacy pane.
final class SystemScreenRecordingClient: ScreenRecordingClient, @unchecked Sendable {
    /// Where the probe reports why a capture failed. The permission pane shows
    /// the same failure as "granted, restart needed", so without this line the
    /// real ScreenCaptureKit error is unrecoverable after the fact.
    private static let log = Logger(subsystem: "dev.alvaldes.stare", category: "screenRecording")

    private let captureService: CaptureService

    /// The size the last successful probe answered with, per display, so a
    /// display that only works at full size stops paying for a reduced attempt
    /// on every refresh. `ProbeCapturePlan` owns the rule and its tests; this
    /// adapter only performs the captures. Touched from the main-thread refresh
    /// only.
    private var plan = ProbeCapturePlan()

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
        // The probe must vouch for the capture the app actually performs, and
        // that capture targets the display holding the front-most window. A
        // probe pointed at a different display — the main one, or a display
        // that cannot be captured at all — fails while capturing works, and
        // the permission UI reads that failure as a missing permission.
        guard let screen = FrontWindowLocator.frontmostNormalWindowScreen()
            ?? NSScreen.screens.first,
            let displayID = Self.displayID(of: screen) else {
            Self.log.error("probe: no display to capture")
            return false
        }

        // The reduced capture is the cheap answer, the full-size one is the
        // capture the capture key takes, so the probe is never stricter than the
        // capture it vouches for. `ProbeCapturePlan` owns which sizes are tried
        // and remembers the one that worked — one capture per refresh once a
        // size is known, instead of two every second.
        return plan.run(displayID: displayID, displayDownscale: Self.probeDownscale(for: screen)) { downscale in
            let failure = Self.capture(
                displayID: displayID,
                downscale: downscale,
                using: captureService
            )
            if let failure {
                let error = failure as NSError
                Self.log.error(
                    "probe capture failed display=\(displayID) downscale=\(downscale, privacy: .public) error=\(error.domain, privacy: .public)/\(error.code) \(error.localizedDescription, privacy: .public)"
                )
            }
            return failure
        }
    }

    /// One capture attempt, blocked on until it finishes or until
    /// `ProbeCaptureSize.timeout` runs out: `captureDisplay` is async and
    /// `ScreenRecordingClient` is not, so a detached task does the work and this
    /// thread waits, exactly like the synchronous capture path. The main thread
    /// has nothing else to do in between — the caller is the permission model's
    /// refresh — but a stalled ScreenCaptureKit call must not hang it, so the
    /// wait is bounded. Worst case for a first probe on an unknown display is
    /// one attempt per size, each bounded by that timeout.
    ///
    /// Returns the failure, or nil when the capture succeeded.
    private static func capture(
        displayID: CGDirectDisplayID,
        downscale: CGFloat,
        using captureService: CaptureService
    ) -> Error? {
        let semaphore = DispatchSemaphore(value: 0)
        var failure: Error?

        Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }
            do {
                _ = try await captureService.captureDisplay(
                    displayID,
                    downscale: downscale
                )
            } catch {
                failure = error
            }
        }

        if semaphore.wait(timeout: .now() + ProbeCaptureSize.timeout) == .timedOut {
            return ProbeTimeout()
        }
        return failure
    }

    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
        Diag.log("opened screen recording privacy pane")
    }

    /// How much the probe divides the primary display's pixels by.
    ///
    /// The factor follows the display instead of being a fixed constant: a
    /// constant tuned for one display collapses a bigger one into a
    /// configuration ScreenCaptureKit rejects, and a rejected probe reads as a
    /// missing permission. `ProbeCaptureSize` owns the floor and its rationale.
    private static func probeDownscale(for screen: NSScreen) -> CGFloat {
        let scale = screen.backingScaleFactor
        return ProbeCaptureSize.downscale(
            pixelWidth: Int((screen.frame.width * scale).rounded()),
            pixelHeight: Int((screen.frame.height * scale).rounded())
        )
    }

    /// The display behind a screen, the one a capture of "the screen" starts
    /// from.
    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}

/// The probe waited as long as it is allowed to and ScreenCaptureKit never
/// answered. Reported as a plain failure: no capture happened, so the probe may
/// not claim the permission works.
struct ProbeTimeout: LocalizedError {
    var errorDescription: String? {
        "The capture probe timed out after \(ProbeCaptureSize.timeout) s"
    }
}
