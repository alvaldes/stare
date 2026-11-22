import Foundation
import CoreGraphics

/// Where the drawing overlay draws: every display or only the one under the
/// pointer. Raw values are what the versioned preferences blob persists and
/// the strings today's picker has always used; decoding an unknown raw value
/// falls back to the default instead of failing the document.
public enum OverlayScope: String, Codable, CaseIterable, Sendable {
    /// Draw on every display — today's default.
    case all
    /// Draw only on the display the pointer is on when the session starts.
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
}

/// Which tools the drawing toolbar shows and in what order (T8/S10): the
/// stored form is a list of tool identifiers in display order — hidden tools
/// included, so a hidden tool never falls off the list and re-enters as if it
/// were new — plus the hidden set. Decoding is tolerant: unknown identifiers
/// are dropped, duplicates collapse to their first occurrence, and tools the
/// stored list never mentions (a tool added in a newer build, or anything the
/// document lost) are appended in the documented default order, so a new tool
/// is never invisible for existing users. The bar can never go empty: a
/// stored document that hides every tool loses the hidden set, and no write
/// path in the app can persist a layout with zero visible tools.
///
/// This is the drawing toolbar's layout only — the capture editor keeps its
/// own fixed palette over a still image, and a keyboard shortcut is not the
/// bar: a hidden tool stays shortcut-armed.
public struct ToolbarToolLayout: Codable, Equatable, Sendable {
    /// Tools in display order; hidden ones keep their stored place for when
    /// they come back.
    public var tools: [Tool]
    /// The hidden tools — drawn nowhere, still shortcut-armed.
    public var hidden: Set<Tool>

    /// The documented default order: exactly today's grouped bar flattened —
    /// the same sequence the four default `Tool.toolbarGroups` renders.
    public static let defaultOrder = Tool.toolbarGroups.flatMap { $0 }

    /// The layout a fresh install gets: every tool, today's order, none
    /// hidden.
    public static let standard = ToolbarToolLayout()

    /// Creates a layout. The stored order is normalized: duplicates collapse
    /// to their first occurrence, tools the list never mentions are appended
    /// in the documented default order, and a hidden set that leaves no
    /// visible tool is dropped so the bar can never present itself empty.
    public init(tools: [Tool] = ToolbarToolLayout.defaultOrder, hidden: Set<Tool> = []) {
        var seen = Set<Tool>(minimumCapacity: Tool.allCases.count)
        var ordered: [Tool] = []
        for tool in tools where seen.insert(tool).inserted {
            ordered.append(tool)
        }
        for tool in ToolbarToolLayout.defaultOrder where seen.insert(tool).inserted {
            ordered.append(tool)
        }
        self.tools = ordered
        self.hidden = ordered.contains(where: { !hidden.contains($0) }) ? hidden : []
    }

    /// The tools the bar draws, in order, with no gaps and nothing duplicated:
    /// the stored order with the hidden ones skipped.
    public var visibleTools: [Tool] {
        tools.filter { !hidden.contains($0) }
    }

    /// The tool section the toolbar renders: runs of consecutive visible
    /// tools that share a default family (the groups of
    /// `Tool.toolbarGroups`). The shipped layout reproduces today's groups
    /// exactly, and an arbitrary user order still gets a family divider only
    /// between neighbouring relatives.
    public var visibleGroups: [[Tool]] {
        // Every tool belongs to exactly one default family (pinned by
        // `ToolAndInkTests`); a nil comparison below only defends against a
        // future tool missing from `toolbarGroups`.
        var families: [Tool: Int] = [:]
        for (index, group) in Tool.toolbarGroups.enumerated() {
            for tool in group {
                families[tool] = index
            }
        }
        var groups: [[Tool]] = []
        for tool in visibleTools {
            let family = families[tool]
            if let last = groups.last, families[last[0]] == family {
                groups[groups.count - 1].append(tool)
            } else {
                groups.append([tool])
            }
        }
        return groups
    }

    /// Moves `tool` through the stored order by signed positions — one step
    /// swaps with the neighbour — clamped at both ends; the hidden keep their
    /// place and reorder too. A tool that is not stored comes back unchanged.
    public func moving(_ tool: Tool, by positions: Int) -> ToolbarToolLayout {
        guard let index = tools.firstIndex(of: tool) else { return self }
        let target = min(max(index + positions, 0), tools.count - 1)
        guard target != index else { return self }
        var copy = self
        copy.tools.remove(at: index)
        copy.tools.insert(tool, at: target)
        return copy
    }

