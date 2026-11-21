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

/// The lookup both capture paths share: fresh shareable content, the requested
/// display inside it, and a filter that leaves Stare's own windows out of the
/// pixels, plus the display's real framebuffer size.
enum ScreenContent {
    struct Prepared {
        let filter: SCContentFilter
        let pixelWidth: Int
        let pixelHeight: Int
    }

    static func prepare(
        for displayID: CGDirectDisplayID,
        in content: SCShareableContent
    ) throws -> Prepared {
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

        // The display mode carries the real framebuffer size. CGDisplayPixelsWide
        // reports points here (1920 for a 3840-wide Retina screen), so
        // trusting CGDisplayPixelsWide would quietly halve the capture
        // resolution.
        let mode = CGDisplayCopyDisplayMode(displayID)
        return Prepared(
            filter: filter,
            pixelWidth: mode?.pixelWidth ?? Int(CGDisplayPixelsWide(displayID)),
            pixelHeight: mode?.pixelHeight ?? Int(CGDisplayPixelsHigh(displayID))
        )
    }
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
                let prepared = try ScreenContent.prepare(for: displayID, in: content)
                let configuration = Self.makeConfiguration(
                    pixelWidth: prepared.pixelWidth,
                    pixelHeight: prepared.pixelHeight
                )

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: prepared.filter,
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

    /// A frame at a reduced pixel size, for the live blur refresh (T5/S3). Same
    /// permission rule and same own-windows-excluded filter as the one-shot
    /// capture; only the pixel size differs, and it never blocks the caller:
    /// the live frame source awaits it.
    func captureDisplay(_ displayID: CGDirectDisplayID, downscale: CGFloat) async throws -> CGImage {
        guard hasPermission else { throw CaptureError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let prepared = try ScreenContent.prepare(for: displayID, in: content)
        let configuration = Self.makeConfiguration(
            pixelWidth: max(1, Int((CGFloat(prepared.pixelWidth) * downscale).rounded())),
            pixelHeight: max(1, Int((CGFloat(prepared.pixelHeight) * downscale).rounded()))
        )
        return try await SCScreenshotManager.captureImage(
            contentFilter: prepared.filter,
            configuration: configuration
        )
    }

    private static func makeConfiguration(pixelWidth: Int, pixelHeight: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return configuration
    }
}
