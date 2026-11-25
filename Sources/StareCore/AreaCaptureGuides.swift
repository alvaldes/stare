import CoreGraphics

/// Pure geometry of the area drag's dotted guides (S4): while area mode is
/// armed — before and during the drag alike — the POINTER carries the
/// crosshair, one vertical and one horizontal rule through the pointer, out
/// to this display's edges. Exactly one rule per axis, always the pointer's:
/// the selection's edges are never ruled, so the origin's rules the first
/// version drew cannot exist. This chrome is the eye's aid only; what the
/// capture takes is still the selection rectangle alone, which the guides
/// never read.
///
/// Everything computes from the pointer's point and the display's bounds
/// alone (kept pure, like `AreaCaptureLoupe`'s plan). The clipping is the
/// same one the first version lived by, applied per axis: a point outside
/// the display's span on an axis draws no rule on that axis (so a pointer on
/// another display draws nothing here), and no rule is drawn exactly on a
/// display edge — a rule there could only imply a farther edge that does not
/// exist.
///
/// The view paints all of this; nothing here touches AppKit.
public enum AreaCaptureGuides {
    /// The rule's stroke width, in view points (the paint pass uses it).
    public static let lineWidth: CGFloat = 1
    /// The dotted pattern's dot, in points: a short dash with a round cap,
    /// so the rule reads as a line of dots, never a solid stroke.
    public static let dotLength: CGFloat = 1
    /// The dotted pattern's gap, in points.
    public static let gapLength: CGFloat = 3

    /// One dotted rule: a zero-width (vertical) or zero-height (horizontal)
    /// segment — `line` is the span the painter strokes from `min` to `max`.
    public struct Guide: Equatable, Sendable {
        public let line: CGRect

        public init(line: CGRect) { self.line = line }

        public var isVertical: Bool { line.width == 0 }
        public var isHorizontal: Bool { line.height == 0 }
    }

    /// The pointer's crosshair rules inside `bounds` (the display, top-left
    /// origin view space), or none when there is nothing to rule: no pointer,
    /// no room on an axis (outside the display, or a point sitting on the
    /// display's edge — a rule there would sit exactly on the boundary).
    public static func guides(at point: CGPoint?, bounds: CGRect) -> [Guide] {
        guard let point, bounds.width > 0, bounds.height > 0 else { return [] }

        var guides: [Guide] = []
        func rule(vertical: Bool) {
            let position = vertical ? point.x : point.y
            let start = vertical ? bounds.minX : bounds.minY
            let end = vertical ? bounds.maxX : bounds.maxY
            guard position > start, position < end else { return }
            let line = vertical
                ? CGRect(x: position, y: bounds.minY, width: 0, height: bounds.height)
                : CGRect(x: bounds.minX, y: position, width: bounds.width, height: 0)
            guides.append(Guide(line: line))
        }
        rule(vertical: true)
        rule(vertical: false)
        return guides
    }
}
