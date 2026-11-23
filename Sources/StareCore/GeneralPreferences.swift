import Foundation
import CoreGraphics

/// Where the drawing overlay draws: every display or only the one under the
/// pointer. Raw values are what the versioned preferences blob persists and
/// the strings today's picker has always used; decoding an unknown raw value
/// falls back to the default instead of failing the document.
public enum OverlayScope: String, Codable, CaseIterable, Sendable {
    /// Draw on every display.
    case all
    /// Draw only on the display the pointer is on when the session starts —
    /// the default, so a second monitor the person is watching is never
    /// covered by a sheet they did not ask for.
    case active

    /// English label shown in Settings, matching today's picker.
    public var title: String {
        switch self {
        case .all: "Every display"
        case .active: "Only the active display"
        }
    }
}

/// Where the palette opens. Raw values are what the versioned preferences
/// blob persists and the strings today's picker has always used; decoding an
/// unknown raw value falls back to the default instead of failing the
/// document.
public enum PalettePlacement: String, Codable, CaseIterable, Sendable {
    /// Near the pointer — today's default.
    case cursor
    /// On the display of the front window.
    case frontWindow
    /// On the last used display.
    case fixed

    /// English label shown in Settings, matching today's picker.
    public var title: String {
        switch self {
        case .cursor: "Under the pointer"
        case .frontWindow: "On the display of the front window"
        case .fixed: "On the last used display"
        }
    }
}

/// How long a laser mark stays on screen before fading out, in seconds. The
/// raw values are exactly today's picker values; decoding an unknown raw
/// value falls back to the default instead of failing the document.
public enum LaserLifetime: Double, Codable, CaseIterable, Sendable {
    case one = 1
    case two = 2
    case twoPointFive = 2.5
    case three = 3
    case five = 5

    /// English label shown in Settings. Verbatim today's picker strings,
    /// including the "1 seconds" wording, so the copy never changes.
    public var title: String {
        switch self {
        case .one: "1 seconds"
        case .two: "2 seconds"
        case .twoPointFive: "2.5 seconds"
        case .three: "3 seconds"
        case .five: "5 seconds"
        }
    }
}

/// How the toolbar lays its items out (T9/S12): a single horizontal row or
/// a vertical stack. Raw values are what the versioned preferences blob
/// persists; decoding an unknown raw value falls back to the default instead
/// of failing the document.
public enum ToolbarOrientation: String, Codable, CaseIterable, Sendable {
    /// Items in one row — today's default.
    case horizontal
    /// Items stacked in one column.
    case vertical

    /// English label shown in Settings.
    public var title: String {
        switch self {
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        }
    }
}

/// Which screen edge the toolbar rests at (T9/S12). Raw values are what the
/// versioned preferences blob persists; decoding an unknown raw value falls
/// back to the default instead of failing the document.
public enum ToolbarBorder: String, Codable, CaseIterable, Sendable {
    /// Along the top edge — today's default.
    case top
    /// Along the bottom edge.
    case bottom
    /// Along the left edge.
    case left
    /// Along the right edge.
    case right

    /// English label shown in Settings.
    public var title: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        case .left: "Left"
        case .right: "Right"
        }
    }

    /// The docked edges that make sense for an orientation (T3/S4): a
    /// horizontal row rests on the top or bottom edge; a vertical column on
    /// the left or right. This is the exact list the Settings picker offers,
    /// so an edge the orientation cannot sit on is never choosable.
    public static func validEdges(for orientation: ToolbarOrientation) -> [ToolbarBorder] {
        switch orientation {
        case .horizontal: [.top, .bottom]
        case .vertical: [.left, .right]
        }
    }

    /// The edge an orientation falls back to (T3/S4): the first valid edge —
    /// the top for a horizontal row (the dock the app has always opened
    /// with), the left for a vertical column, its mirror on the column's
    /// first edge.
    public static func fallbackEdge(for orientation: ToolbarOrientation) -> ToolbarBorder {
        validEdges(for: orientation)[0]
    }

    /// This edge made valid for `orientation` (T3/S4): itself when it is one
    /// of the orientation's edges, the orientation's fallback edge otherwise.
    /// Every stored pair passes through here on decode, so a changed
    /// orientation can never leave the pair inconsistent (horizontal + left
    /// or vertical + top).
    public func validated(for orientation: ToolbarOrientation) -> ToolbarBorder {
        Self.validEdges(for: orientation).contains(self) ? self : Self.fallbackEdge(for: orientation)
    }
}

