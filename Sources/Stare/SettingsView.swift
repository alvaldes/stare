import AppKit
import SwiftUI
import StareCore

/// The areas of the Settings window, in sidebar order.
enum SettingsArea: String, CaseIterable, Identifiable {
    case general, tools, shortcuts, marker, capture, whiteboard, permissions, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .tools: "Tools"
        case .shortcuts: "Shortcuts"
        case .marker: "Pointer Highlight"
        case .capture: "Capture"
        case .whiteboard: "Whiteboard"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .tools: "wrench.and.screwdriver"
        case .shortcuts: "keyboard"
        case .marker: "scope"
        case .capture: "camera.viewfinder"
        case .whiteboard: "square.grid.2x2"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

/// Publishes the shared `ScreenRecordingPermission` for the Permissions pane.
/// The permission model is a plain `@MainActor` class whose single `onChange`
/// callback belongs to the onboarding guide, so this shell does not take the
/// callback: it publishes the state it reads with `refresh()` — on appear,
/// on activation (back from System Settings) and on the pane's Refresh button.
@MainActor
final class PermissionProbe: ObservableObject {
    let permission: ScreenRecordingPermission
    @Published private(set) var access: ScreenRecordingAccess = .denied
    private var activeObserver: NSObjectProtocol?

    init(permission: ScreenRecordingPermission) {
        self.permission = permission
        access = permission.access
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    func refresh() {
        access = permission.refresh()
    }

    func openSettings() {
        permission.openSettings()
    }
}

/// The Settings window content: a material sidebar of areas on the left and
/// the selected area's panes of cards on the right. Every control writes
/// through the single `PreferencesModel` (T6 slice 1) — never UserDefaults.
struct SettingsView: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var permission: PermissionProbe

    /// Every open starts on General, like netty's Settings. The controller
    /// recreates the hosting view each `show()`, so this `@State` (and the
    /// pane scroll position) reset deterministically even though closing the
    /// window does not tear the SwiftUI tree down. The selftest renders a
    /// chosen pane directly through `initialArea`.
    @State private var area: SettingsArea = .general
    @Environment(\.colorScheme) private var colorScheme

