import CoreGraphics

/// Where the bar's extras panel opens. The rule the owner asked for: the tools
/// the bar hides never open toward the screen edge they are parked on, they open
/// toward the middle of the screen — a bar on the right edge opens its panel to
/// its left, a bar along the bottom opens it above. The panel is then clamped
/// into the visible frame, so no dock choice can push it off-screen.
public enum ToolbarOverflowPlacement {
    /// The air between the bar and the panel, in points.
    public static let gap: CGFloat = 8

    /// The panel's frame in screen coordinates: beside the bar on the side that
    /// faces the middle of the screen, aligned with the bar's leading edge, then
    /// clamped into `visibleFrame`.
    /// `anchor` is the control that opened the panel — the bar's more button —
    /// in screen coordinates. When it is known the panel centres on it along the
    /// bar's own axis, so it reads as "this button opened this"; without one the
    /// panel aligns with the bar's leading edge.
    public static func panelFrame(
        panelSize: CGSize,
        barFrame: CGRect,
        border: ToolbarBorder,
        visibleFrame: CGRect,
        anchor: CGPoint? = nil
    ) -> CGRect {
        var origin: CGPoint
        switch border {
        case .left:
            // Bar along the left edge: the panel goes to its right.
            origin = CGPoint(x: barFrame.maxX + gap, y: barFrame.maxY - panelSize.height)
        case .right:
            origin = CGPoint(x: barFrame.minX - gap - panelSize.width, y: barFrame.maxY - panelSize.height)
        case .top:
            // Horizontal bar along the top: the panel hangs below it.
            origin = CGPoint(x: barFrame.minX, y: barFrame.minY - gap - panelSize.height)
        case .bottom:
            origin = CGPoint(x: barFrame.minX, y: barFrame.maxY + gap)
        }
        if let anchor {
            // Centre on the button along the axis the bar runs in; the
            // across-the-bar offset is the edge rule above.
            switch border {
            case .left, .right: origin.y = anchor.y - panelSize.height / 2
            case .top, .bottom: origin.x = anchor.x - panelSize.width / 2
            }
        }
        // Clamp into the visible area: a panel wider or taller than the room
        // left keeps its leading corner on screen instead of vanishing.
        let maxX = visibleFrame.maxX - panelSize.width
        let maxY = visibleFrame.maxY - panelSize.height
        origin.x = min(max(origin.x, visibleFrame.minX), max(maxX, visibleFrame.minX))
        origin.y = min(max(origin.y, visibleFrame.minY), max(maxY, visibleFrame.minY))
        return CGRect(origin: origin, size: panelSize)
    }
}