/// One placeable item of the drawing toolbar's layout (T6/S5): a tool, or a
/// real separator the user can place, move and take away. Separators are
/// items of the stored layout — not the automatic family grouping the bar
/// used to draw — and the bar renders the list exactly as stored, with
/// separators drawn as dividers.
public enum ToolbarLayoutItem: Hashable, Sendable {
    /// A drawing tool placed on the bar.
    case tool(Tool)
    /// A divider between two neighbouring items.
    case separator

    /// The stable identifier the stored document and the drag payload both
    /// use. It names the item itself, never a slot, so every zone of the
    /// organiser decodes the same wire format and an identifier stays
    /// meaningful however the draft changes. The `tool:` prefix keeps a
    /// future tool named "separator" unambiguous.
    public var identifier: String {
        switch self {
        case .tool(let tool): "tool:\(tool.rawValue)"
        case .separator: "separator"
        }
    }

    /// The item an identifier names; anything else is nil and every decode
    /// drops it.
    public init?(identifier: String) {
        if identifier == "separator" {
            self = .separator
        } else if identifier.hasPrefix("tool:"), let tool = Tool(rawValue: String(identifier.dropFirst(5))) {
            self = .tool(tool)
        } else {
            return nil
        }
    }

    /// The tool this item holds, or nil for a separator.
    public var tool: Tool? {
        if case .tool(let tool) = self { return tool }
        return nil
    }
}

/// Which tools the drawing toolbar shows, in what order, and which wait in
/// the pool (T6/S5): the stored form is the bar's item list — every entry a
/// tool or a separator — plus the pool's tools in pool order. Normalisation
/// keeps every broken state unreachable: unknown identifiers drop, tools the
/// bar list never mentions land in the pool (never silently on the bar),
/// duplicated tools collapse to their first occurrence, and leading, trailing
/// or repeated separators are cleaned so the bar can never render an empty
/// end. A document that would leave the bar with no tool is refused and the
/// shipped bar comes back.
///
/// This is the drawing toolbar's layout only — the capture editor keeps its
/// own fixed family-grouped palette over a still image, and a keyboard
/// shortcut is not the bar: an off-bar tool stays shortcut-armed.
public struct ToolbarToolLayout: Codable, Equatable, Sendable {
    /// The bar's items in display order: tools and separators, normalised.
    public var items: [ToolbarLayoutItem]
    /// Every tool that is not on the bar, in the pool's order.
    public var pool: [Tool]

    /// The documented default order: exactly the grouped bar flattened — the
    /// same sequence `Tool.toolbarGroups` renders.
    public static let defaultOrder = Tool.toolbarGroups.flatMap { $0 }

    /// The items a fresh install draws: every tool in the documented order
    /// with a separator exactly between the tool families — the dividers the
    /// grouped bar has always placed.
    public static let standardItems: [ToolbarLayoutItem] = {
        var items: [ToolbarLayoutItem] = []
        for group in Tool.toolbarGroups {
            if !items.isEmpty { items.append(.separator) }
            items.append(contentsOf: group.map(ToolbarLayoutItem.tool))
        }
        return items
    }()

    /// The layout a fresh install gets: every tool on the bar in today's
    /// order with the family dividers, an empty pool.
    public static let standard = ToolbarToolLayout()

    /// Creates a layout. The stored form is normalised: duplicate tools
    /// collapse to their first occurrence, a separator only ever sits between
    /// two tools (leading, trailing and repeated ones are cleaned), the pool
    /// ends up holding exactly the tools that are off the bar — the stored
    /// pool order first, anything it never mentions behind in the documented
    /// default order — and a list without a single tool is refused, bringing
    /// the shipped bar back.
    public init(items: [ToolbarLayoutItem] = ToolbarToolLayout.standardItems, pool: [Tool] = []) {
        var seen = Set<Tool>()
        var ordered: [ToolbarLayoutItem] = []
        for item in items {
            switch item {
            case .tool(let tool):
                if seen.insert(tool).inserted { ordered.append(item) }
            case .separator:
                if ordered.last?.tool != nil { ordered.append(item) }
            }
        }
        while ordered.last == .separator { ordered.removeLast() }
        guard ordered.contains(where: { $0.tool != nil }) else {
            self = .standard
            return
        }
        let onBar = Set(ordered.compactMap(\.tool))
        var poolSeen = Set<Tool>()
        var poolOrder: [Tool] = []
        for tool in pool where !onBar.contains(tool) && poolSeen.insert(tool).inserted {
            poolOrder.append(tool)
        }
        for tool in ToolbarToolLayout.defaultOrder where !onBar.contains(tool) && poolSeen.insert(tool).inserted {
            poolOrder.append(tool)
        }
        self.items = ordered
        self.pool = poolOrder
    }