    init(
        model: PreferencesModel,
        permission: PermissionProbe,
        initialArea: SettingsArea = .general
    ) {
        self.model = model
        self.permission = permission
        _area = State(initialValue: initialArea)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                pane
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                AppMark(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Stare")
                        .font(.system(size: 16, weight: .bold))
                    Text("Version \(AppVersion.short)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)

            ForEach(SettingsArea.allCases) { area in
                sidebarButton(for: area)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 180)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func sidebarButton(for area: SettingsArea) -> some View {
        Button {
            self.area = area
        } label: {
            HStack(spacing: 10) {
                Image(systemName: area.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(self.area == area ? Color(nsColor: .controlAccentColor) : .secondary)
                    .frame(width: 18)
                Text(area.title)
                    .font(.system(size: 13,
                                  weight: self.area == area ? .semibold : .regular))
                    .foregroundStyle(self.area == area ? Color(nsColor: .controlAccentColor) : Color.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if self.area == area {
                    // Card wash: an elevated card sitting on the material.
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(nsColor: .controlBackgroundColor)
                            .opacity(colorScheme == .dark ? 0.28 : 0.75))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(Color(nsColor: .separatorColor))
                        )
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(self.area == area ? [.isSelected] : [])
    }

    // MARK: Panes

    /// The pane content for an area — header and cards, without the shell's
    /// sidebar and scroll container. The selftest renders each pane directly
    /// (`renderSettings`), so the switch lives here for one writer.
    @ViewBuilder
    static func pane(for area: SettingsArea, model: PreferencesModel, permission: PermissionProbe) -> some View {
        switch area {
        case .general: GeneralPane(model: model)
        case .tools: ToolsPane(model: model)
        case .shortcuts: ShortcutsPane(model: model)
        case .marker: MarkerPane(model: model)
        case .capture: CapturePane(model: model)
        case .whiteboard: WhiteboardPane(model: model)
        case .permissions: PermissionsPane(permission: permission)
        case .about: AboutPane()
        }
    }

    @ViewBuilder
    private var pane: some View {
        Self.pane(for: area, model: model, permission: permission)
    }
}

// MARK: - General

/// Drawing frame, displays and laser, plus startup and updates (T10/S6) —
/// as cards.
private struct GeneralPane: View {
    @ObservedObject var model: PreferencesModel
    /// The real login-item service, re-read every time the pane appears; the
    /// pane never caches a status the system has since changed.
    @StateObject private var login = LaunchAtLogin()

    var body: some View {
        VStack(spacing: 16) {
            PaneHeader(title: "General", subtitle: "How Stare draws over the screen.")

            startupCard
            updatesCard

            SettingsCard(title: "Drawing", symbol: "pencil.tip") {
                SettingRow(
                    title: "Show drawing frame",
                    detail: "A thin frame in the active ink marks every display that will take a mark.",
                    content: Toggle("", isOn: $model.showArmedFrame)
                        .labelsHidden()
                )
            }

            SettingsCard(title: "Displays", symbol: "display.2") {
                SettingRow(
                    title: "Draw on",
                    content: Picker("", selection: $model.scope) {
                        ForEach(OverlayScope.allCases, id: \.self) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                )
                SettingRow(
                    title: "Open the palette",
                    content: Picker("", selection: $model.palettePlacement) {
                        ForEach(PalettePlacement.allCases, id: \.self) { placement in
                            Text(placement.title).tag(placement)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                )
                Text("Marking every display is the default; the palette follows the pointer unless told otherwise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard(title: "Laser", symbol: "cursor.rays") {
                SettingRow(
                    title: "Laser lasts",
                    content: Picker("", selection: $model.laserLifetime) {
                        ForEach(LaserLifetime.allCases, id: \.self) { lifetime in
                            Text(lifetime.title).tag(lifetime)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                )
                Text("Laser marks fade out and never appear in a capture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Startup (launch at login, T10/S6)

    /// The toggle drives the real login-item registration, the status is the
    /// service's own, an approval requirement opens the exact system pane,
    /// and a registration error is shown instead of swallowed.
    private var startupCard: some View {
        SettingsCard(title: "Startup", symbol: "power") {
            SettingRow(
                title: "Open Stare at login",
                detail: loginDetail,
                content: Toggle("", isOn: Binding(
                    get: { login.isEnabled },
                    set: { login.setEnabled($0) }
                ))
                .labelsHidden()
            )
            HStack(spacing: 8) {
                Text("Login item: \(login.statusDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if login.needsApproval {
                HStack(spacing: 8) {
                    Label(
                        "macOS needs your approval before Stare can start at login.",
                        systemImage: "person.badge.shield.checkmark"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    Spacer()
                    Button("Open Login Items…") { login.openLoginItemsSettings() }
                }
            }
            if let error = login.lastError {
                RefusalNote(text: error)
            }
        }
        .onAppear { login.refresh() }
    }

    /// Registration is meaningful for an app in /Applications — where the
    /// login item keeps pointing. Running from somewhere else is never
    /// blocked, but the detail says so plainly instead of implying the entry
    /// will survive.
    private var loginDetail: String {
        if login.runsFromApplications {
            return "Starts Stare automatically when you log in."
        }
        return "Login items are honoured for apps in /Applications; Stare is running from \(Bundle.main.bundlePath)."
    }

    // MARK: Updates (T10/S6)

    /// The schedule decides when a check runs; Check Now runs one at once.
    /// An available newer release is named with its version and a link to
    /// the release page — Stare is not notarized, so it never installs.
    private var updatesCard: some View {
        SettingsCard(title: "Updates", symbol: "arrow.down.circle") {
            SettingRow(
                title: "Check for updates",
                content: Picker("", selection: $model.updateSchedule) {
                    ForEach(UpdateCheckSchedule.allCases, id: \.self) { schedule in
                        Text(schedule.title).tag(schedule)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            )
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.updateStatus.message)
                    if let release = model.updateStatus.available {
                        Text("Version \(release.version.displayString) is ready to download.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let lastCheck = model.updateLastCheck {
                        Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Check Now") {
                    Task { await UpdateFlow.checkNow(model: model) }
                }
                if let release = model.updateStatus.available {
                    Link("Download", destination: release.pageURL)
                }
            }
            Text(
                "Stare is not notarized, so checking only points at the latest release — "
                    + "download it here or run `brew upgrade --cask stare`. Stare never installs anything itself."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            Task { await UpdateFlow.checkIfDue(model: model) }
        }
    }
}

// MARK: - Tools

/// A rounded key badge: what both shortcut panes show as a row's current key.
private struct KeyBadge: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// A visible refusal (T8/T9/S6): the map is left unchanged, and the pane says
/// why instead of failing silently.
private struct RefusalNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The starting tool and ink, the per-tool shortcuts and the palette's
/// position (T8/S6). Every control writes through the one preferences blob.
private struct ToolsPane: View {
    @ObservedObject var model: PreferencesModel
    /// The tool whose shortcut is being captured, if any.
    @State private var recordingTool: Tool?
    /// The last refusal, shown instead of a silent no-op.
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 16) {
            PaneHeader(title: "Tools", subtitle: "The ink you start with, the tool keys and the palette.")

            SettingsCard(title: "Starting ink", symbol: "paintpalette") {
                SettingRow(
                    title: "Start drawing with",
                    detail: "The ink the palette opens with, wherever Stare draws.",
                    content: HStack(spacing: 7) {
                        ForEach(Ink.allCases) { ink in
                            swatch(ink)
                        }
                    }
                )
                Text("The choice persists across launches; while drawing the swatches and the number keys still switch the ink at once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard(title: "Tool shortcuts", symbol: "keyboard") {
                ForEach(Tool.allCases) { tool in
                    SettingRow(
                        title: tool.displayName,
                        content: HStack(spacing: 10) {
                            KeyBadge(title: String(model.toolShortcuts[tool]))
                            Button(recordingTool == tool ? "Recording…" : "Record") {
                                startRecording(tool)
                            }
                            .disabled(recordingTool != nil && recordingTool != tool)
                        }
                    )
                }
                if let notice {
                    RefusalNote(text: notice)
                }
                HStack {
                    Spacer()
                    Button("Restore defaults") {
                        model.toolShortcuts = .standard
                        notice = nil
                    }
                }
                Text("One key per tool: assigning a key another tool already holds is refused, so every tool stays reachable while drawing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard(title: "Toolbar", symbol: "rectangle.bottomthird.inset.filled") {
                SettingRow(
                    title: "Reset position",
                    detail: "Puts the palette back where a fresh install opens it, and moves it at once if it is on screen.",
                    content: Button("Reset") {
                        ToolbarPanel.requestPositionReset()
                    }
                )
            }

            KeyCaptureField(
                includesModifiers: false,
                active: recordingTool != nil,
                onCapture: { record($0) },
                onCancel: { recordingTool = nil }
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private func startRecording(_ tool: Tool) {
        notice = nil
        recordingTool = tool
    }

    /// Runs the captured key through the map's own assignment, so the same
    /// validation the router relies on refuses it here: a taken key names the
    /// tool that holds it and an unsupported character explains why, and a
    /// refusal leaves the map exactly as it was.
    private func record(_ binding: HotkeyBinding?) {
        defer { recordingTool = nil }
        guard let tool = recordingTool else { return }
        guard let binding else {
            notice = "That key can't be a tool shortcut."
            return
        }
        var map = model.toolShortcuts
        switch map.assigning(binding.key.character, to: tool) {
        case .success:
            model.toolShortcuts = map
            notice = nil
        case .failure(.conflict(let holder)):
            notice = "“\(binding.key.character)” is already assigned to \(holder.displayName); the map is unchanged."
        case .failure(.unsupportedCharacter):
            notice = "Only letters and numbers can be tool shortcuts."
        }
    }

    /// One ink as a round swatch; the starting ink carries an accent ring.
    private func swatch(_ ink: Ink) -> some View {
        Button {
            model.ink = ink
        } label: {
            Circle()
                .fill(Color(cgColor: ink.cgColor()))
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor)))
                .overlay {
                    if model.ink == ink {
                        Circle().strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 2)
                            .padding(-3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start drawing with \(ink.displayName)")
    }
}

// MARK: - Shortcuts

/// The four global hotkeys (T9/S6): each row shows its binding and offers
/// Record. The captured binding goes through `HotkeyBindings.assigning` —
/// conflicts with another action and modifier-less keys refuse visibly — and
/// then through the AppDelegate's registration path, which reports a system
/// rejection (usually another app owning the shortcut) while the previous
/// binding stays registered.
private struct ShortcutsPane: View {
    @ObservedObject var model: PreferencesModel
    @State private var recording: HotkeyAction?
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 16) {
            PaneHeader(title: "Shortcuts", subtitle: "The system-wide shortcuts Stare answers to.")

            SettingsCard(title: "Global shortcuts", symbol: "keyboard") {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    SettingRow(
                        title: action.title,
                        detail: detail(for: action),
                        content: HStack(spacing: 10) {
                            KeyBadge(title: model.hotkeys[action].displayTitle)
                            Button(recording == action ? "Recording…" : "Record") {
                                startRecording(action)
                            }
                            .disabled(recording != nil && recording != action)
                        }
                    )
                }
                if let rejection = model.hotkeyRejection {
                    RefusalNote(text: rejectionText(rejection))
                }
                if let notice {
                    RefusalNote(text: notice)
                }
                Text("These shortcuts work in any app, without extra permissions. While recording, press a key together with at least one modifier; esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            KeyCaptureField(
                includesModifiers: true,
                active: recording != nil,
                onCapture: { record($0) },
                onCancel: { recording = nil }
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private func startRecording(_ action: HotkeyAction) {
        notice = nil
        model.hotkeyRejection = nil
        recording = action
    }

    /// The refusal the registration path reported for this pane's last
    /// attempt: the system refused the binding, the model went back to the
    /// previous one, and that previous binding is still armed.
    private func rejectionText(_ rejection: HotkeyRejection) -> String {
        "Another app owns \(rejection.binding.displayTitle); \(rejection.action.title) kept \(model.hotkeys[rejection.action].displayTitle)."
    }

    /// Runs the captured binding through the bindings' own assignment, so the
    /// same validation the registration relies on refuses it here, and a
    /// refusal leaves the bindings exactly as they were.
    private func record(_ binding: HotkeyBinding?) {
        defer { recording = nil }
        guard let action = recording else { return }
        guard let binding else {
            notice = "That key can't be a shortcut."
            return
        }
        guard binding.isValid else {
            notice = "Add a modifier — a shortcut needs at least one modifier key."
            return
        }
        var bindings = model.hotkeys
        switch bindings.assigning(binding, to: action) {
        case .success:
            model.hotkeys = bindings
            notice = nil
        case .failure(.conflict(let holder)):
            notice = "\(binding.displayTitle) is already used by \(holder.title)."
        case .failure(.invalidBinding):
            notice = "A shortcut needs at least one modifier key."
        }
    }

    private func detail(for action: HotkeyAction) -> String {
        switch action {
        case .drawOverlay: "Arms and disarms drawing over the screen."
        case .pointerHighlight: "Shows the highlight that follows the pointer."
        case .pin: "Keeps the drawing on screen while you work in other apps."
        case .whiteboard: "Opens the opaque whiteboard."
        }
    }
}

// MARK: - Pointer Highlight

/// The pointer highlight's appearance settings (T7/S5). Every control writes
/// through the one preferences blob, and the preview draws the highlight with
/// the production renderer (`PointerHighlightRenderer`) at the real chosen
/// size over a light and a dark background, so what the user configures is
/// exactly what ⌥⇧M shows.
private struct MarkerPane: View {
    @ObservedObject var model: PreferencesModel
    /// Representative ink for the preview and the swatch-less case: the real
    /// highlight follows the active ink while drawing.
    private let sampleInk: Ink = .red

    /// Where the highlight's colour comes from, as the picker sees it.
    private enum ColourMode {
        case followInk, fixed
    }

    var body: some View {
        VStack(spacing: 16) {
            PaneHeader(title: "Pointer Highlight", subtitle: "The highlight that follows the pointer (⌥⇧M).")

            SettingsCard(title: "Highlight", symbol: "scope") {
                SettingRow(
                    title: "Style",
                    content: Picker("", selection: $model.pointer.preset) {
                        ForEach(PointerStylePreset.allCases, id: \.self) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                )
                SettingRow(
                    title: "Size",
                    content: HStack(spacing: 8) {
                        Slider(value: $model.pointer.size, in: PointerStyle.sizeRange)
                            .frame(width: 180)
                        Text("\(Int(model.pointer.size)) pt")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                )
                SettingRow(
                    title: "Band width",
                    detail: bandDetail,
                    content: HStack(spacing: 8) {
                        Slider(value: $model.pointer.bandWidth, in: PointerStyle.bandWidthRange)
                            .disabled(!bandApplies)
                            .frame(width: 180)
                        Text("\(Int((model.pointer.bandWidth * 100).rounded())) %")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                )
                SettingRow(
                    title: "Glow",
                    detail: "A soft halo outside the highlight's edge; zero turns it off.",
                    content: HStack(spacing: 8) {
                        Slider(value: $model.pointer.glowIntensity, in: PointerStyle.glowRange)
                            .frame(width: 180)
                        Text(glowLabel)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                )
                SettingRow(
                    title: "Fade when idle",
                    detail: "Lower the highlight while the pointer stops moving.",
                    content: Toggle("", isOn: $model.pointer.fadeWhenIdle)
                        .labelsHidden()
                )
                Text("The highlight follows the pointer in presentation mode (⌥⇧M) and never takes focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard(title: "Colour", symbol: "paintpalette") {
                SettingRow(
                    title: "Colour",
                    detail: "Either the ink active while drawing, or the highlight's own fixed one.",
                    content: Picker("", selection: colourMode) {
                        Text("Follow the current ink").tag(ColourMode.followInk)
                        Text("Fixed colour").tag(ColourMode.fixed)
                    }
                    .pickerStyle(.segmented)
                )
                if case .fixed = model.pointer.colorSource {
                    SettingRow(
                        title: "Fixed colour",
                        detail: nil,
                        content: HStack(spacing: 7) {
                            ForEach(Ink.allCases) { ink in
                                swatch(ink)
                            }
                        }
                    )
                }
            }

            SettingsCard(title: "Preview", symbol: "eye") {
                VStack(spacing: 10) {
                    PointerPreviewView(style: model.pointer, ink: sampleInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("Drawn live by the same renderer the overlay uses, at the real chosen size. "
                        + "Shown in red; with “Follow the current ink” the highlight takes the active ink while drawing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The band is part of the hollow shapes only: the Dot is filled and the
    /// Spotlight has no hard edge, so their appearance ignores the thickness
    /// and the control says so instead of silently doing nothing.
    private var bandApplies: Bool {
        switch model.pointer.preset {
        case .dot, .spotlight: false
        default: true
        }
    }

    private var bandDetail: String {
        bandApplies
            ? "Thickness of the band, as a share of the highlight's size."
            : "The \(model.pointer.preset.title) style has no band; thickness is ignored."
    }

    /// The glow is a strength (0...1); the label reads it as one: off at
    /// zero, full at one, a percentage in between.
    private var glowLabel: String {
        let intensity = model.pointer.glowIntensity
        if intensity == 0 { return "Off" }
        if intensity == PointerStyle.glowRange.upperBound { return "Full" }
        return "\(Int((intensity * 100).rounded())) %"
    }

    private var colourMode: Binding<ColourMode> {
        Binding(
            get: {
                if case .fixed = model.pointer.colorSource { return .fixed }
                return .followInk
            },
            set: { mode in
                switch (mode, model.pointer.colorSource) {
                case (.followInk, _):
                    model.pointer.colorSource = .ink
                case (.fixed, .fixed(let ink)):
                    model.pointer.colorSource = .fixed(ink)
                case (.fixed, _):
                    model.pointer.colorSource = .fixed(.red)
                }
            }
        )
    }

    /// One ink as a round swatch; the chosen one carries an accent ring.
    private func swatch(_ ink: Ink) -> some View {
        Button {
            model.pointer.colorSource = .fixed(ink)
        } label: {
            Circle()
                .fill(Color(cgColor: ink.cgColor()))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle().strokeBorder(Color(nsColor: .separatorColor))
                )
                .overlay {
                    if case .fixed(let chosen) = model.pointer.colorSource, chosen == ink {
                        Circle().strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 2)
                            .padding(-3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ink.displayName) colour")
    }
}

// MARK: - Capture

/// Capture destination and format (T11/S6), wired to the delivery tail the
/// overlay's hotkey and toolbar capture actually use: clipboard behaves
/// exactly as before (PNG+TIFF on the pasteboard), a folder writes the file
/// named by `CapturePreference.fileName(at:)` in the chosen format and the
/// in-overlay pill says where it went.
private struct CapturePane: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        VStack(spacing: 16) {
            PaneHeader(title: "Capture", subtitle: "How captures are encoded and where they go.")

            SettingsCard(title: "Destination", symbol: "tray.full") {
                SettingRow(
                    title: "Capture goes to",
                    content: Picker("", selection: destinationSelection) {
                        Text("Clipboard").tag(0)
                        Text("Folder").tag(1)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                )
                if case .folder(let path) = model.capture.destination {
                    SettingRow(
                        title: "Folder",
                        detail: path,
                        content: Button("Choose…") { chooseFolder() }
                    )
                    Text(
                        "The capture is written into this folder in the chosen format and its in-overlay "
                            + "confirmation names the file; the corner card still shows it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        "The capture lands on the pasteboard as PNG and TIFF, ready to paste into "
                            + "another app, and its in-overlay confirmation says so."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "Format", symbol: "photo") {
                SettingRow(
                    title: "File format",
                    detail: "PNG is lossless, JPEG is smaller. The clipboard always carries PNG and TIFF.",
                    content: Picker("", selection: $model.capture.format) {
                        ForEach(CaptureFormat.allCases, id: \.self) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .disabled(isClipboard)
                )
                if isClipboard {
                    Text("The clipboard carries PNG and TIFF only; the format applies to folder saves.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "File name", symbol: "doc.text") {
                SettingRow(
                    title: "Name prefix",
                    detail: "Letters, numbers, hyphen, underscore and dot. Anything else falls back to “Stare”.",
                    content: TextField("", text: $model.capture.fileNamePrefix)
                        .frame(width: 180)
                )
                HStack(spacing: 6) {
                    Text("Files are named like")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(exampleName)
                        .font(.caption.monospaced())
                }
            }
        }
    }

    private var isClipboard: Bool {
        if case .folder = model.capture.destination { return false }
        return true
    }

    /// `CaptureDestination` is a value with an associated path, not a picker
    /// tag, so the picker speaks in indices and the set branch carries a path.
    private var destinationSelection: Binding<Int> {
        Binding(
            get: {
                if case .folder = model.capture.destination { return 1 }
                return 0
            },
            set: { newValue in
                if newValue == 1 {
                    let path: String
                    if case .folder(let existing) = model.capture.destination {
                        path = existing
                    } else {
                        path = "~/Documents"
                    }
                    model.capture.destination = .folder(path: path)
                } else {
                    model.capture.destination = .clipboard
                }
            }
        )
    }

    private var folderPath: String {
        if case .folder(let path) = model.capture.destination { return path }
        return "~/Documents"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath, isDirectory: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.capture.destination = .folder(path: url.path)
        }
    }

    /// One sample name at a fixed instant, so the row does not tick every
    /// second with the clock.
    private var exampleName: String {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 21
        components.hour = 14
        components.minute = 5
        components.second = 33
        let sample = Calendar.current.date(from: components) ?? Date()
        return model.capture.fileName(at: sample)
    }
}

// MARK: - Whiteboard

/// What a new whiteboard opens with (T11/S6): background and page count. The
/// overlay's board creation reads the same blob, so a fresh session really
/// starts with these. Pages beyond 10 are what the core model opens ahead —
/// the stepper names the cap instead of faking a bigger one.
private struct WhiteboardPane: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        VStack(spacing: 16) {
            PaneHeader(title: "Whiteboard", subtitle: "What a new board opens with (⌥⇧W).")

            SettingsCard(title: "Background", symbol: "square.fill") {
                SettingRow(
                    title: "New pages start",
                    // The detail follows the selection: the System entry states
                    // what it resolves to in either appearance (T13/S8).
                    detail: model.whiteboard.background.detail + " ⌘B still flips the page you are on, at any time.",
                    content: Picker("", selection: $model.whiteboard.background) {
                        ForEach(WhiteboardBackgroundChoice.allCases, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                )
            }

            SettingsCard(title: "Pages", symbol: "square.grid.2x2") {
                Stepper(
                    "Opens with \(model.whiteboard.pagesOnOpen) \(model.whiteboard.pagesOnOpen == 1 ? "page" : "pages")",
                    value: $model.whiteboard.pagesOnOpen,
                    in: WhiteboardDefaults.pageRange
                )
                Text(
                    "Up to \(WhiteboardDefaults.pageRange.upperBound) pages are opened ahead. Going past the last one with › "
                        + "keeps creating empty pages, as before."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Permissions

/// The Screen Recording permission, shown live through the shared permission
/// model and the T5 client.
private struct PermissionsPane: View {
    @ObservedObject var permission: PermissionProbe

    var body: some View {
        VStack(spacing: 16) {
            PaneHeader(title: "Permissions", subtitle: "What Stare needs from macOS.")

            SettingsCard(title: "Screen Recording", symbol: "lock.shield") {
                HStack(spacing: 12) {
                    StatusDot(state: permission.access)
                    VStack(alignment: .leading, spacing: 6) {
                        SettingRow(
                            title: permission.access.title,
                            detail: permission.access.detail,
                            content: HStack(spacing: 8) {
                                Button("Refresh") { permission.refresh() }
                                Button("Open System Settings…") { permission.openSettings() }
                            }
                        )
                        if permission.access == .grantedPendingRestart {
                            Label(
                                "Quit and reopen Stare to finish granting the permission.",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                }
                .onAppear { permission.refresh() }
            }
        }
    }
}

// MARK: - About

/// Identity only: the app exposes no web or support links to mirror, so the
/// pane shows the mark, name, version and one description line.
private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 16) {
            PaneHeader(title: "About", subtitle: "Draw over your screen, together.")

            SettingsCard(title: "Stare", symbol: "app") {
                HStack(alignment: .top, spacing: 14) {
                    AppMark(size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stare")
                            .font(.title3.weight(.semibold))
                        Text("Version \(AppVersion.short)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Stare draws over your screen and captures it with your marks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
}
