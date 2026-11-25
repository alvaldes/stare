import CoreGraphics

/// Where the bar's extras panel opens. The rule the owner asked for: the tools
/// the bar hides never open toward the screen edge they are parked on, they open
/// toward the middle of the screen — a bar on the right edge opens its panel to
/// its left, a bar along the bottom opens it above. The side is read from where
/// the bar actually IS and not from the edge it is docked to, because the gripper
/// moves the window without moving its border; when the middle-facing side has no
/// room for the panel, the other side is used. The panel is then clamped into the
/// visible frame, so no position can push it off-screen.
public enum ToolbarOverflowPlacement {
    /// The air between the bar and the panel, in points.
    public static let gap: CGFloat = 8

    /// The panel's frame in screen coordinates: beside the bar on the side that
    /// faces the middle of the screen, aligned with the bar's leading edge, then
    /// clamped into `visibleFrame`.
    /// `border` says which way the bar runs (a vertical bar takes a column, a
    /// horizontal one a row); it does NOT pick the side, see
    /// `opensOnIncreasingSide`.
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
        case .left, .right:
            // A vertical bar takes a column beside it.
            let after = opensOnIncreasingSide(
                barMin: barFrame.minX,
                barMax: barFrame.maxX,
                panelExtent: panelSize.width,
                visibleMin: visibleFrame.minX,
                visibleMax: visibleFrame.maxX,
                settingSideIsIncreasing: border == .left
            )
            origin = CGPoint(
                x: after ? barFrame.maxX + gap : barFrame.minX - gap - panelSize.width,
                y: barFrame.maxY - panelSize.height
            )
        case .top, .bottom:
            // A horizontal bar takes a row beside it; screen y grows upward, so
            // "after" is above the bar.
            let after = opensOnIncreasingSide(
                barMin: barFrame.minY,
                barMax: barFrame.maxY,
                panelExtent: panelSize.height,
                visibleMin: visibleFrame.minY,
                visibleMax: visibleFrame.maxY,
                settingSideIsIncreasing: border == .bottom
            )
            origin = CGPoint(
                x: barFrame.minX,
                y: after ? barFrame.maxY + gap : barFrame.minY - gap - panelSize.height
            )
        }
        if let anchor {
            // Centre on the button along the axis the bar runs in; the
            // across-the-bar offset is the side rule above.
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

    /// Whether the panel opens on the side of the bar where the coordinate grows:
    /// right of a vertical bar, above a horizontal one.
    ///
    /// The side comes from the geometry, never from the dock alone. When only one
    /// side has room for the panel, that side wins — a bar docked left but dragged
    /// against the right edge opens to its left. When both sides have room the
    /// panel faces the middle of the screen, and the dock setting decides only when
    /// the bar sits exactly on the screen's centre line. When neither side has
    /// room, the panel still faces the middle and the clamp in `panelFrame` keeps
    /// its leading corner reachable.
    private static func opensOnIncreasingSide(
        barMin: CGFloat,
        barMax: CGFloat,
        panelExtent: CGFloat,
        visibleMin: CGFloat,
        visibleMax: CGFloat,
        settingSideIsIncreasing: Bool
    ) -> Bool {
        let roomAfter = visibleMax - barMax - gap
        let roomBefore = barMin - visibleMin - gap
        let fitsAfter = roomAfter >= panelExtent
        let fitsBefore = roomBefore >= panelExtent
        if fitsAfter, !fitsBefore { return true }
        if fitsBefore, !fitsAfter { return false }
        let barCentre = barMin + (barMax - barMin) / 2
        let visibleCentre = visibleMin + (visibleMax - visibleMin) / 2
        if barCentre == visibleCentre { return settingSideIsIncreasing }
        return barCentre < visibleCentre
    }
}