    /// The tools the bar draws, in order.
    public var visibleTools: [Tool] {
        items.compactMap(\.tool)
    }

    /// The items of the v0.4-shaped bar: the stored tool order with a
    /// separator wherever the family changed — the dividers the old
    /// `visibleGroups` rendering drew.
    static func itemsWithFamilySeparators(_ tools: [Tool]) -> [ToolbarLayoutItem] {
        var families: [Tool: Int] = [:]
        for (index, group) in Tool.toolbarGroups.enumerated() {
            for tool in group { families[tool] = index }
        }
        var items: [ToolbarLayoutItem] = []
        var lastFamily: Int? = nil
        for tool in tools {
            let family = families[tool]
            if let last = lastFamily, let family, last != family {
                items.append(.separator)
            }
            items.append(.tool(tool))
            lastFamily = family
        }
        return items
    }

    /// Drops `item` into the bar at `index` — the organiser's pool drop. A
    /// tool comes out of the pool and lands where it is dropped; a separator
    /// joins the bar at the nearest legal slot — a slot strictly between two
    /// tools (the bar can never render an empty end, so a one-tool bar
    /// refuses a separator outright; a bar with no tool-tool gap left
    /// refuses too). A slot request that lands beside another separator
    /// slides to the nearest legal gap instead of collapsing into it — the
    /// dropped separator stays a real item, never silently vanishes.
    public func inserting(_ item: ToolbarLayoutItem, at index: Int) -> ToolbarToolLayout {
        var copy = items
        if item.tool == nil {
            guard let target = Self.nearestSeparatorSlot(near: index, in: copy) else { return self }
            copy.insert(item, at: target)
        } else {
            let target = min(max(index, 0), copy.count)
            copy.insert(item, at: target)
        }
        let movedTool = item.tool
        return ToolbarToolLayout(items: copy, pool: pool.filter { $0 != movedTool })
    }

    /// Moves `item` to `index` — the insert position in the list as it would
    /// be without the item. A tool clamps at both ends; a separator lands in
    /// the nearest legal slot — strictly between two tools — so a stray
    /// request beside another separator never erases one of them. An item
    /// the bar does not hold changes nothing, and the pool is untouched.
    public func moving(_ item: ToolbarLayoutItem, to index: Int) -> ToolbarToolLayout {
        guard let current = items.firstIndex(of: item) else { return self }
        var copy = items
        copy.remove(at: current)
        let target: Int
        if item.tool == nil {
            guard let slot = Self.nearestSeparatorSlot(near: index, in: copy) else { return self }
            target = slot
        } else {
            target = min(max(index, 0), copy.count)
        }
        copy.insert(item, at: target)
        // T5/S5: a bar-to-bar move may leave a separator where normalisation
        // would erase it — stranded at a bar end or beside another one. It
        // relocates to the nearest legal slot instead of being deleted, so
        // reordering in place never costs a placed separator; one with no
        // legal home left (no tool-tool gap) still goes, as normalisation
        // always did.
        return ToolbarToolLayout(items: Self.relocatingOrphanedSeparators(in: copy), pool: pool)
    }

    /// Where a separator may sit: only strictly between two tools, so the
    /// slots of a bar-to-be with `count` items are 1...(count-1) — and both
    /// neighbours must be tools, or the fresh separator would sit beside
    /// (or be collapsed with) another one. The request is clamped into the
    /// slot range first, then the nearest legal slot wins; ties go to the
    /// lower slot. A one-tool bar offers none, and a bar whose every gap
    /// already holds a separator offers none either.
    private static func nearestSeparatorSlot(
        near index: Int, in items: [ToolbarLayoutItem]
    ) -> Int? {
        let top = items.count - 1
        guard top >= 1 else { return nil }
        let requested = min(max(index, 1), top)
        var best: Int?
        var bestDistance = Int.max
        for slot in 1...top where items[slot - 1].tool != nil && items[slot].tool != nil {
            let distance = abs(slot - requested)
            if distance < bestDistance {
                best = slot
                bestDistance = distance
            }
        }
        return best
    }

