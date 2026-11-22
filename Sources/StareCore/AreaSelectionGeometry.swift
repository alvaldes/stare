import CoreGraphics

/// Pure geometry of the area drag (`⇧S`): normalizing the drag in any
/// direction, forcing a square with `⇧`, clamping to the display, and deciding
/// whether a finished drag is a capture or a stray click.
public enum AreaSelectionGeometry {
    /// The rectangle a drag from `origin` to `point` selects, constrained to
    /// `bounds` (the display), so the result can never address pixels outside
    /// the display.
    ///
    /// Reuses the primitives the drawing tools already trust instead of
    /// re-deriving them:
    ///
    /// - `PathBuilder.squareConstraint`: the exact `⇧` square rule the
    ///   rectangle and ellipse tools use, which keeps the drag direction so
    ///   the shape grows toward where the pointer went.
    /// - `PathBuilder.normalizedRect`: normalizes any drag direction, so
    ///   dragging up-left is a real rectangle and not an empty one.
    /// - `CoordinateMapping.clamped`: the intersection-with-display-bounds
    ///   clamp area capture already relies on.
    public static func rect(
        from origin: CGPoint,
        to point: CGPoint,
        square: Bool,
        bounds: CGRect
    ) -> CGRect {
        let endpoint = square
            ? PathBuilder.squareConstraint(from: origin, to: point)
            : point
        let drag = PathBuilder.normalizedRect(from: origin, to: endpoint)
        return CoordinateMapping.clamped(drag, to: bounds)
    }

    /// A drag smaller than `minimum` is a stray click, not a capture. The
    /// minimum itself counts (`4×4` is worthy) so exactly the boundary drag
    /// still captures; strictly below it never does.
    public static func isCaptureWorthy(
        _ rect: CGRect,
        minimum: CGSize = CGSize(width: 4, height: 4)
    ) -> Bool {
        rect.width >= minimum.width && rect.height >= minimum.height
    }
}
