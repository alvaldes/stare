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
    /// How long laser marks live before they are pruned.
    public var laserLifetime: TimeInterval = 1.2

    public init() {}

    /// Marks that must be painted right now, with laser marks that already
    /// expired removed.
    public func visibleStrokes(at now: Date) -> [Stroke] {
        var result: [Stroke] = []
        for stroke in visibleStrokes {
            if stroke.tool.isTransient,
               let createdAt = stroke.createdAt,
               now.timeIntervalSince(createdAt) >= laserLifetime {
                continue
            }
            result.append(stroke)
        }
        return result
    }

    /// Every mark that must be visible right now, including the one in progress.
    public var visibleStrokes: [Stroke] {
        guard let active else { return strokes }
        return strokes + [active]
    }

    public var isEmpty: Bool { strokes.isEmpty && active == nil }

    public var stepCount: Int { nextStepNumber - 1 }

    /// Starts a mark. Numbered steps complete immediately; text stays active
    /// until its content is confirmed.
    @discardableResult
    public mutating func begin(at point: CGPoint, tool: Tool, ink: Ink, now: Date = Date()) -> Stroke {
        var stroke = Stroke(tool: tool, ink: ink, points: [point])
        if tool.isTransient { stroke.createdAt = now }

        if tool.commitsImmediately {
            stroke.stepNumber = nextStepNumber
            nextStepNumber += 1
        }

        active = stroke
        if tool.commitsImmediately { commit() }
        return stroke
    }

    /// Records what the user typed into the text mark in progress.
    public mutating func setActiveText(_ text: String, size: CGSize?) {
        guard var current = active, current.tool == .text else { return }
        current.text = text
        current.textSize = size
        active = current
    }

    /// Removes every mark the pointer touches. Returns the removed ids.
    @discardableResult
    public mutating func erase(at point: CGPoint, radius: CGFloat = 6) -> [UUID] {
        let doomed = strokes.filter { $0.hitTest(point, radius: radius) }
        guard !doomed.isEmpty else { return [] }

        let ids = Set(doomed.map(\.id))
        strokes.removeAll { ids.contains($0.id) }
        for stroke in doomed where stroke.stepNumber != nil {
            renumberFromScratch()
            break
        }
        return Array(ids)
    }

    /// Drops transient marks older than the lifetime.
    @discardableResult
    public mutating func pruneTransient(now: Date) -> Bool {
        let before = strokes.count
        strokes.removeAll { stroke in
            guard stroke.tool.isTransient, let createdAt = stroke.createdAt else { return false }
            return now.timeIntervalSince(createdAt) >= laserLifetime
        }
        return strokes.count != before
    }

    /// Numbered marks stay gapless after an erase.
    private mutating func renumberFromScratch() {
        var next = 1
        for index in strokes.indices where strokes[index].tool == .number {
            strokes[index].stepNumber = next
            next += 1
        }
        nextStepNumber = next
    }

    /// Extends the mark in progress. Ignored for click tools and when idle.
    /// With `straight`, the mark collapses to a straight line from its start to
    /// the current point, which is what holding Shift means while drawing.
    public mutating func extend(to point: CGPoint, straight: Bool = false) {
        guard var current = active, !current.tool.isClickTool else { return }

        if straight, let first = current.points.first {
            current.points = [first, point]
        } else {
            current.points.append(point)
        }
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
