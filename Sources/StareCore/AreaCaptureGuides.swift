import CoreGraphics

/// Pure geometry of the area drag's dotted guides (S1): while a selection is
/// being drawn, each of the selection's four edges extends out to THE
/// DISPLAY'S edges as a thin dotted rule, so the eye can follow a line to the
/// edge before committing.
///
/// Everything computes from the selection's own rect alone (S3): the caller
/// passes the same `selectionRect` the overlay holds at mouse-up — exactly
/// what `deliver` crops with — so a rule can never promise an edge the
/// capture does not take. Three decisions the type encodes:
///
/// - Which edges get a rule: the selection's four, each extended both ways.
/// - No rule before a rect exists: a pointer without a selection edge has
///   nothing to extend, and a line not tied to `selectionRect` would claim
///   geometry the crop does not honour.
/// - The clipping: the rect is first intersected with the display's bounds
///   (the same clamp area capture already relies on, and on a multi-display
///   Mac each `OverlayView`'s bounds ARE its display's edges — no
///   cross-canvas geometry exists), and an edge that lands on a display edge,
///   or a ray whose span degenerated to nothing, is dropped rather than
///   painting into the display's own boundary — a rule there could only
///   imply a farther edge that does not exist.
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

    /// The rules for `selectionRect` inside `bounds` (the display, top-left
    /// origin view space), or none when there is nothing to rule: no rect, no
    /// room on an axis, or a selection missing the display entirely.
    public static func guides(for selectionRect: CGRect?, bounds: CGRect) -> [Guide] {
        guard let rect = selectionRect, bounds.width > 0, bounds.height > 0 else { return [] }
        // The clip (see above): a stray drag event can land a hair outside
        // the window, and only what the display contains may be ruled.
        let selected = rect.intersection(bounds)
        guard !selected.isNull, selected.width > 0, selected.height > 0 else { return [] }

        var guides: [Guide] = []
        func rule(vertical: Bool, position: CGFloat, from: CGFloat, to: CGFloat) {
            let start = vertical ? bounds.minX : bounds.minY
            let end = vertical ? bounds.maxX : bounds.maxY
            guard to > from, position > start, position < end else { return }
            let line = vertical
                ? CGRect(x: position, y: from, width: 0, height: to - from)
                : CGRect(x: from, y: position, width: to - from, height: 0)
            guides.append(Guide(line: line))
        }
        // Each of the selection's four edges, extended both ways to the
        // display's edges: two rays per edge, dropped when a ray degenerates
        // (the edge sits on a display edge) or when the edge itself lies on
        // the display's boundary.
        for position in [selected.minX, selected.maxX] {
            rule(vertical: true, position: position, from: bounds.minY, to: selected.minY)
            rule(vertical: true, position: position, from: selected.maxY, to: bounds.maxY)
        }
        for position in [selected.minY, selected.maxY] {
            rule(vertical: false, position: position, from: bounds.minX, to: selected.minX)
            rule(vertical: false, position: position, from: selected.maxX, to: bounds.maxX)
        }
        return guides
    }
}
