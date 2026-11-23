import Combine
import Foundation
import StareCore

/// The capture editor's one armed item (S6): a drawing tool or the crop
/// action. The rule is the value itself — picking one replaces the other, so
/// exactly one palette item is marked at any moment. Surfaces without a crop
/// action (the drawing overlay, the whiteboard) hold `.tool(tool)` in step
/// with `tool`, so their marking is today's behaviour.
enum CaptureSelection: Equatable {
    case tool(Tool)
    case crop
}

/// Editor state shared by the overlay views and the floating toolbar: the
/// current tool, the current ink and whether the armed frame is drawn.
///
/// Persistence lives in the injected `PreferencesModel` (T6 slice 1): every
/// general and pointer value below is a mirror of a field of the model's one
/// blob, written through it on change — `EditorState` never touches
/// `UserDefaults` itself. The published property names and types are kept
/// exactly as the existing consumers (`OverlayView`, `OverlayController`,
/// `ToolbarPanel`, `CaptureEditor`, `SelfTest`, and the current
/// `SettingsView`) use them; consumers that used to compare strings compare
/// the typed accessors (`overlayScopeValue`, `palettePlacementValue`,
/// `pointerPreset`) instead. `tool`, `ink` and the shortcut map persist too
/// (T8/S6).
final class EditorState: ObservableObject {
    /// The single preferences owner. Nil in surfaces that never see the
    /// app's instance — the capture editor (created per capture, detached
    /// from the app's own state) and the selftest harness (which must not
    /// read or write the user's real preferences). They run on the shipped
    /// defaults in memory only.
    private let preferences: PreferencesModel?
    private var preferenceCancellables: Set<AnyCancellable> = []
    /// True while the mirrors are being refreshed from the preferences
    /// model, so a refresh does not bounce back into the model and persist.
    private var syncingFromModel = false

