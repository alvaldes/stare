import Foundation

/// Modifier flags of a global hotkey. The raw values are plain single bits
/// chosen for stable persistence; the Carbon `EventModifiers` flag values are
/// derived in `carbonFlags`, so this file needs no Carbon import.
public struct HotkeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let command = HotkeyModifiers(rawValue: 1 << 0)
    public static let option = HotkeyModifiers(rawValue: 1 << 1)
    public static let control = HotkeyModifiers(rawValue: 1 << 2)
    public static let shift = HotkeyModifiers(rawValue: 1 << 3)

    /// Carbon event-flag mask for `RegisterEventHotKey`, built from the plain
    /// `EventModifiers` constants: `cmdKey` 4096, `optionKey` 2048,
    /// `controlKey` 16384, `shiftKey` 512.
    public var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= 4096 } // cmdKey
        if contains(.option) { flags |= 2048 } // optionKey
        if contains(.control) { flags |= 16384 } // controlKey
        if contains(.shift) { flags |= 512 } // shiftKey
        return flags
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A physical key on the ANSI layout. The key codes are fixed platform data
/// (the `kVK_ANSI_*` constants from `Events.h`) and never change across macOS
/// releases, so they are written as literals here instead of imported.
public enum VirtualKey: String, Codable, CaseIterable, Sendable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z
    case zero = "0"
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"

    /// macOS virtual key code for the ANSI layout (`kVK_ANSI_*`), fixed
    /// platform data: a = 0, s = 1, d = 2, …, m = 46; the digits are not
    /// sequential (1 = 18 … 9 = 25, 0 = 29).
    public var keyCode: UInt32 {
        switch self {
        case .a: 0 // kVK_ANSI_A
        case .s: 1 // kVK_ANSI_S
        case .d: 2 // kVK_ANSI_D
        case .f: 3 // kVK_ANSI_F
        case .h: 4 // kVK_ANSI_H
        case .g: 5 // kVK_ANSI_G
        case .z: 6 // kVK_ANSI_Z
        case .x: 7 // kVK_ANSI_X
        case .c: 8 // kVK_ANSI_C
        case .v: 9 // kVK_ANSI_V
        case .b: 11 // kVK_ANSI_B
        case .q: 12 // kVK_ANSI_Q
        case .w: 13 // kVK_ANSI_W
        case .e: 14 // kVK_ANSI_E
        case .r: 15 // kVK_ANSI_R
        case .y: 16 // kVK_ANSI_Y
        case .t: 17 // kVK_ANSI_T
        case .one: 18 // kVK_ANSI_1
        case .two: 19 // kVK_ANSI_2
        case .three: 20 // kVK_ANSI_3
        case .four: 21 // kVK_ANSI_4
        case .six: 22 // kVK_ANSI_6
        case .five: 23 // kVK_ANSI_5
        case .nine: 25 // kVK_ANSI_9
        case .seven: 26 // kVK_ANSI_7
        case .eight: 28 // kVK_ANSI_8
        case .zero: 29 // kVK_ANSI_0
        case .o: 31 // kVK_ANSI_O
        case .u: 32 // kVK_ANSI_U
        case .i: 34 // kVK_ANSI_I
        case .p: 35 // kVK_ANSI_P
        case .l: 37 // kVK_ANSI_L
        case .j: 38 // kVK_ANSI_J
        case .k: 40 // kVK_ANSI_K
        case .n: 45 // kVK_ANSI_N
        case .m: 46 // kVK_ANSI_M
        }
    }

    /// The character the key produces on the ANSI layout: a lowercase letter
    /// or a digit. Callers that display the key uppercase it themselves.
    public var character: Character {
        Character(rawValue)
    }

    /// Matches a typed character to its key, case-insensitively, or nil for
    /// characters no covered key produces.
    public init?(character: Character) {
        let lower = Character(character.lowercased())
        self.init(rawValue: String(lower))
    }
}

/// One global hotkey: a physical key plus the modifiers that must be held.
/// The invariant it holds: `isValid` is true only with at least one modifier,
/// because Carbon refuses to register a modifier-less hotkey.
public struct HotkeyBinding: Codable, Hashable, Sendable {
    public var key: VirtualKey
    public var modifiers: HotkeyModifiers

    public init(key: VirtualKey, modifiers: HotkeyModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// A binding is usable only with at least one modifier: Carbon refuses a
    /// modifier-less hotkey registration.
    public var isValid: Bool {
        !modifiers.isEmpty
    }
}

/// A global hotkey the app registers. The defaults reproduce today's
/// bindings exactly (S7): ⌥⇧A draw, ⌥⇧M pointer, ⌥⇧P pin, ⌥⇧W whiteboard.
public enum HotkeyAction: String, Codable, CaseIterable, Sendable {
    case drawOverlay
    case pointerHighlight
    case pin
    case whiteboard

