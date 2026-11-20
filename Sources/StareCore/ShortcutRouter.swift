import Foundation

/// One place that decides what a drawing key press means, so the overlay and the
/// capture editor can never drift apart.
public enum ShortcutResolution: Equatable {
    case tool(Tool)
    case ink(Ink)
    case none
}

public enum ShortcutRouter {
    public static func resolve(_ character: Character) -> ShortcutResolution {
        if let tool = ToolShortcut.tool(for: character) {
            return .tool(tool)
        }
        if let digit = character.wholeNumberValue, let ink = Ink.ink(forNumber: digit) {
            return .ink(ink)
        }
        return .none
    }
}
