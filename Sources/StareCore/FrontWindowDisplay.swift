import CoreGraphics

/// Mapping from a frontmost window's on-screen bounds to the display that
/// holds it. Kept pure — plain geometry, no AppKit and no window list — so
/// the "which display is the front window on" answer is testable headless,
/// while the window list itself is read by the app side.
public enum FrontWindowDisplay {
    /// Converts CG window-list bounds — top-left origin in global
    /// coordinates — into AppKit screen coordinates with a bottom-left
    /// origin. The two coordinate systems share one horizontal row: the top
    /// edge of the main display, whose AppKit y is `primaryScreenTop`, so a
    /// point at AppKit y reads `primaryScreenTop - cgY` in CG coordinates.
    /// Production feeds `NSScreen.screens.first?.frame.maxY`.
    public static func appKitFrame(cgWindowBounds: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(
            x: cgWindowBounds.minX,
            y: primaryScreenTop - cgWindowBounds.maxY,
            width: cgWindowBounds.width,
            height: cgWindowBounds.height
        )
    }

    /// Index into `displayFrames` of the display that holds the window's
    /// centre. When no frame contains the centre — a window parked between
    /// two displays, for instance — the display with the largest overlap with
    /// the window wins; nil when the window touches no display or the list is
    /// empty.
    public static func displayIndex(windowFrame: CGRect, displayFrames: [CGRect]) -> Int? {
        guard !displayFrames.isEmpty else { return nil }
        let centre = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        if let index = displayFrames.firstIndex(where: { $0.contains(centre) }) {
            return index
        }
        var best: (index: Int, area: CGFloat)?
        for (index, frame) in displayFrames.enumerated() {
            let intersection = frame.intersection(windowFrame)
            let area = intersection.width * intersection.height
            if area > 0, area > best?.area ?? 0 {
                best = (index, area)
            }
        }
        return best?.index
    }
}
