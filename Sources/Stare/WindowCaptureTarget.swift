import AppKit
import StareCore

/// The window a `⌥S` capture shoots, resolved to the display it sits on.
///
/// The bounds are the raw window-server rect (top-left origin, global) on
/// purpose: that is the same space as `CGDisplayBounds`, which is what
/// `WindowCaptureGeometry` needs to turn the window into a crop.
struct WindowCaptureTarget: Equatable {
    let windowID: CGWindowID
    let bounds: CGRect
    let displayID: CGDirectDisplayID

    /// Resolves the front-most normal window of another app. Nil when the
    /// window server lists nothing eligible, or when the window's screen has
    /// no display behind it — in both cases there is nothing to shoot.
    static func frontWindow() -> WindowCaptureTarget? {
        guard let candidate = FrontWindowLocator.frontmostNormalWindowCandidate(),
              let screen = FrontWindowLocator.screen(forWindowBounds: candidate.bounds),
              let displayID = displayID(of: screen)
        else { return nil }

        return WindowCaptureTarget(
            windowID: candidate.windowID,
            bounds: candidate.bounds,
            displayID: displayID
        )
    }

    /// The display behind a screen. `NSScreen` carries it as a number and the
    /// capture layer speaks `CGDirectDisplayID`.
    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
