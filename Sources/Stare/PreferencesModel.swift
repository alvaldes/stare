import Combine
import Foundation
import StareCore

/// The one persisted owner of the app-wide preferences (T6 slice 1/S4):
/// everything the app stores lives in a single versioned `AppPreferences`
/// blob loaded once from the injected `PreferenceStore` and saved back on
/// every change.
///
/// Invariant: one blob in, one blob out — every value is a mirror of a field
/// of that one document, each setter updates its mirror, the document and
/// saves the whole blob immediately, and there are no key-per-control writes
/// anywhere; no other component may load the preferences from
/// `UserDefaults` (the capture editor and the selftest harness run detached
/// on in-memory defaults because they never see this instance).
///
/// The `@Published` mirrors exist so Settings panes (slice 2) can bind to
/// this model directly, while `EditorState` keeps its own mirrors in sync by
/// subscribing to them, so views that observe `EditorState` still re-render
/// when any value changes.
@MainActor
final class PreferencesModel: ObservableObject {
    private let store: PreferenceStore

    /// The persisted document the mirrors project from and persist into.
    private(set) var preferences: AppPreferences

    /// Mirror of the pointer style; writing it persists the whole blob.
    @Published var pointer: PointerStyle {
        didSet { persist() }
    }
    /// Mirror of the armed frame switch; writing it persists the whole blob.
    @Published var showArmedFrame: Bool {
        didSet { persist() }
    }
    /// Mirror of where the overlay draws; writing it persists the whole blob.
    @Published var scope: OverlayScope {
        didSet { persist() }
    }
    /// Mirror of where the palette opens; writing it persists the whole blob.
    @Published var palettePlacement: PalettePlacement {
        didSet { persist() }
    }
    /// Mirror of the laser lifetime; writing it persists the whole blob.
    @Published var laserLifetime: LaserLifetime {
        didSet { persist() }
    }
    /// Mirror of the first-run flag; writing it persists the whole blob.
    @Published var hasCompletedOnboarding: Bool {
        didSet { persist() }
    }
    /// Mirror of the tool drawing starts with (T8/S6); writing it persists
    /// the whole blob.
    @Published var tool: Tool {
        didSet { persist() }
    }
    /// Mirror of the ink drawing starts with (T8/S6); writing it persists
    /// the whole blob.
    @Published var ink: Ink {
        didSet { persist() }
    }
    /// Mirror of the per-tool shortcut map (T8/S6): the Settings pane edits
    /// it and the overlay's routing reads it through `EditorState`; writing
    /// it persists the whole blob.
    @Published var toolShortcuts: ToolShortcutMap {
        didSet { persist() }
    }
    /// Mirror of the four global hotkeys (T9/S6): the Settings pane edits it
    /// and the AppDelegate's registration path reads it; writing it persists
    /// the whole blob.
    @Published var hotkeys: HotkeyBindings {
        didSet { persist() }
    }
    /// Runtime outcome of the last global-hotkey registration attempt
    /// (T9/S6), reported by the AppDelegate's registration path; never
    /// persisted. A rejection means the system refused the registration —
    /// usually another app owns the shortcut — and the previous binding
    /// stayed registered, with the model reverted to it.
    @Published var hotkeyRejection: HotkeyRejection?

    /// Loads the blob once through `AppPreferences(store:)`, which also
    /// carries the legacy per-key migration; no legacy key is ever written.
    init(store: PreferenceStore = UserDefaultsPreferenceStore()) {
        self.store = store
        let loaded = AppPreferences(store: store)
        self.preferences = loaded
        self.pointer = loaded.pointer
        self.showArmedFrame = loaded.general.showArmedFrame
        self.scope = loaded.general.scope
        self.palettePlacement = loaded.general.palettePlacement
        self.laserLifetime = loaded.general.laserLifetime
        self.hasCompletedOnboarding = loaded.hasCompletedOnboarding
        self.tool = loaded.tool
        self.ink = loaded.ink
        self.toolShortcuts = loaded.toolShortcuts
        self.hotkeys = loaded.hotkeys
    }

    /// Writes the one blob from the mirrors. Everything else keeps reading
    /// the same document, so a save is always the whole state, never a lone
    /// key.
    private func persist() {
        preferences.pointer = pointer
        preferences.general = GeneralPreferences(
            showArmedFrame: showArmedFrame,
            scope: scope,
            palettePlacement: palettePlacement,
            laserLifetime: laserLifetime
        )
        preferences.hasCompletedOnboarding = hasCompletedOnboarding
        preferences.tool = tool
        preferences.ink = ink
        preferences.toolShortcuts = toolShortcuts
        preferences.hotkeys = hotkeys
        preferences.save(to: store)
    }
}
