import AppKit
import ScreenCaptureKit

/// Reads screen pixels. Everything here needs the Screen Recording permission,
/// which is why drawing never touches this type.
protocol ScreenCapturing {
    var hasPermission: Bool { get }
    /// Asks macOS once; the user answers in System Settings.
    func requestPermission()
    /// One display at its native pixel size, with Stare's own windows excluded.
    func captureDisplay(_ displayID: CGDirectDisplayID) throws -> CGImage
}

enum CaptureError: Error, Equatable {
    case permissionDenied
    case displayUnavailable
    case noImage
}

final class CaptureService: ScreenCapturing {
    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func requestPermission() {
        guard !hasPermission else { return }
        CGRequestScreenCaptureAccess()
        Diag.log("capture permission requested")
    }

    func captureDisplay(_ displayID: CGDirectDisplayID) throws -> CGImage {
        guard hasPermission else { throw CaptureError.permissionDenied }

        // ScreenCaptureKit is async and this protocol is not, so a detached task
        // does the work and the caller waits. Nothing else runs on the main
        // thread in between: the caller is a key press handler that is about to
        // hand the image to the pasteboard.
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<CGImage, Error> = .failure(CaptureError.noImage)

        Task.detached(priority: .userInitiated) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw CaptureError.displayUnavailable
                }

                // Excluding our own windows is what keeps the palette, the
                // drawing frame and the pointer highlight out of the shot, with
                // no flicker and no timing race.
                let ownWindows = content.windows.filter {
                    $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                }

                let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
                let configuration = SCStreamConfiguration()
                configuration.width = Int(CGDisplayPixelsWide(displayID))
                configuration.height = Int(CGDisplayPixelsHigh(displayID))
                configuration.showsCursor = false
                configuration.capturesAudio = false

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                outcome = .success(image)
            } catch {
                outcome = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        let image = try outcome.get()
        Diag.log("capture display=\(displayID) pixels=\(image.width)x\(image.height)")
        return image
    }
}