    @Published var tool: Tool = .pen {
        didSet {
            Diag.log("tool=\(tool.rawValue)")
            writeIfNotSyncing { $0.tool = tool }
            // S6: a tool picked through any route (palette, keyboard, history)
            // becomes the armed item again, so the crop's marking falls off at
            // the same moment the tool's comes on — one state, one marked item.
            if captureSelection != .tool(tool) { captureSelection = .tool(tool) }
        }
    }
    /// The one armed item the palette marks (S6): `selectCrop` arms the crop
    /// action and any tool selection (including `tool`'s own `didSet`) arms the
    /// tool again. Never stored stale: it always answers `tool` unless the crop
    /// is armed right now.
    @Published private(set) var captureSelection: CaptureSelection = .tool(.pen)
    @Published var ink: Ink = .red {
        didSet { writeIfNotSyncing { $0.ink = ink } }
    }
    /// Mirror of the persisted tool-shortcut map (T8/S6): the overlay and the
    /// capture editor route key presses through `shortcutRouter`, which is
    /// rebuilt from this map, so a shortcut edited in Settings routes
    /// everywhere. Detached state (capture editor, selftest harness) keeps
    /// the shipped `.standard` map in memory only.
    @Published var toolShortcuts: ToolShortcutMap = .standard {
        didSet { writeIfNotSyncing { $0.toolShortcuts = toolShortcuts } }
    }
    /// S15 slice A: whether the next rectangle or ellipse is drawn filled, and
    /// the head the next arrow carries — the style keys of the drawing
    /// session (`9` toggles the fill, `0` cycles the head, overlay only).
    /// Deliberately NOT wired into the preferences mirror plumbing: nothing
    /// persists them, nothing in Settings references them, and surfaces that
    /// have not adopted the keys keep the outline/open default — the capture
    /// editor draws its shapes through its own `session.begin` calls and
    /// stays outline-only for now (gap on record, a later unit adopts it).
    @Published var shapesFilled: Bool = false
    /// S15 slice A: the arrowhead style the next arrow is drawn with (see
    /// `shapesFilled` for why this stays out of the persistence plumbing).
    @Published var arrowHeadStyle: ArrowHeadStyle = .open
    /// The router the drawing surfaces resolve keys with: always rebuilt from
    /// the live map, so the map the Settings pane edits is the map that
    /// routes.
    var shortcutRouter: ShortcutRouter {
        ShortcutRouter(shortcuts: toolShortcuts)
    }
    @Published var showArmedFrame: Bool {
        didSet { writeIfNotSyncing { $0.showArmedFrame = showArmedFrame } }
    }
    /// Presentation mode: the layer is visible but passes clicks through, so the
    /// pointer highlight works while the user keeps working in another app.
    @Published var pointerActive: Bool = false
    /// Mirror of the overlay scope; "all" draws on every display, "active"
    /// only on the one under the pointer. Compare it through
    /// `overlayScopeValue` instead of the string.
    @Published var overlayScope: String {
        didSet { writeIfNotSyncing { $0.scope = OverlayScope(rawValue: overlayScope) ?? .all } }
    }
    /// Mirror of where the palette opens. Compare it through
    /// `palettePlacementValue` instead of the string.
    @Published var palettePlacement: String {
        didSet {
            writeIfNotSyncing {
                $0.palettePlacement = PalettePlacement(rawValue: palettePlacement) ?? .cursor
            }
        }
    }
    /// Mirror of the toolbar's orientation (T9/S12): a horizontal row or a
    /// vertical stack. The Settings pane writes the model, this state mirrors
    /// it, and the toolbar panel and view react from here; detached state
    /// (capture editor, selftest) keeps the shipped horizontal default.
    @Published var toolbarOrientation: ToolbarOrientation {
        didSet { writeIfNotSyncing { $0.toolbarOrientation = toolbarOrientation } }
    }
    /// Mirror of the toolbar's docked border (T9/S12): the edge the bar rests
    /// at when it has not been dragged, which is also the gripper's reset
    /// target for the current choice.
    @Published var toolbarBorder: ToolbarBorder {
        didSet { writeIfNotSyncing { $0.toolbarBorder = toolbarBorder } }
    }
    /// Mirror of the drawing toolbar's tool layout (T8/S10): the persisted
    /// order and visibility the bar renders. The Settings pane writes the
    /// model, this state mirrors it, and the toolbar's tool section follows;
    /// detached state (capture editor, selftest) keeps the shipped
    /// `.standard` layout — the capture editor passes its own fixed palette
    /// anyway, and a keyboard shortcut is not the bar, so a hidden tool stays
    /// shortcut-armed everywhere.
    @Published var toolbarTools: ToolbarToolLayout = .standard {
        didSet { writeIfNotSyncing { $0.toolbarTools = toolbarTools } }
    }
    /// Mirror of the pointer highlight diameter, in points.
    @Published var pointerSize: CGFloat {
        didSet { writeIfNotSyncing { $0.pointer.size = Double(pointerSize) } }
    }
    /// Mirror of the pointer shape as the legacy "circle"/"squircle" strings;
    /// the slice-2 Settings pane binds the full `PointerStyle` instead.
    /// Compare it through `pointerPreset` instead of the string.
    @Published var pointerShape: String {
        didSet { writeIfNotSyncing { $0.pointer.preset = pointerShape == "squircle" ? .squircle : .ring } }
    }
    /// Mirror of whether the glow is on: any positive glow intensity reads
    /// as on, and writing maps on/off to today's full/off intensities.
    @Published var pointerGlow: Bool {
        didSet { writeIfNotSyncing { $0.pointer.glowIntensity = pointerGlow ? 1 : 0 } }
    }
    /// Fade the highlight down when the pointer stops moving.
    @Published var pointerFadeWhenIdle: Bool {
        didSet { writeIfNotSyncing { $0.pointer.fadeWhenIdle = pointerFadeWhenIdle } }
    }
    /// Mirror of the band thickness as a ratio of the radius.
    @Published var pointerBandWidth: Double {
        didSet { writeIfNotSyncing { $0.pointer.bandWidth = pointerBandWidth } }
    }
    /// Mirror of the glow strength, 0...1; 0 turns the glow off.
    @Published var pointerGlowStrength: Double {
        didSet { writeIfNotSyncing { $0.pointer.glowIntensity = pointerGlowStrength } }
    }
    /// Mirror of where the highlight's colour comes from: true follows the
    /// active ink, false uses `pointerFixedInk`.
    @Published var pointerColorFollowsInk: Bool {
        didSet {
            writeIfNotSyncing {
                $0.pointer.colorSource = pointerColorFollowsInk ? .ink : .fixed(pointerFixedInk)
            }
        }
    }
    /// Mirror of the fixed ink, used whenever the colour does not follow the
    /// active ink.
    @Published var pointerFixedInk: Ink {
        didSet {
            guard !pointerColorFollowsInk else { return }
            writeIfNotSyncing { $0.pointer.colorSource = .fixed(pointerFixedInk) }
        }
    }
    /// Mirror of the laser lifetime in seconds; only today's picker values
    /// are persisted, anything else falls back to the default on write.
    @Published var laserLifetime: TimeInterval {
        didSet {
            writeIfNotSyncing {
                $0.laserLifetime = LaserLifetime(rawValue: laserLifetime) ?? .twoPointFive
            }
        }
    }
    /// Mirror of the first page's colour: "system" follows the appearance
    /// (light → white, dark → black), "white" and "black" fix it. New pages
    /// inherit the page they came from; ⌘B still flips the current page.
    /// Persisted in the one blob's whiteboard defaults, never as its own key.
    @Published var boardPageBackground: String {
        didSet {
            writeIfNotSyncing {
                $0.whiteboard.background = WhiteboardBackgroundChoice(rawValue: boardPageBackground) ?? .system
            }
        }
    }
    /// Mirror of where the whiteboard opens: "all" covers every display,
    /// "active" only the one under the pointer — the same rule the drawing
    /// overlay uses. Persisted in the one blob's whiteboard defaults.
    @Published var boardScope: String {
        didSet {
            writeIfNotSyncing {
                $0.whiteboard.scope = OverlayScope(rawValue: boardScope) ?? .all
            }
        }
    }
    /// Mirror of whether the whiteboard draws its border. The board's own
    /// preference, decided independently of the drawing frame
    /// (`showArmedFrame`); persisted in the one blob's whiteboard defaults.
    @Published var boardShowBorder: Bool {
        didSet { writeIfNotSyncing { $0.whiteboard.showsBorder = boardShowBorder } }
    }
    /// Whiteboard pages indicator for the toolbar: nil hides the page controls.
    @Published var whiteboardPage: (current: Int, total: Int)? = nil

