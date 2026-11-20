import CoreGraphics
import Foundation

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

    public init(
        id: UUID = UUID(),
        tool: Tool,
        ink: Ink,
        points: [CGPoint],
        stepNumber: Int? = nil,
        text: String? = nil,
        textSize: CGSize? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.tool = tool
        self.ink = ink
        self.points = points
        self.stepNumber = stepNumber
        self.text = text
        self.textSize = textSize
        self.createdAt = createdAt
    }

    /// Stroke width in points, excluding badges.
    public var lineWidth: CGFloat {
        switch tool {
        case .highlighter: 18
        case .number: 2
        case .text, .eraser: 0
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
    public func hitTest(_ point: CGPoint, radius: CGFloat) -> Bool {
        switch tool {
        case .number:
            guard let center = points.first else { return false }
            let dx = point.x - center.x
            let dy = point.y - center.y
            let reach = PathBuilder.badgeDiameter / 2 + radius
            return (dx * dx + dy * dy) <= reach * reach
        case .text:
            return bounds.insetBy(dx: -radius, dy: -radius).contains(point)
        case .eraser:
            return false
        case .pen, .highlighter, .arrow, .line, .rectangle, .ellipse, .laser:
            let outline = PathBuilder.path(for: self).copy(
                strokingWithWidth: max(lineWidth, 2) + radius * 2,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
            return outline.contains(point, using: .winding)
        }
    }
}
