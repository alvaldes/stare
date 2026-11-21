import Foundation

/// One place that decides what a drawing key press means, so the overlay and the
/// capture editor can never drift apart.
public enum ShortcutResolution: Equatable {
    case tool(Tool)
    case ink(Ink)
    case none
}

public enum ShortcutRouter {
    /// Resolves a pressed key to a tool or an ink. With `allowedTools`, a tool
    /// outside the offered set resolves to nothing — a surface that hides a
    /// tool must not arm it through its shortcut either.
    public static func resolve(_ character: Character, allowedTools: [Tool]) -> ShortcutResolution {
        if let tool = ToolShortcut.tool(for: character), allowedTools.contains(tool) {
            return .tool(tool)
        }
        if let digit = character.wholeNumberValue, let ink = Ink.ink(forNumber: digit) {
            return .ink(ink)
        }
        return .none
    }

    public static func resolve(_ character: Character) -> ShortcutResolution {
        resolve(character, allowedTools: Tool.allCases)
    }
}