    /// Mirror of what a blur mark produces over what it covers (T6b/S13): the
    /// Settings pane writes the model, this state mirrors it, and every mark
    /// the surface mints — the drawing overlay and the capture editor alike —
    /// stamps its own redaction from here. Detached state (capture editor
    /// with no model, selftest harness) keeps the shipped blur, today's
    /// behaviour, in memory only — the `laserLifetime` precedent.
    @Published var redactionStyle: RedactionStyle = .blur {
        didSet { writeIfNotSyncing { $0.redactionStyle = redactionStyle } }
    }

    /// Typed value behind the `overlayScope` string mirror; consumers that
    /// used to compare strings compare this instead.
    var overlayScopeValue: OverlayScope {
        OverlayScope(rawValue: overlayScope) ?? .all
    }

    /// Typed value behind the `palettePlacement` string mirror; consumers
    /// that used to compare strings compare this instead.
    var palettePlacementValue: PalettePlacement {
        PalettePlacement(rawValue: palettePlacement) ?? .cursor
    }

    /// Typed value behind the `pointerShape` string mirror, mapped the way
    /// today's renderer maps it — anything that is not "squircle" is a ring.
    var pointerPreset: PointerStylePreset {
        pointerShape == "squircle" ? .squircle : .ring
    }

    /// The style the pointer highlight draws from (T7/S5): with a
    /// preferences model it is the one blob's `PointerStyle`, which the
    /// Settings pane writes directly; detached state (selftest harness,
    /// capture editor) projects it from the mirrors on the shipped defaults.
    /// `OverlayView` reads this for both the renderer and the invalidation
    /// rect, so the highlight and its dirty rect answer to the same style.
    var pointerStyle: PointerStyle {
        guard let preferences else {
            return PointerStyle(
                preset: pointerPreset,
                size: Double(pointerSize),
                colorSource: pointerColorFollowsInk ? .ink : .fixed(pointerFixedInk),
                bandWidth: pointerBandWidth,
                glowIntensity: pointerGlowStrength,
                fadeWhenIdle: pointerFadeWhenIdle
            )
        }
        return MainActor.assumeIsolated { preferences.pointer }
    }

