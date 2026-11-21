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

    /// The armed frame, overlay scope, palette placement and laser lifetime
    /// (T6 slice 1/S4). These used to be lone UserDefaults keys; they now
    /// ride in the same versioned blob as everything else.
    public var general: GeneralPreferences

    /// Per-tool keyboard shortcuts; the router reads this map.
    public var toolShortcuts: ToolShortcutMap

    /// The four global hotkeys (⌥⇧A/M/P/W) as data.
    public var hotkeys: HotkeyBindings

    /// The tool drawing starts with (T8/S6): what the palette arms on open.
    public var tool: Tool

    /// The ink drawing starts with (T8/S6): what the palette's swatch shows
    /// as active on open.
    public var ink: Ink

    /// Capture format, destination and file name prefix.
    public var capture: CapturePreference

    /// What a whiteboard opens with: background and page count.
    public var whiteboard: WhiteboardDefaults

    /// Update check schedule and the last successful check.
    public var updates: UpdateSchedulePreference

    /// Whether the first-run guide (T5/S3) has been shown and dismissed. Once
    /// true the guide never reappears on its own; the menu bar's "Setup
    /// Guide…" item can still open it by hand without touching this flag.
    public var hasCompletedOnboarding: Bool

    /// The preferences a fresh install gets, matching the look the app ships
    /// today.
    public static let standard = AppPreferences()

    /// Creates preferences with the given pointer style, general settings,
    /// tool shortcuts, hotkeys, capture, whiteboard and update settings; each
    /// unset parameter takes its shipped default.
    public init(
        pointer: PointerStyle = .standard,
        general: GeneralPreferences = .standard,
        toolShortcuts: ToolShortcutMap = .standard,
        hotkeys: HotkeyBindings = .standard,
        tool: Tool = .pen,
        ink: Ink = .red,
        capture: CapturePreference = .standard,
        whiteboard: WhiteboardDefaults = .standard,
        updates: UpdateSchedulePreference = .standard,
        hasCompletedOnboarding: Bool = false
    ) {
        self.pointer = pointer
        self.general = general
        self.toolShortcuts = toolShortcuts
        self.hotkeys = hotkeys
        self.tool = tool
        self.ink = ink
        self.capture = capture
        self.whiteboard = whiteboard
        self.updates = updates
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    /// Loads preferences from `store`. A corrupt or absent blob falls back to
    /// `standard`, plus migration from the legacy pointer keys and the legacy
    /// general keys (`showArmedFrame`, `overlayScope`, `palettePlacement`,
    /// `laserLifetime`) when they are present. Legacy keys are only read,
    /// never deleted or rewritten.
    public init(store: PreferenceStore) {
        self = AppPreferences.load(from: store)
    }

    private enum CodingKeys: String, CodingKey {
        case pointer, general, toolShortcuts, hotkeys, tool, ink, capture, whiteboard, updates, hasCompletedOnboarding
    }

    /// Lenient decoding: a missing or undecodable field falls back to its
    /// `standard` instead of failing the whole document, and blobs written
    /// before the shortcut, capture/whiteboard/update or general fields
    /// existed load complete defaults for them.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pointer = (try? container.decode(PointerStyle.self, forKey: .pointer)) ?? .standard
        self.general = (try? container.decode(GeneralPreferences.self, forKey: .general)) ?? .standard
        self.toolShortcuts = (try? container.decode(ToolShortcutMap.self, forKey: .toolShortcuts)) ?? .standard
        self.hotkeys = (try? container.decode(HotkeyBindings.self, forKey: .hotkeys)) ?? .standard
        // Tool and ink persist as their raw values: the enums are plain data
        // types, not Codable themselves, and an unknown raw value from a
        // foreign document falls back to the shipped defaults instead of
        // failing the whole blob.
        self.tool = (try? container.decode(String.self, forKey: .tool)).flatMap(Tool.init(rawValue:)) ?? .pen
        self.ink = (try? container.decode(String.self, forKey: .ink)).flatMap(Ink.init(rawValue:)) ?? .red
        self.capture = (try? container.decode(CapturePreference.self, forKey: .capture)) ?? .standard
        self.whiteboard = (try? container.decode(WhiteboardDefaults.self, forKey: .whiteboard)) ?? .standard
        self.updates = (try? container.decode(UpdateSchedulePreference.self, forKey: .updates)) ?? .standard
        self.hasCompletedOnboarding = (try? container.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? false
    }

    /// Encodes the preferences as JSON under the versioned key. `tool` and
    /// `ink` are written as their raw values (`Tool`/`Ink` are plain data
    /// enums, not `Codable`). Legacy keys stay untouched; they stop being
    /// read once the blob exists.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pointer, forKey: .pointer)
        try container.encode(general, forKey: .general)
        try container.encode(toolShortcuts, forKey: .toolShortcuts)
        try container.encode(hotkeys, forKey: .hotkeys)
        try container.encode(tool.rawValue, forKey: .tool)
        try container.encode(ink.rawValue, forKey: .ink)
        try container.encode(capture, forKey: .capture)
        try container.encode(whiteboard, forKey: .whiteboard)
        try container.encode(updates, forKey: .updates)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
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
        let pointer = PreferencesMigration.migratedPointerStyle(in: store)
        let general = PreferencesMigration.migratedGeneralPreferences(in: store)
        if pointer != nil || general != nil {
            return AppPreferences(pointer: pointer ?? .standard, general: general ?? .standard)
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

    /// Legacy key holding whether the armed frame is drawn.
    public static let legacyFrameKey = "showArmedFrame"
    /// Legacy key holding `"all"` or `"active"`.
    public static let legacyScopeKey = "overlayScope"
    /// Legacy key holding `"cursor"`, `"frontWindow"` or `"fixed"`.
    public static let legacyPlacementKey = "palettePlacement"
    /// Legacy key holding the laser lifetime in seconds.
    public static let legacyLifetimeKey = "laserLifetime"

    /// Builds the general preferences the legacy keys describe, or nil when
    /// none of them is stored. A missing legacy key keeps today's default, an
    /// unknown string maps to the field's default like today's renderer —
    /// anything but `"active"` draws everywhere, anything but
    /// `"frontWindow"`/`"fixed"` opens the palette at the pointer — and the
    /// legacy keys are never deleted or rewritten.
    public static func migratedGeneralPreferences(in store: PreferenceStore) -> GeneralPreferences? {
        let hasFrame = store.object(forKey: legacyFrameKey) != nil
        let hasScope = store.object(forKey: legacyScopeKey) != nil
        let hasPlacement = store.object(forKey: legacyPlacementKey) != nil
        let hasLifetime = store.object(forKey: legacyLifetimeKey) != nil
        guard hasFrame || hasScope || hasPlacement || hasLifetime else { return nil }

        var general = GeneralPreferences.standard
        if hasFrame {
            general.showArmedFrame = store.bool(forKey: legacyFrameKey, default: true)
        }
        if hasScope {
            general.scope = store.string(forKey: legacyScopeKey).flatMap(OverlayScope.init(rawValue:)) ?? .all
        }
        if hasPlacement {
            general.palettePlacement = store.string(forKey: legacyPlacementKey).flatMap(PalettePlacement.init(rawValue:)) ?? .cursor
        }
        if hasLifetime {
            general.laserLifetime = LaserLifetime(
                rawValue: store.double(forKey: legacyLifetimeKey, default: GeneralPreferences.standard.laserLifetime.rawValue)
            ) ?? .twoPointFive
        }
        return general
    }
}