    /// T5/S5: slides every separator a move would orphan — leading, trailing
    /// or beside another separator — to the nearest legal slot (strictly
    /// between two tools), judged from where the separator sits. Each
    /// relocation lands in a legal slot and so can never orphan another
    /// one, so the rescan settles; a separator with no legal slot on the
    /// whole bar is dropped, exactly what normalisation would have done.
    private static func relocatingOrphanedSeparators(
        in items: [ToolbarLayoutItem]
    ) -> [ToolbarLayoutItem] {
        var result = items
        var changed = true
        while changed {
            changed = false
            for index in result.indices {
                guard result[index].tool == nil else { continue }
                let orphaned = index == 0
                    || index == result.count - 1
                    || (index > 0 && result[index - 1].tool == nil)
                    || (index < result.count - 1 && result[index + 1].tool == nil)
                guard orphaned else { continue }
                let separator = result.remove(at: index)
                if let slot = nearestSeparatorSlot(near: index, in: result) {
                    result.insert(separator, at: slot)
                }
                changed = true
                break
            }
        }
        return result
    }

    /// Whether `item` can be dragged out of the bar into the pool (T3/S2): the
    /// bar keeps its first tool, so the leading tool cannot leave, and every
    /// other item — placed separators included — can. The pool's handlers
    /// refuse the drag-out on this answer and the preview marks the item
    /// fixed by it, so the two halves of the organiser can never disagree;
    /// the model's own `removing` keeps its last-tool guard, and a pinned
    /// item stays draggable inside the bar (S5), so the pin never blocks
    /// in-place reordering.
    public func canLeave(_ item: ToolbarLayoutItem) -> Bool {
        item.tool == nil ? true : visibleTools.first != item.tool
    }

    /// Takes `item` off the bar into the pool. The last tool is refused — the
    /// bar can never go empty — and the layout comes back unchanged.
    /// `poolIndex` places the tool inside the pool, clamped into
    /// `0...pool.count` so a negative or too-large index can never trap
    /// (the verifier's crash: a negative index used to reach `Array.insert`
    /// and die with "Negative Array index is out of range"); nil appends at
    /// the end.
    public func removing(_ item: ToolbarLayoutItem, intoPoolAt poolIndex: Int? = nil) -> ToolbarToolLayout {
        guard let current = items.firstIndex(of: item) else { return self }
        if item.tool != nil, visibleTools.count <= 1 { return self }
        var copy = items
        copy.remove(at: current)
        var poolOrder = pool
        if let tool = item.tool {
            // Clamped into 0...pool.count (verifier finding: a negative
            // index used to trap); nil appends at the end.
            let at = poolIndex.map { min(max($0, 0), poolOrder.count) } ?? poolOrder.count
            poolOrder.insert(tool, at: at)
        }
        return ToolbarToolLayout(items: copy, pool: poolOrder)
    }

    /// Reorders the pool: `tool` moves to `index` — the insert position in
    /// the pool as it would be without the tool (clamped). A tool not in the
    /// pool changes nothing.
    public func movingInPool(_ tool: Tool, to index: Int) -> ToolbarToolLayout {
        guard pool.contains(tool) else { return self }
        var copy = pool.filter { $0 != tool }
        let target = min(max(index, 0), copy.count)
        copy.insert(tool, at: target)
        return ToolbarToolLayout(items: items, pool: copy)
    }

    private enum CodingKeys: String, CodingKey {
        case items, pool, tools, hidden
    }

    /// Lenient decoding. The v0.5 shape holds `items` (identifier strings:
    /// `tool:` plus a tool raw value, or the `separator` token) and `pool`
    /// (raw tool values); unknown identifiers drop. A blob without that shape
    /// but holding the v0.4 `tools`/`hidden` fields decodes into the new one
    /// with the same visible set and order the old bar drew — separators
    /// wherever the family changed. Anything older is the shipped bar.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.items) {
            let rawItems = (try? container.decode([String].self, forKey: .items)) ?? []
            let rawPool = (try? container.decode([String].self, forKey: .pool)) ?? []
            self.init(items: rawItems.compactMap(ToolbarLayoutItem.init(identifier:)), pool: rawPool.compactMap(Tool.init(rawValue:)))
            return
        }
        let rawTools = (try? container.decode([String].self, forKey: .tools)) ?? []
        let rawHidden = (try? container.decode([String].self, forKey: .hidden)) ?? []
        guard !rawTools.isEmpty else {
            // An empty stored list — like a field the blob never had — is the
            // shipped bar, not an empty one.
            self = .standard
            return
        }
        var seen = Set<Tool>()
        var stored: [Tool] = []
        for tool in rawTools.compactMap(Tool.init(rawValue:)) where seen.insert(tool).inserted {
            stored.append(tool)
        }
        self.init(
            items: Self.itemsWithFamilySeparators(stored.filter { !rawHidden.contains($0.rawValue) }),
            pool: stored.filter { rawHidden.contains($0.rawValue) }
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items.map(\.identifier), forKey: .items)
        // The pool's order is part of the layout, so it encodes in order,
        // never sorted.
        try container.encode(pool.map(\.rawValue), forKey: .pool)
    }
}

