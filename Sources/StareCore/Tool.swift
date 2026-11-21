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
        }
    }

    /// Geometry defined by the first and last point only: intermediate drag
    /// samples carry no meaning for these tools.
    public var usesEndpointsOnly: Bool {
        switch self {
        case .line, .arrow, .rectangle, .ellipse, .blur: true
        case .select, .pen, .highlighter, .text, .number, .laser, .eraser: false
        }
    }

    /// Tools that lay a mark with a single click instead of a drag.
    public var isClickTool: Bool {
        switch self {
        case .number, .text: true
        case .select, .pen, .highlighter, .arrow, .line, .rectangle, .ellipse, .laser, .eraser, .blur: false
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
        [.blur, .laser],
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
    /// static captured image with no live session: the edit cursor has no
    /// selection UI there, text has no field editor, and the laser fades with
    /// session time instead of annotating a still image.
    public var worksInCaptureEditor: Bool {
        switch self {
        case .select, .text, .laser: false
        default: true
        }
    }

    /// The palette groups as the capture editor may offer them: the main bar's
    /// groups minus the tools that cannot work over a still image.
    public static var captureEditorGroups: [[Tool]] {
        toolbarGroups.map { $0.filter(\.worksInCaptureEditor) }.filter { !$0.isEmpty }
    }

    /// Flattened list of what `captureEditorGroups` offers, for the shortcut
    /// router.
    public static var captureEditorTools: [Tool] {
        captureEditorGroups.flatMap { $0 }
    }
}

public enum ToolShortcut {
    /// Resolves a pressed key to a tool, case-insensitively.
    public static func tool(for character: Character) -> Tool? {
        let upper = Character(character.uppercased())
        return Tool.allCases.first { $0.shortcut == upper }
    }
}
