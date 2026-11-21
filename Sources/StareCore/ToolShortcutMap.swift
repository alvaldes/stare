import Foundation

/// Error of a refused tool-shortcut assignment.
public enum ToolShortcutAssignmentError: Error, Equatable, Sendable {
    /// The character is neither a letter nor a digit.
    case unsupportedCharacter
    /// The character is already bound to the carried tool.
    case conflict(Tool)
}

/// The persisted map of every routable `Tool` to its shortcut key. The
/// invariant it holds: the map is a bijection between the routable tools and
/// their keys — every tool has exactly one key and no key maps to two tools —
/// after decoding as well as after assignment.
public struct ToolShortcutMap: Codable, Equatable, Sendable {
    private var map: [Tool: Character]

    public init() {
        self = .standard
    }

    private init(map: [Tool: Character]) {
        self.map = map
    }

    /// One key per tool, derived from today's `Tool.shortcut` values, so the
    /// defaults reproduce the shipped shortcuts exactly.
    public static let standard = ToolShortcutMap(map: Dictionary(
        uniqueKeysWithValues: Tool.allCases.map { ($0, $0.shortcut) }
    ))

    /// The shortcut of `tool`; always present.
    public subscript(tool: Tool) -> Character {
        map[tool, default: tool.shortcut]
    }

    /// The tool bound to `character` (case-insensitive), or nil when no tool
    /// claims it.
    public func tool(for character: Character) -> Tool? {
        let key = Self.normalized(character)
        return Tool.allCases.first { Self.normalized(map[$0, default: $0.shortcut]) == key }
    }

    /// The tool already holding `character` (case-insensitive), if any.
    public func conflictingTool(for character: Character) -> Tool? {
        tool(for: character)
    }

    /// Sets `character` as `tool`'s shortcut, or refuses it and leaves the
    /// previous mapping in place when the character is already taken by
    /// another tool or is unsupported (letters and digits only).
    @discardableResult
    public mutating func assigning(_ character: Character, to tool: Tool) -> Result<Void, ToolShortcutAssignmentError> {
        guard Self.isSupported(character) else { return .failure(.unsupportedCharacter) }
        let key = Self.normalized(character)
        if let other = conflictingTool(for: key), other != tool {
            return .failure(.conflict(other))
        }
        map[tool] = key
        return .success(())
    }

    /// Only ASCII letters and digits can be shortcuts: the key handler and
    /// the ink digit selectors share the keyboard, and anything else would be
    /// untypable or ambiguous.
    fileprivate static func isSupported(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        if character.isLetter { return true }
        if let number = character.wholeNumberValue { return number >= 0 && number <= 9 }
        return false
    }

    /// Shortcut keys are stored uppercase so they match today's
    /// `Tool.shortcut` values; digits stay digits.
    fileprivate static func normalized(_ character: Character) -> Character {
        Character(character.uppercased())
    }

    private enum ToolKey: String, CodingKey {
        case select, pen, highlighter, arrow, line, rectangle, ellipse
        case text, number, laser, eraser, blur
    }

    /// Encodes each tool's shortcut as a single-character string; decoding is
    /// lenient (see `init(from:)`).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ToolKey.self)
        for tool in Tool.allCases {
            guard let key = ToolKey(rawValue: tool.rawValue) else { continue }
            try container.encode(String(subscripted(tool)), forKey: key)
        }
    }

    private func subscripted(_ tool: Tool) -> Character {
        map[tool, default: tool.shortcut]
    }

    /// Lenient decoding: a missing or corrupt entry, or one carrying an
    /// unsupported character, falls back to the tool's `Tool.shortcut`; a
    /// duplicate entry whose character is already taken yields to the tool
    /// holding it and falls back to its own default. The result is always a
    /// complete, conflict-free bijection.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ToolKey.self)
        var loaded: [Tool: Character] = [:]
        for tool in Tool.allCases {
            guard let key = ToolKey(rawValue: tool.rawValue),
                  let string = try? container.decode(String.self, forKey: key),
                  string.count == 1,
                  let character = string.first,
                  Self.isSupported(character)
            else { continue }
            loaded[tool] = Self.normalized(character)
        }
        self = ToolShortcutMap(resolving: loaded)
    }

    /// Restores the bijection from leniently loaded entries: defaults first
    /// (they are pairwise distinct), then each loaded character that is not
    /// another tool's default and not already taken — a conflicting loaded
    /// entry keeps the default instead.
    private init(resolving loaded: [Tool: Character]) {
        var resolved: [Tool: Character] = [:]
        var taken = Set<Character>()
        for tool in Tool.allCases {
            resolved[tool] = tool.shortcut
            taken.insert(tool.shortcut)
        }
        for tool in Tool.allCases {
            guard let character = loaded[tool], character != tool.shortcut, !taken.contains(character) else {
                continue
            }
            resolved[tool] = character
            taken.insert(character)
        }
        map = resolved
    }
}
