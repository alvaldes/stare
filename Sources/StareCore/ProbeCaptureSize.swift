import CoreGraphics
import Foundation

/// How small the Screen Recording probe capture is allowed to get.
///
/// The probe is a real capture (`SCScreenshotManager.captureImage`) at a
/// reduced size, because the permission UI runs it on every refresh and a
/// full framebuffer frame is too expensive for that. The reduction has a
/// floor: ScreenCaptureKit rejects a configuration only a couple of pixels
/// wide, and a rejected probe is indistinguishable from a missing permission
/// in the state machine (`ScreenRecordingPermission.refresh()` maps
/// "preflight true but no capture" to "granted, restart needed"). A display
/// whose pixels divided by a fixed factor fall under that floor therefore
/// reports a broken permission while capturing perfectly.
public enum ProbeCaptureSize {
    /// Short side the probe keeps, in pixels. Comfortably above the smallest
    /// configuration ScreenCaptureKit accepts, and still cheap enough to run
    /// on every refresh.
    public static let shortSide = 120

    /// The factor a display's pixel size is divided by to reach
    /// `shortSide` on its short side.
    ///
    /// Returns `1` for a display already at or under the floor (the probe
    /// never upscales) and never returns anything below `1`.
    public static func downscale(pixelWidth: Int, pixelHeight: Int) -> CGFloat {
        let short = min(max(0, pixelWidth), max(0, pixelHeight))
        guard short > shortSide else { return 1 }
        return CGFloat(short) / CGFloat(shortSide)
    }

    /// Ceiling on one probe capture, in seconds.
    ///
    /// The probe blocks the thread that runs the permission refresh — the main
    /// thread — so an unbounded wait hangs the app whenever ScreenCaptureKit
    /// stops answering. A timeout turns that into a plain "cannot capture yet".
    public static let timeout: TimeInterval = 2

    /// The capture sizes to try, in order, for one probe.
    ///
    /// The first probe tries the cheap size and, if that fails, the capture the
    /// capture key takes — the probe may never be stricter than the capture it
    /// vouches for. Once a size has worked it becomes the only attempt: the
    /// refresh runs about once a second, and paying for two captures per tick in
    /// the state that repeats most is the cost this avoids.
    ///
    /// - Parameters:
    ///   - displayDownscale: what `downscale(pixelWidth:pixelHeight:)` returned
    ///     for the display being probed.
    ///   - lastSucceeded: the factor the previous probe answered with, if any.
    public static func attempts(displayDownscale: CGFloat, lastSucceeded: CGFloat?) -> [CGFloat] {
        if let lastSucceeded { return [lastSucceeded] }
        return displayDownscale > 1 ? [displayDownscale, 1] : [1]
    }
}