/// The palette's grab handle, the `⠇⠇` pattern after the close button (S4).
/// The pure values the toolbar view draws from, written here so the tests can
/// pin the layout and the reset target without spinning up AppKit.
public enum ToolbarGripperSpec {
    /// Dot columns the gripper draws — the owner's `⠇⠇` is two columns.
    public static let dotColumns = 2
    /// Dot rows the gripper draws — three stacked dots per column.
    public static let dotRows = 3
    /// Tooltip naming both actions: dragging the handle moves the bar, and
    /// right-clicking it resets the bar's position.
    public static let tooltip = "Drag to move · Right-click to reset position"
    /// The relative screen anchor a fresh install opens at — the reset target
    /// (S4): right-clicking the gripper clears the saved anchor, so the bar
    /// lands back here. This is exactly the anchor the top border keeps;
    /// `defaultAnchor(border:)` is the orientation/border-aware form (S12).
    public static let defaultAnchor = CGPoint(x: 0.5, y: 0.08)

    /// The default anchor for a docked border (S12): the bar's centre sits 8%
    /// in from the chosen edge of the screen frame and centred along it — the
    /// same top-centre spot a fresh install has always opened at, mirrored
    /// for the other three edges.
    public static func defaultAnchor(border: ToolbarBorder) -> CGPoint {
        switch border {
        case .top: CGPoint(x: 0.5, y: 0.08)
        case .bottom: CGPoint(x: 0.5, y: 0.92)
        case .left: CGPoint(x: 0.08, y: 0.5)
        case .right: CGPoint(x: 0.92, y: 0.5)
        }
    }

    /// The margin the palette keeps inside the visible frame when clamping.
    static let visibleFrameMargin: CGFloat = 8

    /// Frames a bar of `barSize` at the relative screen `anchor`: its centre
    /// sits at `anchor` over `screenFrame`, and the origin is clamped into
    /// `visibleFrame` with the margin above — the same centre-and-clamp math
    /// `ToolbarPanel` has always applied, written once so the tests and the
    /// panel agree on it.
    public static func barRect(
        barSize: CGSize,
        anchor: CGPoint,
        screenFrame: CGRect,
        visibleFrame: CGRect
    ) -> CGRect {
        let centre = CGPoint(
            x: screenFrame.minX + anchor.x * screenFrame.width,
            y: screenFrame.minY + anchor.y * screenFrame.height
        )
        let margin = visibleFrameMargin
        var origin = CGPoint(
            x: (centre.x - barSize.width / 2).rounded(),
            y: (centre.y - barSize.height / 2).rounded()
        )
        origin.x = min(max(origin.x, visibleFrame.minX + margin), visibleFrame.maxX - barSize.width - margin)
        origin.y = min(max(origin.y, visibleFrame.minY + margin), visibleFrame.maxY - barSize.height - margin)
        return CGRect(origin: origin, size: barSize)
    }

    /// The reset frame (S12): where the bar lands when the gripper's
    /// right-click clears the saved anchor, or when the Settings choice
    /// changes — docked at `border` for the given bar size. The orientation
    /// is honoured by the bar's own shape; the border alone picks the edge.
    public static func resetRect(
        barSize: CGSize,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        border: ToolbarBorder
    ) -> CGRect {
        barRect(
            barSize: barSize,
            anchor: defaultAnchor(border: border),
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )
    }
}

