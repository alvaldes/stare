import CoreGraphics

/// One entry of a window list, reduced to the facts that choosing a capture
/// target needs. `CGWindowListCopyWindowInfo` returns entries front to back, so
/// the array order is the stacking order.
public struct WindowCandidate: Equatable, Sendable {
    /// `kCGWindowNumber` — the identifier ScreenCaptureKit also knows as
    /// `SCWindow.windowID`.
    public let windowID: CGWindowID
    /// `kCGWindowOwnerPID`.
    public let ownerPID: Int32
    /// `kCGWindowLayer`. Normal app windows are layer 0; the menu bar, panels
    /// and floating helpers are not.
    public let layer: Int
    /// `kCGWindowAlpha`.
    public let alpha: Double
    /// `kCGWindowBounds` in the global, top-left-origin space window lists use.
    public let bounds: CGRect
    /// `kCGWindowIsOnscreen`. A window that is not on screen has no pixels to
    /// capture even when its bounds look valid.
    public let isOnScreen: Bool

    public init(
        windowID: CGWindowID,
        ownerPID: Int32,
        layer: Int,
        alpha: Double,
        bounds: CGRect,
        isOnScreen: Bool
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
        self.isOnScreen = isOnScreen
    }
}

/// Picks the window a capture should target, using the same rules the display
/// naming path already applies: another process's window, normal layer,
/// visible, big enough to be a real window, and on screen.
public enum FrontWindowSelection {
    /// Anything smaller is a helper, not something a person meant to capture.
    public static let minimumSize = CGSize(width: 50, height: 50)

    /// The frontmost candidate that qualifies, or nil when none does.
    /// `candidates` must be in front-to-back order.
    public static func frontmost(
        in candidates: [WindowCandidate],
        excluding ownPID: Int32
    ) -> WindowCandidate? {
        for candidate in candidates {
            // Our own panels sit over everything and would always win, which
            // would make window capture shoot Stare itself.
            guard candidate.ownerPID != ownPID else { continue }
            // Normal app windows are layer 0. Anything else is the menu bar,
            // a system panel or a floating helper.
            guard candidate.layer == 0 else { continue }
            // Alpha is the window's own opacity: zero is invisible, which
            // means there is nothing on screen to capture.
            guard candidate.alpha > 0 else { continue }
            // Bounds can look perfectly valid for a window that is minimised
            // or parked on another Space.
            guard candidate.isOnScreen else { continue }
            guard candidate.bounds.width >= minimumSize.width,
                candidate.bounds.height >= minimumSize.height
            else { continue }
            return candidate
        }
        return nil
    }
}