    /// Creates the state. With `preferences`, every value seeds from the one
    /// blob and every change persists through it; without it (capture
    /// editor, selftest) the state runs on the shipped defaults in memory.
    init(preferences: PreferencesModel? = nil) {
        self.preferences = preferences
        if let preferences {
            // The model is main-actor isolated and this state is only ever
            // created on the main thread, so the assumed isolation holds.
            let style = MainActor.assumeIsolated { preferences.pointer }
            let frame = MainActor.assumeIsolated { preferences.showArmedFrame }
            let scope = MainActor.assumeIsolated { preferences.scope }
            let placement = MainActor.assumeIsolated { preferences.palettePlacement }
            let lifetime = MainActor.assumeIsolated { preferences.laserLifetime }
            let orientation = MainActor.assumeIsolated { preferences.toolbarOrientation }
            let border = MainActor.assumeIsolated { preferences.toolbarBorder }
            let toolsLayout = MainActor.assumeIsolated { preferences.toolbarTools }
            let whiteboard = MainActor.assumeIsolated { preferences.whiteboard }
            let redactionStyle = MainActor.assumeIsolated { preferences.redactionStyle }
            pointerSize = CGFloat(style.size)
            pointerShape = style.preset == .squircle ? "squircle" : "circle"
            pointerGlow = style.glowIntensity > 0
            pointerFadeWhenIdle = style.fadeWhenIdle
            pointerBandWidth = style.bandWidth
            pointerGlowStrength = style.glowIntensity
            if case .fixed(let fixedInk) = style.colorSource {
                pointerFixedInk = fixedInk
                pointerColorFollowsInk = false
            } else {
                pointerFixedInk = .red
                pointerColorFollowsInk = true
            }
            showArmedFrame = frame
            overlayScope = scope.rawValue
            palettePlacement = placement.rawValue
            laserLifetime = lifetime.rawValue
            toolbarOrientation = orientation
            toolbarBorder = border
            toolbarTools = toolsLayout
            boardPageBackground = whiteboard.background.rawValue
            boardScope = whiteboard.scope.rawValue
            boardShowBorder = whiteboard.showsBorder
            self.redactionStyle = redactionStyle
            MainActor.assumeIsolated {
                self.tool = preferences.tool
                self.ink = preferences.ink
                self.toolShortcuts = preferences.toolShortcuts
            }
        } else {
            pointerSize = CGFloat(PointerStyle.standard.size)
            pointerShape = "squircle"
            pointerGlow = true
            pointerFadeWhenIdle = true
            pointerBandWidth = PointerStyle.defaultBandWidth
            pointerGlowStrength = PointerStyle.defaultGlowIntensity
            pointerFixedInk = .red
            pointerColorFollowsInk = true
            showArmedFrame = true
            overlayScope = OverlayScope.all.rawValue
            palettePlacement = PalettePlacement.cursor.rawValue
            laserLifetime = LaserLifetime.twoPointFive.rawValue
            toolbarOrientation = .horizontal
            toolbarBorder = .top
            boardPageBackground = WhiteboardDefaults.standard.background.rawValue
            boardScope = WhiteboardDefaults.standard.scope.rawValue
            boardShowBorder = WhiteboardDefaults.standard.showsBorder
        }
        if let preferences {
            MainActor.assumeIsolated { subscribeToModel(preferences) }
        }
        // S6: the armed item starts as the seeded tool, so a fresh state marks
        // exactly one thing — set explicitly instead of leaning on whether the
        // `tool` observers fire during initialization.
        captureSelection = .tool(tool)
    }

