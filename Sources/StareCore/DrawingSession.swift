import CoreGraphics
import Foundation

/// One mark's stored form (T10/S11): a DTO plain data types can persist, since
/// `Tool` and `Ink` are plain enums that ride in the blob as raw values. The
/// identity, geometry, ink, tool, numbering and every piece of mark metadata
/// ride along, so a restored canvas is the canvas that was there.
public struct PersistedStroke: Codable, Equatable, Sendable {
    public var id: UUID
    /// `Tool.rawValue` — an unknown value makes the mark unrenderable, so the
    /// restore drops it instead of drawing a wrong shape.
    public var tool: String
    /// `Ink.rawValue` — like the blob's own fields, an unknown value falls
    /// back to the default ink.
    public var ink: String
    public var points: [CGPoint]
    public var stepNumber: Int?
    public var text: String?
    public var textSize: CGSize?
    public var createdAt: Date?
    public var badgeSize: CGFloat?
    public var rotation: CGFloat
    /// S15: `true` when the shape was drawn filled. Nil in documents written
    /// before the field existed — they decode to the outline default.
    public var fill: Bool? = nil
    /// S15: `ArrowHeadStyle.rawValue` of an arrow mark's head, nil for every
    /// other tool and in documents written before the field existed; an
    /// unknown raw value falls back to the open head.
    public var arrowHead: String? = nil
    /// `RedactionStyle.rawValue` — the style the mark redacts with (S13).
    /// Optional because a document written before the field existed carries
    /// nothing: it decodes as nil and restores as the default blur.
    public var redactionStyle: String?
}

/// The persisted form of one mark (see `PersistedStroke`).
extension Stroke {
    /// The stored form of this mark.
    public var persisted: PersistedStroke {
        PersistedStroke(
            id: id,
            tool: tool.rawValue,
            ink: ink.rawValue,
            points: points,
            stepNumber: stepNumber,
            text: text,
            textSize: textSize,
            createdAt: createdAt,
            badgeSize: badgeSize,
            rotation: rotation,
            fill: isFilled ? true : nil,
            arrowHead: isFilledHead ? arrowHead.rawValue : nil,
            redactionStyle: redactionStyle.rawValue
        )
    }

    /// Rebuilds the mark from its stored form. nil when the tool named is one
    /// this build does not know — a foreign document must never draw a wrong
    /// shape; the mark is simply not restored. Transient marks (laser) are
    /// refused here too: a stored mark that would have faded anyway must not
    /// resurrect.
    public init?(persisted stroke: PersistedStroke) {
        guard let tool = Tool(rawValue: stroke.tool), !tool.isTransient else { return nil }
        self.init(
            id: stroke.id,
            tool: tool,
            ink: Ink(rawValue: stroke.ink) ?? .red,
            points: stroke.points,
            stepNumber: stroke.stepNumber,
            text: stroke.text,
            textSize: stroke.textSize,
            createdAt: stroke.createdAt,
            badgeSize: stroke.badgeSize,
            rotation: stroke.rotation,
            fill: stroke.fill ?? false,
            arrowHead: stroke.arrowHead.flatMap(ArrowHeadStyle.init(rawValue:)) ?? .open,
            // Lenient like the blob's own fields: a document without the
            // field (every drawing saved before it existed) restores as the
            // audited blur, and an unknown raw value falls back to it too.
            redactionStyle: stroke.redactionStyle.flatMap(RedactionStyle.init(rawValue:)) ?? .blur
        )
    }

    /// Whether a mark stores nothing extra, so its persisted form omits the
    /// S15 fields entirely and a document carries no decoration it does not
    /// show.
    private var isFilledHead: Bool {
        tool == .arrow && arrowHead == .filled
    }
}

/// The marks of one drawing layer plus its undo history. A session is a value
/// type: the overlay owns one per display, and tests drive it directly.
public struct DrawingSession: Equatable, Sendable {
    /// The remembered default of the next text mark (S15): a font size in
    /// points and an ink.
    public struct TextMarkStyle: Equatable, Sendable {
        public var fontSize: CGFloat
        public var ink: Ink

