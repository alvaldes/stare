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

    public init(
        id: UUID = UUID(),
        tool: Tool,
        ink: Ink,
        points: [CGPoint],
        stepNumber: Int? = nil
    ) {
        self.id = id
        self.tool = tool
        self.ink = ink
        self.points = points
        self.stepNumber = stepNumber
    }

    /// Stroke width in points, excluding badges.
    public var lineWidth: CGFloat {
        switch tool {
        case .highlighter: 18
        case .number: 2
        case .pen, .arrow, .line, .rectangle, .ellipse: 3
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
}
