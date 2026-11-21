import CoreGraphics

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
}
