import AppKit
import StareCore

/// The front window's display, read from the actual window server list.
/// `CGWindowListCopyWindowInfo` returns windows front-to-back and needs no
/// Accessibility or Input Monitoring permission and activates nothing, which
/// keeps this answer permission-free like the rest of the app. The pure
/// mapping from window bounds to display lives in `FrontWindowDisplay`
/// (StareCore), so only the lookup lives here.
enum FrontWindowLocator {
    /// CG window-list bounds (top-left origin, global coordinates) of the
    /// front-most normal window: layer 0, on screen, visible, not Stare's
    /// own. Nil when the list has no such window.
    static func frontmostNormalWindowBounds() -> CGRect? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return frontmostWindowBounds { $0 != ownPID }
    }

    /// The screen whose frame holds the frontmost normal window, mapped by
    /// the pure `FrontWindowDisplay` mapping.
    static func frontmostNormalWindowScreen() -> NSScreen? {
        screen(forBounds: frontmostNormalWindowBounds())
    }

    /// CG window bounds of the front-most on-screen layer-0 window owned by
    /// `pid`: the previous frontmost-application heuristic, kept as the
    /// fallback when the list has no other normal window.
    static func frontmostWindowBounds(ownerPID: Int32) -> CGRect? {
        frontmostWindowBounds { $0 == ownerPID }
    }

    /// The screen of an application's front-most window.
    static func frontmostWindowScreen(ownerPID: Int32) -> NSScreen? {
        screen(forBounds: frontmostWindowBounds(ownerPID: ownerPID))
    }

    /// Every window the server lists, front to back, reduced to the facts
    /// choosing a capture target needs. Deliberately unfiltered: the rules live
    /// in the pure `FrontWindowSelection`, where they can be tested.
    static func windowCandidates() -> [WindowCandidate] {
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        return list.compactMap { window in
            guard let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let raw = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary)
            else { return nil }
            return WindowCandidate(
                windowID: id,
                ownerPID: pid,
                layer: layer,
                alpha: window[kCGWindowAlpha as String] as? Double ?? 1,
                bounds: bounds,
                isOnScreen: window[kCGWindowIsOnscreen as String] as? Bool ?? true
            )
        }
    }

    /// The window a window capture shoots: the front-most normal window of
    /// another app, never one of Stare's own panels.
    static func frontmostNormalWindowCandidate() -> WindowCandidate? {
        FrontWindowSelection.frontmost(
            in: windowCandidates(),
            excluding: ProcessInfo.processInfo.processIdentifier
        )
    }

    /// The screen a window sits on, from its raw CG window-list bounds.
    static func screen(forWindowBounds bounds: CGRect) -> NSScreen? {
        screen(forBounds: bounds)
    }

    /// Bounds of the first on-screen layer-0 window whose owner matches
    /// `want`. Fully transparent helper windows and windows smaller than
    /// 50x50 are skipped: invisible layer-0 utilities must not decide where
    /// the front window is.
    private static func frontmostWindowBounds(where want: (Int32) -> Bool) -> CGRect? {
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        for window in list {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  want(pid) else { continue }
            if let alpha = window[kCGWindowAlpha as String] as? CGFloat, alpha == 0 { continue }
            guard let raw = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  bounds.width >= 50, bounds.height >= 50 else { continue }
            return bounds
        }
        return nil
    }

    /// Maps window bounds onto one of the current screens through the shared
    /// pure mapping; nil when the bounds are nil or land on no display.
    private static func screen(forBounds bounds: CGRect?) -> NSScreen? {
        guard let bounds else { return nil }
        let displayFrames = NSScreen.screens.map(\.frame)
        // CG window coordinates are measured from the top edge of the main
        // display, which in AppKit coordinates is the primary screen's top.
        let primaryScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        let appKitFrame = FrontWindowDisplay.appKitFrame(
            cgWindowBounds: bounds,
            primaryScreenTop: primaryScreenTop
        )
        guard let index = FrontWindowDisplay.displayIndex(
            windowFrame: appKitFrame,
            displayFrames: displayFrames
        ) else { return nil }
        return NSScreen.screens[index]
    }
}