        public init(fontSize: CGFloat, ink: Ink) {
            self.fontSize = fontSize
            self.ink = ink
        }
    }
    /// Committed marks, in draw order.
    public private(set) var strokes: [Stroke] = []
    /// Marks `undo` took away, newest last, waiting for `redo`.
    public var undoneStrokes: [Stroke] {
        redoOps.compactMap {
            if case let .removed(stroke) = $0 { return stroke }
            return nil
        }
    }
    /// The mark currently being dragged, not yet committed.
    public private(set) var active: Stroke?
    public private(set) var nextStepNumber: Int = 1
    /// How long laser marks live before they are pruned.
    public var laserLifetime: TimeInterval = 1.2
    /// The style the next text mark starts with (S15): the size and ink of the
    /// last committed text mark, session-scoped — nothing persists it, and a
    /// fresh session starts with no memory, so the next text falls back to the
    /// shipped default the view measures with.
    public private(set) var lastTextStyle: TextMarkStyle?

    /// What undo can reverse, newest last.
    private enum UndoOp: Sendable, Equatable {
        /// The mark was put on the canvas; undo takes it off again.
        case added(Stroke)
        /// The mark was transformed; undo restores the previous geometry.
        case transformed(previous: Stroke, transformed: Stroke)
        /// Every mark was cleared together in one step (the Escape clear,
        /// T4/S5); undo restores the whole batch. The strokes are journalled
        /// in draw order as they were when the clear took them.
        case cleared([Stroke])
        /// The marks of a multi-selection moved together in one drag
        /// (T6b/S8); undo restores every member's previous geometry. The
        /// arrays are journalled in draw order, one entry per group: the
        /// batch is ONE undo step, never one per mark.
        case movedBatch(previous: [Stroke], transformed: [Stroke])
    }

    /// What redo can reapply, newest last.
    private enum RedoOp: Sendable, Equatable {
        /// The mark is off the canvas; redo puts it back.
        case removed(Stroke)
        /// The mark holds the previous geometry; redo reapplies the transform.
        case transformed(previous: Stroke, transformed: Stroke)
        /// The cleared batch was restored; redo clears it again (T4/S5).
        case cleared([Stroke])
        /// The batch move was undone; redo reapplies it to every member
        /// whose mark still exists.
        case movedBatch(previous: [Stroke], transformed: [Stroke])
    }

    private var undoOps: [UndoOp] = []
    private var redoOps: [RedoOp] = []

    public init() {}

    public static func == (lhs: DrawingSession, rhs: DrawingSession) -> Bool {
        lhs.strokes == rhs.strokes
            && lhs.undoneStrokes == rhs.undoneStrokes
            && lhs.active == rhs.active
            && lhs.nextStepNumber == rhs.nextStepNumber
            && lhs.laserLifetime == rhs.laserLifetime
            && lhs.lastTextStyle == rhs.lastTextStyle
            // Two sessions that only look alike but hold different history
            // behave differently on undo/redo, so the journals count too.
            && lhs.undoOps == rhs.undoOps
            && lhs.redoOps == rhs.redoOps
    }

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

    public var canRedo: Bool { !redoOps.isEmpty }

    public var stepCount: Int { nextStepNumber - 1 }

