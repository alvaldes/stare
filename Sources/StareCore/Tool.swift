import CoreGraphics
import Foundation

/// A drawing instrument. The raw value is stable because it is persisted in
/// user defaults and referenced by the MCP-facing model later on.
public enum Tool: String, CaseIterable, Identifiable, Sendable {
    case select
    case pen
    case highlighter
    case arrow
    case line
    case rectangle
    case ellipse
    case text
    case number
    case laser
    case eraser
    case blur
    case spotlight

    public var id: String { rawValue }

    /// Single-key shortcut while drawing. Matches the reference app's layout.
    public var shortcut: Character {
        switch self {
        case .select: "V"
        case .pen: "P"
        case .highlighter: "H"
        case .arrow: "A"
        case .line: "L"
        case .rectangle: "R"
        case .ellipse: "O"
        case .text: "T"
        case .number: "C"
        case .laser: "F"
        case .eraser: "E"
        case .blur: "B"
        case .spotlight: "D"
        }
    }

    public var displayName: String {
        switch self {
        case .select: "Cursor"
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .text: "Text"
        case .number: "Numbered step"
        case .laser: "Laser pointer"
        case .eraser: "Eraser"
        case .blur: "Blur"
        case .spotlight: "Spotlight"
        }
    }

    /// The cursor role this tool shows on the canvas at rest (T2/S2). Exhau-
    /// stive on purpose: a new tool fails to compile here until it declares
    /// its cursor — the mapping must never fall back to a silent default.
    public var cursor: ToolCursor {
        switch self {
        case .select: .editArrow
        case .pen: .penDot
        case .highlighter: .markerBeam
        case .arrow: .arrowCrosshair
        case .line: .lineCrosshair
        case .rectangle: .rectangleCrosshair
        case .ellipse: .ellipseCrosshair
        case .text: .textIBeam
        case .number: .numberRings
        case .laser: .laserSpark
        case .eraser: .eraserRing
        case .blur: .blurDots
        case .spotlight: .spotlightBeam
        }
    }

    public var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        case .number: "1.circle"
        case .laser: "sparkles"
        case .eraser: "eraser"
        case .blur: "camera.filters"
        case .spotlight: "sun.max"
        }
    }

    /// Geometry defined by the first and last point only: intermediate drag
    /// samples carry no meaning for these tools.
    public var usesEndpointsOnly: Bool {
        switch self {
        case .line, .arrow, .rectangle, .ellipse, .blur, .spotlight: true
        case .select, .pen, .highlighter, .text, .number, .laser, .eraser: false
        }
    }

    /// Tools that lay a mark with a single click instead of a drag.
    public var isClickTool: Bool {
        switch self {
        case .number, .text: true
        case .select, .pen, .highlighter, .arrow, .line, .rectangle, .ellipse, .laser, .eraser, .blur, .spotlight: false
        }
    }

    /// The palette order: tools of a kind sit together, so the bar reads as
    /// groups instead of a run of icons. The selection cursor leads the bar as
    /// its own family group, because editing what is already painted comes first.
    public static let toolbarGroups: [[Tool]] = [
        [.select],
        [.pen, .highlighter],
        [.line, .arrow, .rectangle, .ellipse],
        [.text, .number],
        [.blur, .spotlight, .laser],
        [.eraser],
    ]

    /// Marks that complete the moment they are placed.
    public var commitsImmediately: Bool { self == .number }

    /// Marks that fade away and must never be captured.
    public var isTransient: Bool { self == .laser }

    /// The eraser removes existing marks instead of creating one.
    public var isEraser: Bool { self == .eraser }

    /// The edit cursor transforms existing marks instead of creating one.
    public var isSelection: Bool { self == .select }

    /// Whether the tool can work in the capture editor, which draws over a
    /// static captured image with no live session: text has no field editor
    /// there and the laser fades with session time instead of annotating a
    /// still image. The select tool joins the editor's palette (S4 — it was
    /// never there and the owner missed it): over a still image it mints no
    /// mark at all (`DrawingSession.begin` refuses the edit cursor), so it
    /// serves as the palette's empty-handed pointer route, and its marking
    /// rides the same single armed-item state every other tool marks from.
    public var worksInCaptureEditor: Bool {
        switch self {
        case .text, .laser: false
        default: true
        }
    }

    /// The palette groups as the capture editor offers them: the main bar's
    /// groups minus the tools that cannot work over a still image. The select
    /// tool keeps its own leading family group, exactly as the outside bar
    /// draws it (S4).
    public static var captureEditorGroups: [[Tool]] {
        toolbarGroups.map { $0.filter(\.worksInCaptureEditor) }.filter { !$0.isEmpty }
    }

    /// Flattened list of what `captureEditorGroups` offers, for the shortcut
    /// router.
    public static var captureEditorTools: [Tool] {
        captureEditorGroups.flatMap { $0 }
    }
}

/// The cursor a tool shows while it rests on the canvas (T2/S2: "cada tool
/// debe tener un cursor personalizado dentro de lo posible"). The choice is
/// pure and pinneable here; the AppKit mapping — plus the small glyphs for the
/// roles no system cursor can claim — lives in the view (`OverlayView`).
/// System cursors only where one genuinely does the tool's job; the rest get
/// a minimal app-drawn glyph. The gap the "dentro de lo posible" spec admits,
/// on the record: every tool CAN be told apart, but the drawn glyphs are
/// schematic icons (a filled dot, a filled beam), not exact replicas of the
/// toolbar's SF Symbols — building richer art would need new assets, and
/// the spec prefers cursor-per-tool over shipped art the app does not have.
public enum ToolCursor: Equatable, CaseIterable, Sendable {
    /// The edit cursor: the system arrow, which users already read as
    /// "select and transform what is there".
    case editArrow
    /// The system I-beam: text places a field to type into.
    case textIBeam
    /// A circle inside a circle — two thin concentric rings — for the
    /// numbered badge (the owner's count shape).
    case numberRings
    /// The system crosshair, the drafting cursor. Line owns it by itself;
    /// arrow, rectangle and ellipse each own their own role — the table stays
    /// one role per tool — but all four are served the same system cursor BY
    /// IDENTITY instead of a drawn glyph (S7: "la elipse, el rect y arrow
    /// pasan a ser cursor cruz como la linea").
    case lineCrosshair
    case arrowCrosshair
    case rectangleCrosshair
    case ellipseCrosshair
    /// A drawn filled dot at the hotspot, for freehand ink (the owner's pen
    /// shape).
    case penDot
    /// A drawn filled beam — a tall block with flat edges — for the flat
    /// highlighter swab (the owner's highlighter shape; S7 turns it vertical).
    case markerBeam
    /// A drawn dot with rays, for the fading laser trail.
    case laserSpark
    /// A drawn empty circle, border only, no fill, for the eraser (the
    /// owner's eraser shape).
    case eraserRing
    /// A drawn grid of dots, for the frosted blur patch.
    case blurDots
    /// A drawn ring around a beam dot, for the dimming spotlight region.
    case spotlightBeam
}

public enum ToolShortcut {
    /// Resolves a pressed key to a tool, case-insensitively.
    public static func tool(for character: Character) -> Tool? {
        let upper = Character(character.uppercased())
        return Tool.allCases.first { $0.shortcut == upper }
    }
}
