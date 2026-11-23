import CoreGraphics
import Foundation

/// The head an arrow mark carries. Pure model: the open head is the shipped
/// barb pair, the filled head inks the triangle the barbs span. The style is
/// a property of the mark (S15), so an arrow keeps the head it was drawn
/// with through undo, redo and the editor.
public enum ArrowHeadStyle: String, CaseIterable, Sendable {
    /// The shipped arrow head: two straight barbs from the tip.
    case open
    /// A solid triangle spanning the two barbs.
    case filled

    /// The next style when the key cycles the choice.
    public var next: ArrowHeadStyle {
        switch self {
        case .open: .filled
        case .filled: .open
        }
    }
}

/// One mark on the screen. Points live in a top-left-origin, display-local space
/// measured in points, which is what the overlay view and the capture both use.
public struct Stroke: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let tool: Tool
    public let ink: Ink
    public var points: [CGPoint]
    /// 1-based counter for `.number` marks, `nil` for every other tool.
    public var stepNumber: Int?
    /// Typed content of a `.text` mark.
    public var text: String?
    /// Size the text was measured at, so bounds and hit testing agree with what
    /// is on screen without re-measuring on every frame.
    public var textSize: CGSize?
    /// When a transient mark was made, used to fade and prune it.
    public var createdAt: Date?
    /// Diameter a numbered badge is drawn at, in points. Nil means the default
    /// `PathBuilder.badgeDiameter`: the mark stores the size it was created at,
    /// so scaling the mark scales the badge and its digit with it.
    public var badgeSize: CGFloat?
    /// Rotation in radians about the anchor (the centre of the unrotated
    /// bounds). Positive turns clockwise on screen. It is metadata, never baked
    /// into `points`: a rotated rectangle must stay a rectangle.
    public var rotation: CGFloat
    /// S15: whether this mark draws filled instead of outline only. A property
    /// of the mark: a shape keeps whatever it was drawn with through undo,
    /// redo and the editor. Only ever true on `.rectangle` and `.ellipse`.
    public var isFilled: Bool = false
    /// S15: the head this arrow mark draws. A property of the mark like the
    /// fill; only ever set on `.arrow`.
    public var arrowHead: ArrowHeadStyle = .open

    public init(
        id: UUID = UUID(),
        tool: Tool,
        ink: Ink,
        points: [CGPoint],
        stepNumber: Int? = nil,
        text: String? = nil,
        textSize: CGSize? = nil,
        createdAt: Date? = nil,
        badgeSize: CGFloat? = nil,
        rotation: CGFloat = 0,
        fill: Bool = false,
        arrowHead: ArrowHeadStyle = .open
    ) {
        self.id = id
        self.tool = tool
        self.ink = ink
        self.points = points
        self.stepNumber = stepNumber
        self.text = text
        self.textSize = textSize
        self.createdAt = createdAt
        self.badgeSize = badgeSize
        self.rotation = rotation
        self.isFilled = fill
        self.arrowHead = arrowHead
    }

    /// The mark's own badge diameter, falling back to the default.
    public var badgeDiameter: CGFloat {
        badgeSize ?? PathBuilder.badgeDiameter
    }

    /// Ratio of the mark's own badge diameter to the default one, so a resized
    /// badge draws its digit at the matching size.
    public var badgeScale: CGFloat {
        badgeDiameter / PathBuilder.badgeDiameter
    }

    /// Stroke width in points, excluding badges.
    public var lineWidth: CGFloat {
        switch tool {
        case .highlighter: 18
        case .number: 2
        case .text, .select, .eraser, .blur: 0
        case .pen, .arrow, .line, .rectangle, .ellipse, .laser: 3
        }
    }

    /// Highlighter is translucent so text underneath stays readable.
    public var opacity: CGFloat {
        tool == .highlighter ? 0.35 : 1
    }

    public var bounds: CGRect {
        PathBuilder.bounds(for: self)
    }

    /// The pivot for rotation: the centre of the unrotated geometry.
    public var anchor: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// Map that rotates a point about `anchor` by `angle` radians. Shared by
    /// rendering, hit testing and the selection handles so all three agree.
    public static func rotationTransform(around anchor: CGPoint, by angle: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
    }

    /// Axis-aligned bounds of the mark once rotated about its anchor. Larger
    /// than `bounds` whenever the rotation spills over the box, which is what
    /// culling needs.
    public var displayBounds: CGRect {
        guard rotation != 0 else { return bounds }
        let transform = Stroke.rotationTransform(around: anchor, by: rotation)
        let corners = [
            bounds.origin,
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
        ]
        var result = CGRect.null
        for corner in corners {
            result = result.union(CGRect(origin: corner.applying(transform), size: .zero))
        }
        return result
    }

    public var startPoint: CGPoint? { points.first }
    public var endPoint: CGPoint? { points.last }

    /// Opacity at a given moment: laser marks fade out over their lifetime.
    public func opacity(at now: Date, laserLifetime: TimeInterval) -> CGFloat {
        guard tool.isTransient, let createdAt else { return opacity }
        let age = now.timeIntervalSince(createdAt)
        guard age < laserLifetime else { return 0 }
        return max(0, 1 - age / laserLifetime)
    }

    /// Whether a pointer at `point` touches this mark, used by the eraser.
    /// A rotated mark answers in its own space: the query point is rotated back
    /// about the anchor first, so the mark is hit where it looks.
    public func hitTest(_ point: CGPoint, radius: CGFloat) -> Bool {
        let local: CGPoint
        if rotation == 0 {
            local = point
        } else {
            local = point.applying(Stroke.rotationTransform(around: anchor, by: -rotation))
        }
        switch tool {
        case .select:
            return false
        case .number:
            guard let center = points.first else { return false }
            let dx = local.x - center.x
            let dy = local.y - center.y
            // The badge is drawn at the mark's own stored size, so a scaled
            // badge answers at its scaled radius.
            let reach = badgeDiameter / 2 + radius
            return (dx * dx + dy * dy) <= reach * reach
        case .text:
            return bounds.insetBy(dx: -radius, dy: -radius).contains(local)
        case .eraser:
            return false
        case .blur:
            // The blur mark is an area, not an outline: a point inside the
            // rectangle spanned by its endpoints touches the mark.
            guard let first = points.first, let last = points.last else { return false }
            return PathBuilder.normalizedRect(from: first, to: last).contains(local)
        case .pen, .highlighter, .arrow, .line, .rectangle, .ellipse, .laser:
            let outline = PathBuilder.path(for: self).copy(
                strokingWithWidth: max(lineWidth, 2) + radius * 2,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
            return outline.contains(local, using: .winding)
        }
    }

    /// Whether the edit cursor at `point` grabs this mark. Closed shapes and
    /// area marks answer by their rotated box — the interior of a rectangle is
    /// editable, not only its outline — while freehand ink stays outline-only,
    /// so the empty middle of its bounding box does not grab it.
    public func isSelectedByCursor(at point: CGPoint, radius: CGFloat) -> Bool {
        if hitTest(point, radius: radius) { return true }
        switch tool {
        case .rectangle, .ellipse, .blur, .text, .number:
            return displayBounds.insetBy(dx: -radius, dy: -radius).contains(point)
        case .select, .eraser, .pen, .highlighter, .arrow, .line, .laser:
            return false
        }
    }
}