    /// Starts a mark. Numbered steps complete immediately; text stays active
    /// until its content is confirmed. The edit cursor never starts a mark: it
    /// transforms existing ones, so a stray drag must leave nothing behind.
    /// `redactionStyle` (T6b/S13) is what the mark redacts with — today's blur
    /// unless the calling surface names the persisted choice; every existing
    /// caller compiles against the default.
    @discardableResult
    public mutating func begin(
        at point: CGPoint,
        tool: Tool,
        ink: Ink,
        fill: Bool = false,
        arrowHead: ArrowHeadStyle = .open,
        now: Date = Date(),
        redactionStyle: RedactionStyle = .blur
    ) -> Stroke {
        guard !tool.isSelection else {
            return Stroke(tool: tool, ink: ink, points: [point])
        }
        var stroke = Stroke(tool: tool, ink: ink, points: [point], redactionStyle: redactionStyle)
        if tool.isTransient { stroke.createdAt = now }
        // The badge stores the size it is drawn at, so a later uniform scale
        // scales the badge and its digit with it (advisory A).
        if tool == .number { stroke.badgeSize = PathBuilder.badgeDiameter }
        // S15: the style keys arm properties of the next mark. Only the tool
        // a property belongs to stores it, so a mark never carries a style it
        // never shows.
        switch tool {
        case .rectangle, .ellipse: stroke.isFilled = fill
        case .arrow: stroke.arrowHead = arrowHead
        default: break
        }

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

    /// Remembers the style the next text mark starts with (S15). Called by the
    /// surface that knows the measured font size at the moment a text mark
    /// commits; an unusable size is refused so the memory never holds garbage.
    public mutating func rememberTextStyle(_ style: TextMarkStyle) {
        guard style.fontSize > 0 else { return }
        lastTextStyle = style
    }

    /// Removes every mark the pointer touches. Returns the removed ids.
    @discardableResult
    public mutating func erase(at point: CGPoint, radius: CGFloat = 6) -> [UUID] {
        let doomed = strokes.filter { $0.hitTest(point, radius: radius) }
        guard !doomed.isEmpty else { return [] }

        let ids = Set(doomed.map(\.id))
        strokes.removeAll { ids.contains($0.id) }
        // Erasing is an edit: the history forks and nothing comes back.
        redoOps.removeAll()
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

    /// Finishes the mark in progress and appends it to the session. The edit
    /// cursor can never become one, even if something started it.
    public mutating func commit() {
        guard var current = active, !current.tool.isSelection else {
            active = nil
            return
        }

        if current.tool.usesEndpointsOnly,
           let first = current.points.first,
           let last = current.points.last {
            current.points = [first, last]
        }

        // Text only becomes a mark once it has content: a stray click must not
        // leave an invisible box behind, and the editor owns that lifetime.
        let isRenderable: Bool
        if current.tool == .text {
            isRenderable = !(current.text ?? "").isEmpty
        } else {
            isRenderable = current.points.count >= 2 || current.tool.isClickTool
        }
        if isRenderable {
            strokes.append(current)
            redoOps.removeAll()
            undoOps.append(.added(current))
        }
        active = nil
    }

    /// Discards the mark in progress, otherwise reverses the newest change:
    /// a committed mark goes away, a transform restores the previous geometry.
    /// Numbered marks give their number back so the sequence stays gapless, and
    /// whatever undo reversed waits for `redo`.
    @discardableResult
    public mutating func undo() -> Bool {
        if active != nil {
            active = nil
            return true
        }
        while let op = undoOps.popLast() {
            switch op {
            case let .added(stroke):
                // Marks removed by erase or the external history never come
                // back here; their undo entries are stale and are skipped.
                guard let index = strokes.firstIndex(where: { $0.id == stroke.id }) else { continue }
                // The number comes from the live stroke, never the journalled
                // snapshot: an erase may have renumbered it, and undo has to
                // hand back exactly the number the mark carries now.
                let live = strokes[index]
                strokes.remove(at: index)
                if let number = live.stepNumber {
                    nextStepNumber = number
                }
                redoOps.append(.removed(live))
                return true
            case let .transformed(previous, transformed):
                guard let index = strokes.firstIndex(where: { $0.id == transformed.id }) else { continue }
                let live = strokes[index]
                strokes[index] = previous
                redoOps.append(.transformed(previous: previous, transformed: live))
                return true
            case let .cleared(removed):
                // The marks the clear took away come back exactly as they
                // were, draw order included. A batch member deleted by hand
                // in the meantime stays gone — that is the eraser's rule.
                let restored = removed.filter { stroke in
                    !strokes.contains(where: { $0.id == stroke.id })
                }
                guard !restored.isEmpty else { continue }
                strokes.append(contentsOf: restored)
                if restored.contains(where: { $0.stepNumber != nil }) {
                    renumberFromScratch()
                }
                redoOps.append(.cleared(restored))
                return true
            case let .movedBatch(previous, transformed):
                // The group move comes back all at once (T6b/S8). A member
                // the eraser took away in the meantime stays gone and the
                // batch member deleted by hand never undoes the group — the
                // same skip-stale rule the clear keeps.
                var restored: [Stroke] = []
                var restoredTransformed: [Stroke] = []
                for target in transformed {
                    guard let index = strokes.firstIndex(where: { $0.id == target.id }),
                          let original = previous.first(where: { $0.id == target.id }) else { continue }
                    restoredTransformed.append(strokes[index])
                    restored.append(original)
                    strokes[index] = original
                }
                guard !restored.isEmpty else { continue }
                redoOps.append(.movedBatch(previous: restored, transformed: restoredTransformed))
                return true
            }
        }
        return false
    }

    /// Puts back the newest change `undo` reversed, and takes a numbered mark's
    /// step number again.
    @discardableResult
    public mutating func redo() -> Bool {
        guard let op = redoOps.popLast() else { return false }
        switch op {
        case let .removed(stroke):
            strokes.append(stroke)
            if stroke.stepNumber != nil {
                // The journalled number is stale when marks after it were
                // renumbered: the restored mark takes the next free number so
                // the sequence stays gapless.
                renumberFromScratch()
            }
            undoOps.append(.added(stroke))
            return true
        case let .transformed(previous, transformed):
            guard let index = strokes.firstIndex(where: { $0.id == previous.id }) else { return false }
            strokes[index] = transformed
            undoOps.append(.transformed(previous: previous, transformed: transformed))
            return true
        case let .cleared(restore):
            // The restored batch goes away again (T4/S5). Whatever was
            // already deleted by hand stays gone, and numbering stays
            // gapless exactly like a single-mark removal.
            var cleared: [Stroke] = []
            for stroke in restore {
                guard let index = strokes.firstIndex(where: { $0.id == stroke.id }) else { continue }
                cleared.append(strokes.remove(at: index))
            }
            if cleared.contains(where: { $0.stepNumber != nil }) {
                renumberFromScratch()
            }
            undoOps.append(.cleared(cleared))
            return !cleared.isEmpty
        case let .movedBatch(previous, transformed):
            // The undone group move is applied again to every member whose
            // mark still exists (T6b/S8), exactly the subset rule the undo
            // side keeps; the journal walks back with the applied subset.
            var restoredPrevious: [Stroke] = []
            var reapplied: [Stroke] = []
            for target in transformed {
                guard let index = strokes.firstIndex(where: { $0.id == target.id }),
                      let original = previous.first(where: { $0.id == target.id }) else { continue }
                restoredPrevious.append(strokes[index])
                reapplied.append(target)
                strokes[index] = target
            }
            guard !reapplied.isEmpty else { return false }
            undoOps.append(.movedBatch(previous: restoredPrevious, transformed: reapplied))
            return true
        }
    }

    /// The group move (T6b/S8): several committed marks — the marks of a
    /// multi-selection — are replaced by their translated copies and ONE
    /// history op holds the whole batch, so a later undo restores every
    /// member in a single step and redo reapplies it. Members whose id no
    /// longer exists are skipped, and a member whose geometry did not
    /// change journals nothing — so an empty batch never eats an undo step
    /// and never forks the redo history. Returns false when nothing changed.
    @discardableResult
    public mutating func replaceBatch(_ replacements: [Stroke]) -> Bool {
        var previous: [Stroke] = []
        var transformed: [Stroke] = []
        for stroke in replacements {
            guard let index = strokes.firstIndex(where: { $0.id == stroke.id }),
                  strokes[index] != stroke else { continue }
            previous.append(strokes[index])
            transformed.append(stroke)
            strokes[index] = stroke
        }
        guard !transformed.isEmpty else { return false }
        // A transform is an edit like a new mark: the redo history forks.
        redoOps.removeAll()
        undoOps.append(.movedBatch(previous: previous, transformed: transformed))
        return true
    }

    /// Replaces a committed mark with a transformed copy — a move, a uniform
    /// scale or a rotation applied to the drag-start snapshot. The previous
    /// geometry is journalled, so `undo` restores it and `redo` reapplies the
    /// transform. Returns false when no mark has that id; a no-op replacement
    /// is journalled neither, so it never eats an undo step.
    @discardableResult
    public mutating func replace(_ stroke: Stroke) -> Bool {
        guard let index = strokes.firstIndex(where: { $0.id == stroke.id }) else { return false }
        let previous = strokes[index]
        guard previous != stroke else { return true }
        strokes[index] = stroke
        // A transform is an edit like a new mark: the redo history forks.
        redoOps.removeAll()
        undoOps.append(.transformed(previous: previous, transformed: stroke))
        return true
    }

    /// Removes every mark and restarts the numbered sequence. The hard clear:
    /// it never journals anything, so what it removes is gone for good. The
    /// Escape clear that goes into the history is `clearForUndo` (T4/S5).
    public mutating func clear() {
        strokes.removeAll()
        redoOps.removeAll()
        undoOps.removeAll()
        active = nil
        nextStepNumber = 1
        // The style memory is session-scoped (S15): a cleared session starts
        // its next text over with the shipped default.
        lastTextStyle = nil
    }

    /// The Escape clear (T4/S5): every committed mark goes away as one undoable
    /// step, journalled in draw order, so `undo` restores the exact batch and
    /// `redo` clears it again. A clear is an edit like the eraser, so the redo
    /// history forks. An empty layer gives false and adds no history step —
    /// and leaves the redo history alone. The mark in progress is discarded
    /// unjournaled, the way every clear has always treated it.
    @discardableResult
    public mutating func clearForUndo() -> Bool {
        active = nil
        guard !strokes.isEmpty else { return false }
        let removed = strokes
        strokes.removeAll()
        redoOps.removeAll()
        undoOps.append(.cleared(removed))
        nextStepNumber = 1
        return true
    }

    /// Whether the newest *live* undo entry is a clear (T4/S5), so the global
    /// history can route a popped clear entry here and never undo a different
    /// op than the one it named. The scan skips stale entries exactly the way
    /// `undo` skips them, so both scans always stop on the same op.
    public var canUndoClear: Bool {
        for op in undoOps.reversed() {
            switch op {
            case let .added(stroke):
                guard strokes.contains(where: { $0.id == stroke.id }) else { continue }
                return false
            case let .transformed(_, transformed):
                guard strokes.contains(where: { $0.id == transformed.id }) else { continue }
                return false
            case let .movedBatch(_, transformed):
                // A live batch move blocks any clear: the scan stops here,
                // the same point `undo` will act on.
                guard strokes.contains(where: { stroke in transformed.contains { $0.id == stroke.id } }) else { continue }
                return false
            case .cleared:
                return true
            }
        }
        return false
    }

    /// Whether the newest redo entry is a clear (T4/S5), so the global history
    /// can route a popped clear entry here.
    public var canRedoClear: Bool {
        guard case .cleared = redoOps.last else { return false }
        return true
    }

    /// Drops a specific mark, used by the cursor's ⌫ and the overlay's history
    /// across displays. A numbered mark leaves a gapless sequence behind,
    /// exactly like the eraser: the marks after it take the freed numbers.
    @discardableResult
    public mutating func remove(id: UUID) -> Bool {
        guard let index = strokes.firstIndex(where: { $0.id == id }) else { return false }
        let removed = strokes.remove(at: index)
        // A mark removed by id is the global undo history at work, so it waits for
        // redo exactly like `undo` leaves it.
        redoOps.append(.removed(removed))
        if removed.stepNumber != nil {
            renumberFromScratch()
        }
        return true
    }

    /// Whether `redo` would restore a mark with this id — removed by `undo` or
    /// `remove(id:)`, or transformed and undone — so the global history can
    /// route a redo across displays.
    public func canRedo(markWithID id: UUID) -> Bool {
        guard let op = redoOps.last else { return false }
        switch op {
        case let .removed(stroke): return stroke.id == id
        case let .transformed(_, transformed): return transformed.id == id
        case .cleared, .movedBatch: return false
        }
    }

    /// Whether the newest *live* undo entry is about the mark with this id, so
    /// the global history can route a Command-Z across displays and never undo
    /// a different op than the one it popped. Entries whose mark no longer
    /// exists (it was erased externally) are skipped, exactly the way `undo`
    /// skips them, so both scans always stop on the same op.
    public func canUndo(markWithID id: UUID) -> Bool {
        for op in undoOps.reversed() {
            switch op {
            case let .added(stroke):
                guard strokes.contains(where: { $0.id == stroke.id }) else { continue }
                return stroke.id == id
            case let .transformed(_, transformed):
                guard strokes.contains(where: { $0.id == transformed.id }) else { continue }
                return transformed.id == id
            case let .movedBatch(_, transformed):
                // The group move is the newest live op: no single mark can
                // match it — its own entry is the batch one (T6b/S8). A
                // member deleted by hand makes it stale, and the scan walks
                // on exactly like `undo` does.
                guard strokes.contains(where: { stroke in transformed.contains { $0.id == stroke.id } }) else { continue }
                return false
            case .cleared:
                // The clear is the newest live op: no single mark can match
                // it, and the scan must stop here like `undo` will.
                return false
            }
        }
        return false
    }

    /// Whether the newest *live* undo entry is a group move (T6b/S8), so the
    /// global history can route a popped batch-move entry here and never undo
    /// a different change than the one it named. The scan skips stale entries
    /// exactly the way `undo` skips them, so both scans always stop on the
    /// same op.
    public var canUndoBatchMove: Bool {
        for op in undoOps.reversed() {
            switch op {
            case let .added(stroke):
                guard strokes.contains(where: { $0.id == stroke.id }) else { continue }
                return false
            case let .transformed(_, transformed):
                guard strokes.contains(where: { $0.id == transformed.id }) else { continue }
                return false
            case .cleared:
                return false
            case let .movedBatch(_, transformed):
                // The batch is live while at least one member's moved copy
                // is still on the canvas — a member erased in the meantime
                // never blocks the group step unraveling at large.
                return strokes.contains { stroke in transformed.contains { $0.id == stroke.id } }
            }
        }
        return false
    }

    /// Whether the newest redo entry is a group move (T6b/S8), so the global
    /// history can route a popped batch-move entry here.
    public var canRedoBatchMove: Bool {
        guard case let .movedBatch(_, transformed) = redoOps.last else { return false }
        return strokes.contains { stroke in transformed.contains { $0.id == stroke.id } }
    }
}

/// The persisted-form seam (T10/S11): what a snapshot keeps and how a
/// restored session comes back.
public extension DrawingSession {
    /// The marks a persistence snapshot stores: every committed mark that is
    /// not transient. A laser mark would have faded before the session was
    /// ever saved, so it is never stored, and the snapshot intentionally
    /// carries no undo state — the journals belong to the live session and
    /// restart with it.
    var persistedStrokes: [Stroke] {
        strokes.filter { !$0.tool.isTransient }
    }

    /// Rebuilds a session from stored marks: every mark comes back exactly as
    /// it was saved (identity, geometry, ink, tool, numbering), with the
    /// numbered sequence continuing after the highest stored number, and no
    /// mark in progress. Transient marks a stale or hand-built payload still
    /// carries are refused, the same rule the writer keeps.
    static func restored(strokes: [Stroke]) -> DrawingSession {
        var session = DrawingSession()
        let live = strokes.filter { !$0.tool.isTransient }
        session.strokes = live
        session.nextStepNumber = (live.compactMap(\.stepNumber).max() ?? 0) + 1
        return session
    }
}
