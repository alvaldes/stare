import Foundation

/// Single persisted owner of app-wide preferences. Everything is stored as one
/// versioned JSON blob, so new fields join the same document instead of
/// gaining their own UserDefaults keys. Loading falls back to `standard` plus
/// legacy migration and never traps; saving writes only the versioned blob and
/// never touches legacy keys.
public struct AppPreferences: Codable, Equatable, Sendable {
    /// Versioned storage key holding the JSON blob.
    public static let storageKey = "preferences.v1"

    /// Style of the pointer highlight (⌥⇧M).
    public var pointer: PointerStyle

    /// Per-tool keyboard shortcuts; the router reads this map.
    public var toolShortcuts: ToolShortcutMap

    /// The four global hotkeys (⌥⇧A/M/P/W) as data.
    public var hotkeys: HotkeyBindings

    /// Capture format, destination and file name prefix.
    public var capture: CapturePreference

    /// What a whiteboard opens with: background and page count.
    public var whiteboard: WhiteboardDefaults

    /// Update check schedule and the last successful check.
    public var updates: UpdateSchedulePreference

    /// The preferences a fresh install gets, matching the look the app ships
    /// today.
    public static let standard = AppPreferences()

    /// Creates preferences with the given pointer style, tool shortcuts,
    /// hotkeys, capture, whiteboard and update settings; each unset parameter
    /// takes its shipped default.
    public init(
        pointer: PointerStyle = .standard,
        toolShortcuts: ToolShortcutMap = .standard,
        hotkeys: HotkeyBindings = .standard,
        capture: CapturePreference = .standard,
        whiteboard: WhiteboardDefaults = .standard,
        updates: UpdateSchedulePreference = .standard
    ) {
        self.pointer = pointer
        self.toolShortcuts = toolShortcuts
        self.hotkeys = hotkeys
        self.capture = capture
        self.whiteboard = whiteboard
        self.updates = updates
    }

    /// Loads preferences from `store`. A corrupt or absent blob falls back to
    /// `standard`, plus migration from the legacy pointer keys when they are
    /// present. Legacy keys are only read, never deleted or rewritten.
    public init(store: PreferenceStore) {
        self = AppPreferences.load(from: store)
    }

    private enum CodingKeys: String, CodingKey {
        case pointer, toolShortcuts, hotkeys, capture, whiteboard, updates
    }

    /// Lenient decoding: a missing or undecodable field falls back to its
    /// `standard` instead of failing the whole document, and blobs written
    /// before the shortcut or capture/whiteboard/update fields existed load
    /// complete defaults for them.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pointer = (try? container.decode(PointerStyle.self, forKey: .pointer)) ?? .standard
        self.toolShortcuts = (try? container.decode(ToolShortcutMap.self, forKey: .toolShortcuts)) ?? .standard
        self.hotkeys = (try? container.decode(HotkeyBindings.self, forKey: .hotkeys)) ?? .standard
        self.capture = (try? container.decode(CapturePreference.self, forKey: .capture)) ?? .standard
        self.whiteboard = (try? container.decode(WhiteboardDefaults.self, forKey: .whiteboard)) ?? .standard
        self.updates = (try? container.decode(UpdateSchedulePreference.self, forKey: .updates)) ?? .standard
    }

    /// Encodes the preferences as JSON under the versioned key. Legacy keys
    /// stay untouched; they stop being read once the blob exists.
    public func save(to store: PreferenceStore) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        store.set(data, forKey: Self.storageKey)
    }

    private static func load(from store: PreferenceStore) -> AppPreferences {
        if let data = store.data(forKey: storageKey) {
            if let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) {
                return decoded
            }
            // Corrupt blob: fall through to legacy migration or `standard`;
            // the next save overwrites it with a valid document.
        }
        if let pointer = PreferencesMigration.migratedPointerStyle(in: store) {
            return AppPreferences(pointer: pointer)
        }
        return .standard
    }
}

/// Persisted update-check settings (T3/S6): how often to check and when one
/// last succeeded. The schedule's raw value is what the blob persists; the
/// timestamp is only ever written by a successful check, never guessed.
public struct UpdateSchedulePreference: Codable, Equatable, Sendable {
    /// How often to check for updates. Default `.weekly` — a sensible default
    /// for a feature that did not exist before; the Settings pane exposes the
    /// picker.
    public var schedule: UpdateCheckSchedule

    /// When the last successful check ran; nil until one does.
    public var lastCheck: Date?

    /// The update settings a fresh install gets.
    public static let standard = UpdateSchedulePreference()

    /// Creates the update settings.
    public init(schedule: UpdateCheckSchedule = .weekly, lastCheck: Date? = nil) {
        self.schedule = schedule
        self.lastCheck = lastCheck
    }

    private enum CodingKeys: String, CodingKey {
        case schedule, lastCheck
    }

    /// Lenient decoding: a missing or unknown schedule falls back to the
    /// standard one, and a missing timestamp stays nil.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawSchedule = try? container.decode(String.self, forKey: .schedule)
        self.schedule = rawSchedule.flatMap(UpdateCheckSchedule.init(rawValue:)) ?? UpdateSchedulePreference.standard.schedule
        self.lastCheck = try? container.decodeIfPresent(Date.self, forKey: .lastCheck)
    }
}

/// Load-time migration from the legacy per-key pointer preferences
/// (`pointerSize.v3`, `pointerShape`, `pointerGlow`, `pointerFadeWhenIdle`)
/// into a `PointerStyle`. The legacy keys are never deleted or rewritten; the
/// versioned blob takes over on the next save.
public enum PreferencesMigration {
    /// Legacy key holding the highlight diameter in points.
    public static let legacySizeKey = "pointerSize.v3"
    /// Legacy key holding `"circle"` or `"squircle"`.
    public static let legacyShapeKey = "pointerShape"
    /// Legacy key holding whether the glow was on.
    public static let legacyGlowKey = "pointerGlow"
    /// Legacy key holding whether the highlight faded when idle.
    public static let legacyFadeKey = "pointerFadeWhenIdle"

    /// Builds the pointer style the legacy keys describe, or nil when none of
    /// them is stored. A missing legacy key keeps today's default; the shape
    /// maps like today's renderer — `"squircle"` stays a squircle and any
    /// other value is a ring.
    public static func migratedPointerStyle(in store: PreferenceStore) -> PointerStyle? {
        let hasSize = store.object(forKey: legacySizeKey) != nil
        let hasShape = store.object(forKey: legacyShapeKey) != nil
        let hasGlow = store.object(forKey: legacyGlowKey) != nil
        let hasFade = store.object(forKey: legacyFadeKey) != nil
        guard hasSize || hasShape || hasGlow || hasFade else { return nil }

        var style = PointerStyle.standard
        if hasSize {
            style.size = store.double(forKey: legacySizeKey, default: PointerStyle.standard.size)
        }
        if hasShape {
            style.preset = store.string(forKey: legacyShapeKey) == "squircle" ? .squircle : .ring
        }
        if hasGlow {
            style.glowIntensity = store.bool(forKey: legacyGlowKey, default: true) ? 1 : 0
        }
        if hasFade {
            style.fadeWhenIdle = store.bool(forKey: legacyFadeKey, default: true)
        }
        return style
    }
}
