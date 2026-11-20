import CoreGraphics
import Foundation

/// The marks of one drawing layer plus its undo history. A session is a value
/// type: the overlay owns one per display, and tests drive it directly.
public struct DrawingSession: Equatable, Sendable {
    /// Committed marks, in draw order.
    public private(set) var strokes: [Stroke] = []
    /// The mark currently being dragged, not yet committed.
    public private(set) var active: Stroke?
    public private(set) var nextStepNumber: Int = 1

    public init() {}

    /// Every mark that must be visible right now, including the one in progress.
    public var visibleStrokes: [Stroke] {
        guard let active else { return strokes }
        return strokes + [active]
    }

    public var isEmpty: Bool { strokes.isEmpty && active == nil }

    public var stepCount: Int { nextStepNumber - 1 }

    /// Starts a mark. Click tools (`number`) complete immediately.
    @discardableResult
    public mutating func begin(at point: CGPoint, tool: Tool, ink: Ink) -> Stroke {
        var stroke = Stroke(tool: tool, ink: ink, points: [point])

        if tool.isClickTool {
            stroke.stepNumber = nextStepNumber
            nextStepNumber += 1
        }

        active = stroke
        if tool.isClickTool { commit() }
        return stroke
    }

    /// Extends the mark in progress. Ignored for click tools and when idle.
    public mutating func extend(to point: CGPoint) {
        guard var current = active, !current.tool.isClickTool else { return }
        current.points.append(point)
        active = current
    }

    /// Finishes the mark in progress and appends it to the session.
    public mutating func commit() {
        guard var current = active else { return }

        if current.tool.usesEndpointsOnly,
           let first = current.points.first,
           let last = current.points.last {
            current.points = [first, last]
        }

        let isRenderable = current.points.count >= 2 || current.tool.isClickTool
        if isRenderable { strokes.append(current) }
        active = nil
    }

    /// Discards the mark in progress, otherwise removes the last committed mark.
    /// Numbered marks give their number back so the sequence stays gapless.
    @discardableResult
    public mutating func undo() -> Bool {
        if active != nil {
            active = nil
            return true
        }
        guard let removed = strokes.popLast() else { return false }
        if let number = removed.stepNumber {
            nextStepNumber = number
        }
        return true
    }

    /// Removes every mark and restarts the numbered sequence.
    public mutating func clear() {
        strokes.removeAll()
        active = nil
        nextStepNumber = 1
    }

    /// Drops a specific mark, used later by the capture editor.
    @discardableResult
    public mutating func remove(id: UUID) -> Bool {
        guard let index = strokes.firstIndex(where: { $0.id == id }) else { return false }
        let removed = strokes.remove(at: index)
        if let number = removed.stepNumber, number < nextStepNumber {
            nextStepNumber = number
        }
        return true
    }
}