/// The drawing preferences that are not the pointer style: the armed frame,
/// where the overlay draws, where the palette opens, how long the laser lasts
/// and how the toolbar lays out and docks (T9/S12). Everything here used to
/// be a lone UserDefaults key; it now lives in the single versioned
/// `AppPreferences` blob. Decoding is lenient: an unknown raw value falls
/// back to the default of that field and never fails the document.
public struct GeneralPreferences: Codable, Equatable, Sendable {
    /// Whether the armed frame is drawn around displays before the first mark.
    public var showArmedFrame: Bool
    /// Which displays the overlay draws on.
    public var scope: OverlayScope
    /// Where the palette opens.
    public var palettePlacement: PalettePlacement
    /// How long a laser mark stays on screen.
    public var laserLifetime: LaserLifetime
    /// How the toolbar lays its items out (T9/S12). The default reproduces
    /// today's bar: a horizontal row.
    public var toolbarOrientation: ToolbarOrientation
    /// Which screen edge the toolbar rests at when it has not been dragged
    /// (T9/S12). The default is the top edge, where the bar opens today.
    public var toolbarBorder: ToolbarBorder
    /// Which tools the drawing toolbar shows and in what order (T8/S10). The
    /// default is the shipped bar: every tool, today's order, none hidden.
    public var toolbarTools: ToolbarToolLayout
    /// Whether marks and whiteboard pages persist until the machine restarts
    /// (T10/S11). The switch ships on: a stored drawing session is discarded
    /// at the next boot, never restored into a different boot. Turning it off
    /// stops storing and drops anything already stored, back to the ephemeral
    /// behaviour the app always had.
    public var persistsSession: Bool

    /// The general preferences a fresh install gets, matching what the app
    /// ships today.
    public static let standard = GeneralPreferences()

    /// Creates the general preferences; each unset parameter takes its
    /// shipped default.
    public init(
        showArmedFrame: Bool = true,
        scope: OverlayScope = .active,
        palettePlacement: PalettePlacement = .cursor,
        laserLifetime: LaserLifetime = .twoPointFive,
        toolbarOrientation: ToolbarOrientation = .horizontal,
        toolbarBorder: ToolbarBorder = .top,
        toolbarTools: ToolbarToolLayout = .standard,
        persistsSession: Bool = true
    ) {
        self.showArmedFrame = showArmedFrame
        self.scope = scope
        self.palettePlacement = palettePlacement
        self.laserLifetime = laserLifetime
        self.toolbarOrientation = toolbarOrientation
        self.toolbarBorder = toolbarBorder
        self.toolbarTools = toolbarTools
        self.persistsSession = persistsSession
    }

    private enum CodingKeys: String, CodingKey {
        case showArmedFrame, scope, palettePlacement, laserLifetime
        case toolbarOrientation, toolbarBorder, toolbarTools
        case persistsSession
    }

    /// Lenient decoding: a missing or unknown raw value falls back to the
    /// default of that field instead of failing the whole document.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showArmedFrame = (try? container.decode(Bool.self, forKey: .showArmedFrame)) ?? true
        let rawScope = try? container.decode(String.self, forKey: .scope)
        self.scope = rawScope.flatMap(OverlayScope.init(rawValue:)) ?? .active
        let rawPlacement = try? container.decode(String.self, forKey: .palettePlacement)
        self.palettePlacement = rawPlacement.flatMap(PalettePlacement.init(rawValue:)) ?? .cursor
        let rawLifetime = try? container.decode(Double.self, forKey: .laserLifetime)
        self.laserLifetime = rawLifetime.flatMap(LaserLifetime.init(rawValue:)) ?? .twoPointFive
        let rawOrientation = try? container.decode(String.self, forKey: .toolbarOrientation)
        self.toolbarOrientation = rawOrientation.flatMap(ToolbarOrientation.init(rawValue:)) ?? .horizontal
        let rawBorder = try? container.decode(String.self, forKey: .toolbarBorder)
        self.toolbarBorder = rawBorder.flatMap(ToolbarBorder.init(rawValue:)) ?? .top
        // T3/S4: the stored pair must never decode inconsistent — a border
        // the stored orientation cannot sit on re-docks on that orientation's
        // own default edge (horizontal → top, vertical → left); a valid pair
        // passes unchanged.
        self.toolbarBorder = self.toolbarBorder.validated(for: self.toolbarOrientation)
        // Lenient like every field: an unparseable layout (or a blob written
        // before it existed) keeps the shipped bar.
        self.toolbarTools = (try? container.decode(ToolbarToolLayout.self, forKey: .toolbarTools)) ?? .standard
        // A blob written before the switch existed keeps the shipped default:
        // persistence is on (S11).
        self.persistsSession = (try? container.decode(Bool.self, forKey: .persistsSession)) ?? true
    }
}
