import CoreGraphics

/// The last confirmed area rectangle, remembered for the overlay session
/// (S11, T2b slice B). Pressing `⇧S` again pre-loads it as the starting
/// marquee: a plain `Return` confirms and captures it with no drag, and
/// starting a drag replaces it. Pure session-scoped state — nothing persists
/// to disk, nothing reaches Settings, and the overlay's deactivation (the
/// canvases' `clear`) empties it.
public struct AreaCaptureMemory: Equatable {
    public private(set) var rectangle: CGRect?

    public init() {}

    /// The rectangle the next `⇧S` arms with: the last confirmed area, nil
    /// until one is confirmed or after a deactivation.
    public var preload: CGRect? { rectangle }

    /// A confirmed area — a capture-worthy drag result or the `Return` on a
    /// pre-loaded marquee — replaces whatever was remembered, so exactly one
    /// rectangle is remembered: the newest. A stray click's rectangle (below
    /// the capture minimum, the rule the drag already trusts) is refused and
    /// can never poison the memory. Returns whether the memory changed.
    @discardableResult
    public mutating func confirm(_ rect: CGRect) -> Bool {
        guard AreaSelectionGeometry.isCaptureWorthy(rect) else { return false }
        let changed = rectangle != rect
        rectangle = rect
        return changed
    }

    /// The overlay deactivated: the memory is session-scoped and dies with
    /// it. Returns whether anything was remembered.
    @discardableResult
    public mutating func clear() -> Bool {
        guard rectangle != nil else { return false }
        rectangle = nil
        return true
    }
}
