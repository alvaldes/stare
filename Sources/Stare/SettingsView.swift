import AppKit
import SwiftUI
import StareCore

/// The areas of the Settings window, in sidebar order.
enum SettingsArea: String, CaseIterable, Identifiable {
    case general, marker, permissions, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .marker: "Pointer Highlight"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .marker: "scope"
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
        case .marker: MarkerPane(model: model)
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

/// Drawing frame, displays and laser — the same settings the old single form
/// carried, now as cards.
private struct GeneralPane: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        VStack(spacing: 16) {
            PaneHeader(title: "General", subtitle: "How Stare draws over the screen.")

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
