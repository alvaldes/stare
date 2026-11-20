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
    case number

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
        case .number: "C"
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
        case .number: "Numbered step"
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
        case .number: "1.circle"
        }
    }

    /// Geometry defined by the first and last point only: intermediate drag
    /// samples carry no meaning for these tools.
    public var usesEndpointsOnly: Bool {
        switch self {
        case .line, .arrow, .rectangle, .ellipse: true
        case .pen, .highlighter, .number: false
        }
    }

    /// Tools that complete on a single click instead of a drag.
    public var isClickTool: Bool { self == .number }
}

public enum ToolShortcut {
    /// Resolves a pressed key to a tool, case-insensitively.
    public static func tool(for character: Character) -> Tool? {
        let upper = Character(character.uppercased())
        return Tool.allCases.first { $0.shortcut == upper }
    }
}
