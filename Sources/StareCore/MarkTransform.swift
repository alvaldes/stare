import CoreGraphics
import Foundation

/// The edit-cursor transformations of an existing mark, resolved as pure
/// geometry in StareCore. Every function applies to an untouched snapshot of
/// the stroke and returns a new stroke, so a drag stays idempotent from its
/// start: the overlay transforms the drag-start snapshot each frame, never the
/// result of the previous frame.
///
/// The shape is never allowed to change: translation bakes into the points
/// (translation cannot deform), scaling is uniform only, and rotation is
/// metadata on the stroke, never baked into the points.
public enum MarkTransform {
    /// Bakes the drag delta into the points. The text origin is the first
    /// point, so it moves with the mark.
    public static func translated(_ stroke: Stroke, by delta: CGPoint) -> Stroke {
        var result = stroke
        result.points = stroke.points.map {
            CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
        }
        return result
    }

    /// Uniform scale by `factor` about `anchor` — the view-space corner
    /// opposite the dragged handle. The aspect ratio can never change: every
    /// point moves along its ray from the anchor, and a text mark scales
    /// `textSize` with the same factor. `rotation` is metadata and stays.
    public static func scaled(_ stroke: Stroke, from anchor: CGPoint, by factor: CGFloat) -> Stroke {
        // A drag past the anchor must not mirror or collapse the mark.
        let clamped = max(factor, 0.01)
        var result = stroke
        result.points = stroke.points.map {
            CGPoint(x: anchor.x + ($0.x - anchor.x) * clamped,
                    y: anchor.y + ($0.y - anchor.y) * clamped)
        }
        if let size = result.textSize {
            result.textSize = CGSize(width: size.width * clamped, height: size.height * clamped)
        }
        // A numbered badge is drawn at its own stored size, so it scales with
        // the mark instead of sliding (advisory A).
        if let badge = result.badgeSize {
            result.badgeSize = badge * clamped
        }
        return result
    }

    /// The uniform factor of a corner drag: the ratio of the distances from the
    /// anchor to the drag point and to the dragged corner. A free drag on a
    /// single axis still produces this one uniform factor.
    public static func scaleFactor(
        from anchor: CGPoint,
        draggedCorner: CGPoint,
        to point: CGPoint
    ) -> CGFloat {
        let base = distance(draggedCorner, anchor)
        guard base > 0.001 else { return 1 }
        return distance(point, anchor) / base
    }

    /// Resolves a corner-handle drag to a uniform scale. The factor is the
    /// distance ratio from the opposite handle point to the pointer versus to
    /// the dragged handle — a drag twice as far from where the handle was is
    /// exactly 2×. The scale itself is anchored on the opposite corner of the
    /// mark's own geometry (the handle point without the constant bounds
    /// padding, rotated with the mark), which is what keeps the opposite
    /// selection handle exactly where it was through the whole drag. Handles
    /// that are not corners leave the mark untouched.
    public static func scaled(_ stroke: Stroke, dragging handle: MarkHandle, to point: CGPoint) -> Stroke {
        let selection = MarkSelection(stroke: stroke)
        let handles = selection.handlePoints(rotationHandleOffset: MarkSelection.defaultRotationHandleOffset)
        guard let draggedHandle = handles[handle],
              oppositeCorner(of: handle) != handle,
              let anchorHandle = handles[oppositeCorner(of: handle)],
              let anchor = viewGeometryCorner(of: oppositeCorner(of: handle), for: stroke)
        else { return stroke }
        let factor = scaleFactor(from: anchorHandle, draggedCorner: draggedHandle, to: point)
        return scaled(stroke, from: anchor, by: factor)
    }

    /// Adds `angle` radians to the rotation about the anchor. The points are
    /// left untouched, so the mark keeps its shape.
    public static func rotated(_ stroke: Stroke, by angle: CGFloat) -> Stroke {
        var result = stroke
        result.rotation += angle
        return result
    }

    // MARK: - Corner geometry

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func oppositeCorner(of handle: MarkHandle) -> MarkHandle {
        switch handle {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        case .rotation, .body: handle
        }
    }

    /// View-space position of a corner handle on the mark as it now looks.
    private static func viewCorner(of handle: MarkHandle, for stroke: Stroke) -> CGPoint? {
        let bounds = stroke.bounds
        let unrotated: CGPoint
        switch handle {
        case .topLeft: unrotated = CGPoint(x: bounds.minX, y: bounds.minY)
        case .topRight: unrotated = CGPoint(x: bounds.maxX, y: bounds.minY)
        case .bottomLeft: unrotated = CGPoint(x: bounds.minX, y: bounds.maxY)
        case .bottomRight: unrotated = CGPoint(x: bounds.maxX, y: bounds.maxY)
        case .rotation, .body: return nil
        }
        guard stroke.rotation != 0 else { return unrotated }
        return unrotated.applying(
            Stroke.rotationTransform(around: stroke.anchor, by: stroke.rotation)
        )
    }

    /// The mark's own geometry corner for a handle — the bounds corner without
    /// the constant bounds padding, rotated with the mark. Scaling about this
    /// point keeps the opposite selection handle fixed: the geometry corner
    /// never moves, and the padding is added back unchanged.
    private static func viewGeometryCorner(of handle: MarkHandle, for stroke: Stroke) -> CGPoint? {
        let box: CGRect
        if stroke.tool == .text, let origin = stroke.points.first {
            box = CGRect(origin: origin, size: stroke.textSize ?? .zero)
        } else {
            box = PathBuilder.path(for: stroke).boundingBoxOfPath
            guard !box.isNull else { return nil }
        }
        let corner: CGPoint
        switch handle {
        case .topLeft: corner = CGPoint(x: box.minX, y: box.minY)
        case .topRight: corner = CGPoint(x: box.maxX, y: box.minY)
        case .bottomLeft: corner = CGPoint(x: box.minX, y: box.maxY)
        case .bottomRight: corner = CGPoint(x: box.maxX, y: box.maxY)
        case .rotation, .body: return nil
        }
        guard stroke.rotation != 0 else { return corner }
        return corner.applying(
            Stroke.rotationTransform(around: stroke.anchor, by: stroke.rotation)
        )
    }
}