    /// Shows or hides `tool`. Hiding the last visible tool is refused — the
    /// bar can never go empty — and returns the layout unchanged.
    public func setting(_ tool: Tool, isVisible: Bool) -> ToolbarToolLayout {
        if isVisible {
            var copy = self
            copy.hidden.remove(tool)
            return copy
        }
        let visibleCount = visibleTools.count
        guard visibleTools.contains(tool) ? visibleCount > 1 : visibleCount > 0 else { return self }
        var copy = self
        copy.hidden.insert(tool)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case tools, hidden
    }

    /// Lenient decoding: identifiers are tool raw values, unknown ones drop,
    /// duplicates collapse, missing tools append in the documented default
    /// order, and an empty stored list is the shipped bar instead of an empty
    /// one. The layout's own `init` applies every rule, so decoding only adds
    /// the two fallbacks for missing or unparseable fields.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawTools = (try? container.decode([String].self, forKey: .tools)) ?? []
        let rawHidden = (try? container.decode([String].self, forKey: .hidden)) ?? []
        guard !rawTools.isEmpty else {
            // An empty stored list — like a field the blob never had — is the
            // shipped bar, not an empty one.
            self = .standard
            return
        }
        self.init(tools: rawTools.compactMap(Tool.init(rawValue:)), hidden: Set(rawHidden.compactMap(Tool.init(rawValue:))))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tools.map(\.rawValue), forKey: .tools)
        // Sorted so the same layout always writes the same bytes.
        try container.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
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

    /// The general preferences a fresh install gets, matching what the app
    /// ships today.
    public static let standard = GeneralPreferences()

    /// Creates the general preferences; each unset parameter takes its
    /// shipped default.
    public init(
        showArmedFrame: Bool = true,
        scope: OverlayScope = .all,
        palettePlacement: PalettePlacement = .cursor,
        laserLifetime: LaserLifetime = .twoPointFive,
        toolbarOrientation: ToolbarOrientation = .horizontal,
        toolbarBorder: ToolbarBorder = .top,
        toolbarTools: ToolbarToolLayout = .standard
    ) {
        self.showArmedFrame = showArmedFrame
        self.scope = scope
        self.palettePlacement = palettePlacement
        self.laserLifetime = laserLifetime
        self.toolbarOrientation = toolbarOrientation
        self.toolbarBorder = toolbarBorder
        self.toolbarTools = toolbarTools
    }

    private enum CodingKeys: String, CodingKey {
        case showArmedFrame, scope, palettePlacement, laserLifetime
        case toolbarOrientation, toolbarBorder, toolbarTools
    }

    /// Lenient decoding: a missing or unknown raw value falls back to the
    /// default of that field instead of failing the whole document.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showArmedFrame = (try? container.decode(Bool.self, forKey: .showArmedFrame)) ?? true
        let rawScope = try? container.decode(String.self, forKey: .scope)
        self.scope = rawScope.flatMap(OverlayScope.init(rawValue:)) ?? .all
        let rawPlacement = try? container.decode(String.self, forKey: .palettePlacement)
        self.palettePlacement = rawPlacement.flatMap(PalettePlacement.init(rawValue:)) ?? .cursor
        let rawLifetime = try? container.decode(Double.self, forKey: .laserLifetime)
        self.laserLifetime = rawLifetime.flatMap(LaserLifetime.init(rawValue:)) ?? .twoPointFive
        let rawOrientation = try? container.decode(String.self, forKey: .toolbarOrientation)
        self.toolbarOrientation = rawOrientation.flatMap(ToolbarOrientation.init(rawValue:)) ?? .horizontal
        let rawBorder = try? container.decode(String.self, forKey: .toolbarBorder)
        self.toolbarBorder = rawBorder.flatMap(ToolbarBorder.init(rawValue:)) ?? .top
        // Lenient like every field: an unparseable layout (or a blob written
        // before it existed) keeps the shipped bar.
        self.toolbarTools = (try? container.decode(ToolbarToolLayout.self, forKey: .toolbarTools)) ?? .standard
    }
}