    /// Keeps the mirrors in step with the one blob, so a change made
    /// directly on the model (the slice-2 Settings panes) reaches every view
    /// that observes this state.
    @MainActor
    private func subscribeToModel(_ model: PreferencesModel) {
        model.$pointer.dropFirst().sink { [weak self] style in
            self?.syncFromModel {
                $0.pointerSize = CGFloat(style.size)
                $0.pointerShape = style.preset == .squircle ? "squircle" : "circle"
                $0.pointerGlow = style.glowIntensity > 0
                $0.pointerFadeWhenIdle = style.fadeWhenIdle
                $0.pointerBandWidth = style.bandWidth
                $0.pointerGlowStrength = style.glowIntensity
                if case .fixed(let fixedInk) = style.colorSource {
                    $0.pointerFixedInk = fixedInk
                    $0.pointerColorFollowsInk = false
                } else {
                    $0.pointerColorFollowsInk = true
                }
            }
        }.store(in: &preferenceCancellables)
        model.$showArmedFrame.dropFirst().sink { [weak self] value in
            self?.syncFromModel { $0.showArmedFrame = value }
        }.store(in: &preferenceCancellables)
        model.$scope.dropFirst().sink { [weak self] value in
            self?.syncFromModel { $0.overlayScope = value.rawValue }
        }.store(in: &preferenceCancellables)
        model.$palettePlacement.dropFirst().sink { [weak self] value in
            self?.syncFromModel { $0.palettePlacement = value.rawValue }
        }.store(in: &preferenceCancellables)
        model.$laserLifetime.dropFirst().sink { [weak self] value in
            self?.syncFromModel { $0.laserLifetime = value.rawValue }
        }.store(in: &preferenceCancellables)
        model.$toolbarOrientation.dropFirst().sink { [weak self] value in
            self?.syncFromModel { $0.toolbarOrientation = value }
        }.store(in: &preferenceCancellables)
        model.$toolbarBorder.dropFirst().sink { [weak self] value in
            self?.syncFromModel { $0.toolbarBorder = value }
        }.store(in: &preferenceCancellables)
        model.$toolbarTools.dropFirst().sink { [weak self] value in
            self?.syncFromModel { $0.toolbarTools = value }
        }.store(in: &preferenceCancellables)
        model.$tool.dropFirst().sink { [weak self] value in
            self?.syncFromModel { $0.tool = value }
        }.store(in: &preferenceCancellables)
        model.$ink.dropFirst().sink { [weak self] value in
            self?.syncFromModel { $0.ink = value }
        }.store(in: &preferenceCancellables)
        model.$toolShortcuts.dropFirst().sink { [weak self] value in
            self?.syncFromModel { $0.toolShortcuts = value }
        }.store(in: &preferenceCancellables)
        model.$whiteboard.dropFirst().sink { [weak self] defaults in
            self?.syncFromModel {
                $0.boardPageBackground = defaults.background.rawValue
                $0.boardScope = defaults.scope.rawValue
                $0.boardShowBorder = defaults.showsBorder
            }
        }.store(in: &preferenceCancellables)
        model.$redactionStyle.dropFirst().sink { [weak self] style in
            self?.syncFromModel { $0.redactionStyle = style }
        }.store(in: &preferenceCancellables)
    }

    /// Writes a value into the preferences model unless the write came from
    /// a model refresh, which must not persist back.
    private func writeIfNotSyncing(_ write: @MainActor (PreferencesModel) -> Void) {
        guard !syncingFromModel, let preferences else { return }
        // EditorState is only ever created and used on the main thread (the
        // overlay, the toolbar and the editors are main-thread objects), so
        // the assumed isolation holds.
        MainActor.assumeIsolated { write(preferences) }
    }

    private func syncFromModel(_ update: (EditorState) -> Void) {
        syncingFromModel = true
        update(self)
        syncingFromModel = false
    }

    /// The board's page-colour choice, parsed from the mirror above. An
    /// unknown value falls back to following the system, the documented
    /// default.
    var boardBackgroundChoice: BoardBackground {
        BoardBackground(rawValue: boardPageBackground) ?? .system
    }

    // MARK: - Selected-tool state (S6)

    /// What the palette marks for `candidate` (S6): the armed item decides, so
    /// in the capture editor a tool is marked only while it is the one armed —
    /// picking the crop unmarks it. Surfaces without crop hold `.tool(tool)`
    /// always, which reduces this to today's `tool == candidate` marking.
    func isToolMarked(_ candidate: Tool) -> Bool {
        switch captureSelection {
        case .tool(let armed): return armed == candidate
        case .crop: return false
        }
    }

    /// Whether the palette marks the extra crop action (S6).
    var isCropMarked: Bool {
        if case .crop = captureSelection { return true }
        return false
    }

    /// Picking any tool is the editor's way of giving the crop up. Routing the
    /// pick through `tool` keeps the persisted tool and the armed item one
    /// state — the `didSet` above does the realignment.
    func select(_ candidate: Tool) {
        tool = candidate
    }

    /// Picking the crop arms it as the palette's single selection (S6): the
    /// active tool is unmarked but remembered (`tool` keeps its value), so the
    /// editor can hand the mark back when the crop is given up.
    func selectCrop() {
        captureSelection = .crop
    }

    /// Ends the crop's turn as the armed item, giving the mark back to the
    /// remembered tool — used when the staged rectangle is confirmed with
    /// Return or cancelled with Escape (T4/S6). Picking a tool instead
    /// reroutes through `select(_:)`, whose `didSet` does the same.
    func endCropSelection() {
        captureSelection = .tool(tool)
    }
}