    /// Human-readable name shown in Settings.
    public var title: String {
        switch self {
        case .drawOverlay: "Draw Over Screen"
        case .pointerHighlight: "Pointer Highlight"
        case .pin: "Pin"
        case .whiteboard: "Whiteboard"
        }
    }

    /// The binding the app ships with, identical to today's hard-coded
    /// ⌥⇧A / ⌥⇧M / ⌥⇧P / ⌥⇧W.
    public var defaultBinding: HotkeyBinding {
        switch self {
        case .drawOverlay: HotkeyBinding(key: .a, modifiers: [.option, .shift])
        case .pointerHighlight: HotkeyBinding(key: .m, modifiers: [.option, .shift])
        case .pin: HotkeyBinding(key: .p, modifiers: [.option, .shift])
        case .whiteboard: HotkeyBinding(key: .w, modifiers: [.option, .shift])
        }
    }
}

/// Error of a refused hotkey assignment.
public enum HotkeyAssignmentError: Error, Equatable, Sendable {
    /// The binding carries no modifier, which Carbon cannot register.
    case invalidBinding
    /// The binding is already used by the carried action.
    case conflict(HotkeyAction)
}

/// The persisted map of every `HotkeyAction` to its binding. The invariant it
/// holds: the map is complete and conflict-free — every action has a binding,
/// no two actions share one — after decoding as well as after assignment.
public struct HotkeyBindings: Codable, Equatable, Sendable {
    private var bindings: [HotkeyAction: HotkeyBinding]

    public init() {
        self = .standard
    }

    private init(bindings: [HotkeyAction: HotkeyBinding]) {
        self.bindings = bindings
    }

    /// Every action bound to its `defaultBinding`, reproducing today's
    /// ⌥⇧A / ⌥⇧M / ⌥⇧P / ⌥⇧W.
    public static let standard = HotkeyBindings(bindings: Dictionary(
        uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, $0.defaultBinding) }
    ))

    /// The binding of `action`; always present.
    public subscript(action: HotkeyAction) -> HotkeyBinding {
        bindings[action, default: action.defaultBinding]
    }

    /// The action already holding `binding`, if any.
    public func conflictingAction(for binding: HotkeyBinding) -> HotkeyAction? {
        HotkeyAction.allCases.first { bindings[$0, default: $0.defaultBinding] == binding }
    }

    /// Sets `binding` for `action`, or refuses it and leaves the previous
    /// value in place when the binding is modifier-less or already used by
    /// another action.
    @discardableResult
    public mutating func assigning(_ binding: HotkeyBinding, to action: HotkeyAction) -> Result<Void, HotkeyAssignmentError> {
        guard binding.isValid else { return .failure(.invalidBinding) }
        if let other = conflictingAction(for: binding), other != action {
            return .failure(.conflict(other))
        }
        bindings[action] = binding
        return .success(())
    }

    private enum ActionKey: String, CodingKey {
        case drawOverlay, pointerHighlight, pin, whiteboard
    }

    /// Encodes each action's binding at the top level, the shape
    /// `init(from:)` reads.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ActionKey.self)
        for action in HotkeyAction.allCases {
            guard let key = ActionKey(rawValue: action.rawValue) else { continue }
            try container.encode(self[action], forKey: key)
        }
    }

    /// Lenient decoding: a missing or corrupt entry, or one carrying an
    /// invalid binding, falls back to the action's default; a duplicate entry
    /// whose binding is already taken yields to the action holding it and
    /// falls back to its own default. The result is always complete and
    /// conflict-free.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ActionKey.self)
        var loaded: [HotkeyAction: HotkeyBinding] = [:]
        for action in HotkeyAction.allCases {
            guard let key = ActionKey(rawValue: action.rawValue),
                  let binding = try? container.decode(HotkeyBinding.self, forKey: key),
                  binding.isValid
            else { continue }
            loaded[action] = binding
        }
        self = HotkeyBindings(resolving: loaded)
    }

    /// Restores completeness and conflict-freedom from leniently loaded
    /// entries: defaults first (they are pairwise distinct), then each loaded
    /// binding that is valid, not another action's default, and not already
    /// taken — a conflicting loaded entry keeps the default instead.
    private init(resolving loaded: [HotkeyAction: HotkeyBinding]) {
        var resolved: [HotkeyAction: HotkeyBinding] = [:]
        var taken = Set<HotkeyBinding>()
        for action in HotkeyAction.allCases {
            resolved[action] = action.defaultBinding
            taken.insert(action.defaultBinding)
        }
        for action in HotkeyAction.allCases {
            guard let binding = loaded[action], binding != action.defaultBinding, !taken.contains(binding) else {
                continue
            }
            resolved[action] = binding
            taken.insert(binding)
        }
        bindings = resolved
    }
}
