import CoreGraphics
import Foundation

/// A drawing instrument. The raw value is stable because it is persisted in
/// user defaults and referenced by the MCP-facing model later on.
public enum Tool: String, CaseIterable, Identifiable, Sendable {
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
        case .pen, .highlighter, .text, .number, .laser, .eraser: false
        }
    }

    /// Tools that lay a mark with a single click instead of a drag.
    public var isClickTool: Bool {
        switch self {
        case .number, .text: true
        case .pen, .highlighter, .arrow, .line, .rectangle, .ellipse, .laser, .eraser, .blur: false
        }
    }

    /// Marks that complete the moment they are placed.
    public var commitsImmediately: Bool { self == .number }

    /// Marks that fade away and must never be captured.
    public var isTransient: Bool { self == .laser }

    /// The eraser removes existing marks instead of creating one.
    public var isEraser: Bool { self == .eraser }
}

public enum ToolShortcut {
    /// Resolves a pressed key to a tool, case-insensitively.
    public static func tool(for character: Character) -> Tool? {
        let upper = Character(character.uppercased())
        return Tool.allCases.first { $0.shortcut == upper }
    }
}
