import Foundation

/// One place that decides what a drawing key press means, so the overlay and the
/// capture editor can never drift apart.
public enum ShortcutResolution: Equatable {
    case tool(Tool)
    case ink(Ink)
    case none
}

/// Resolves pressed keys through a `ToolShortcutMap`, so editing a tool's
/// shortcut in Settings changes routing everywhere. The invariant it holds:
/// a character the map does not claim keeps today's behaviour — digits 1–8
/// select inks and every other unclaimed key resolves to nothing.
public struct ShortcutRouter {
    private let shortcuts: ToolShortcutMap

    /// Creates a router over `shortcuts`; defaults to the shipped
    /// `ToolShortcutMap.standard`, which reproduces today's routing.
    public init(shortcuts: ToolShortcutMap = .standard) {
        self.shortcuts = shortcuts
    }

    /// Resolves a pressed key to a tool or an ink. With `allowedTools`, a tool
    /// outside the offered set resolves to nothing — a surface that hides a
    /// tool must not arm it through its shortcut either.
    public func resolve(_ character: Character, allowedTools: [Tool]) -> ShortcutResolution {
        if let tool = shortcuts.tool(for: character), allowedTools.contains(tool) {
            return .tool(tool)
        }
        if let digit = character.wholeNumberValue, let ink = Ink.ink(forNumber: digit) {
            return .ink(ink)
        }
        return .none
    }

    public func resolve(_ character: Character) -> ShortcutResolution {
        resolve(character, allowedTools: Tool.allCases)
    }

    /// Resolves against the shipped defaults; kept as a static entry point so
    /// existing call sites keep compiling unchanged.
    public static func resolve(_ character: Character, allowedTools: [Tool]) -> ShortcutResolution {
        ShortcutRouter().resolve(character, allowedTools: allowedTools)
    }

    public static func resolve(_ character: Character) -> ShortcutResolution {
        resolve(character, allowedTools: Tool.allCases)
    }
}
