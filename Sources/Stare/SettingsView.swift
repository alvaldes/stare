import AppKit
import SwiftUI
import StareCore
import UniformTypeIdentifiers

/// The groups the sidebar is divided into, in sidebar order. They are the
/// product's objects, not the order the preferences happened to be added.
enum SettingsGroup: String, CaseIterable, Identifiable {
    case capture, draw, pointer, board, system

    var id: Self { self }

    var title: String {
        switch self {
        case .capture: "Capture"
        case .draw: "Draw"
        case .pointer: "Pointer"
        case .board: "Board"
        case .system: "System"
        }
    }

    /// The areas in this group, in the order they appear here.
    var areas: [SettingsArea] {
        SettingsArea.allCases.filter { $0.group == self }
    }
}

/// The areas of the Settings window, in sidebar order: one object per area,
/// and a group as the heading over it.
enum SettingsArea: String, CaseIterable, Identifiable {
    // Capture
    case capture
    // Draw
    case overlay, tools, bar
    // Pointer
    case marker
    // Board
    case whiteboard
    // System
    case shortcuts, general, permissions, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .overlay: "Overlay"
        case .tools: "Tools"
        case .bar: "Bar"
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
        case .overlay: "rectangle.dashed"
        case .tools: "pencil.tip"
        case .bar: "menubar.rectangle"
        case .shortcuts: "keyboard"
        case .marker: "cursorarrow.rays"
        case .capture: "camera.viewfinder"
        case .whiteboard: "rectangle.on.rectangle"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }

    var group: SettingsGroup {
        switch self {
        case .capture: .capture
        case .overlay, .tools, .bar: .draw
        case .marker: .pointer
        case .whiteboard: .board
        case .shortcuts, .general, .permissions, .about: .system
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
        // The shell is the one place that knows the sidebar's width, so it is
        // the one place that turns the window into a cards width for the pane.
        GeometryReader { proxy in
            HStack(spacing: 0) {
                sidebar
                    // The ring belongs to the keyboard, not to the selection
                    // (S3): on open the selected row is also the window's
                    // first responder, and macOS draws a focus ring around
                    // what reads as a selected row. It stays off until the
                    // first Tab.
                    .focusEffectDisabled(!keyboardNavigationStarted)
                Divider()
                Self.pane(
                    for: area,
                    width: cardsWidth(in: proxy.size.width),
                    model: model,
                    permission: permission
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear { installTabMonitor() }
        .onDisappear { removeTabMonitor() }
    }

    // MARK: Focus ring (S3)

    /// Whether the user has started moving through Settings with Tab. Until
    /// then the sidebar draws no focus ring, because the window's first
    /// responder being the selected row is not a keyboard decision.
    @State private var keyboardNavigationStarted = false
    /// The Tab watcher: removed with the window, so a closed Settings leaves
    /// nothing behind.
    @State private var tabMonitor: Any?

    private func installTabMonitor() {
        guard tabMonitor == nil else { return }
        tabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 48 {
                keyboardNavigationStarted = true
            }
            return event
        }
    }

    private func removeTabMonitor() {
        if let tabMonitor { NSEvent.removeMonitor(tabMonitor) }
        tabMonitor = nil
    }

    /// What a pane's cards get: the window, less the sidebar and a divider,
    /// less the pane's own padding.
    private func cardsWidth(in totalWidth: CGFloat) -> CGFloat {
        max(0, totalWidth - SettingsMetrics.sidebarWidth - 1 - SettingsMetrics.panePadding * 2)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                AppMark(size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Stare")
                        .font(.system(size: 15, weight: .bold))
                    Text("Version \(AppVersion.short)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            ForEach(SettingsGroup.allCases) { group in
                Text(group.title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 3)
                ForEach(group.areas) { area in
                    sidebarButton(for: area)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: SettingsMetrics.sidebarWidth)
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

    /// The pane content for an area — header, stage and cards, each pane its
    /// own scroll container. The selftest renders each pane directly
    /// (`renderSettings`), so the switch lives here for one writer.
    @ViewBuilder
    static func pane(
        for area: SettingsArea,
        width: CGFloat,
        model: PreferencesModel,
        permission: PermissionProbe
    ) -> some View {
        switch area {
        case .general: GeneralPane(model: model, cardsWidth: width)
        case .overlay: OverlayPane(model: model, cardsWidth: width)
        case .tools: ToolsPane(model: model, cardsWidth: width)
        case .bar: BarPane(model: model, cardsWidth: width)
        case .shortcuts: ShortcutsPane(model: model, cardsWidth: width)
        case .marker: MarkerPane(model: model, cardsWidth: width)
        case .capture: CapturePane(model: model, cardsWidth: width)
        case .whiteboard: WhiteboardPane(model: model, cardsWidth: width)
        case .permissions: PermissionsPane(permission: permission)
        case .about: AboutPane()
        }
    }
}

// MARK: - Overlay

/// What drawing over the screen does: the frame that arms it, the displays it
/// reaches, and how long a laser mark lives. These rode along inside General
/// until the settings grew enough for each object to own a pane.
private struct OverlayPane: View {
    @ObservedObject var model: PreferencesModel
    let cardsWidth: CGFloat

    var body: some View {
        SettingsPane(
            title: "Overlay",
            subtitle: "What drawing over the screen does, and where it reaches."
        ) {
            SettingsColumns(width: cardsWidth, left: {
                VStack(spacing: SettingsMetrics.cardSpacing) {
                    drawingCard
                    displaysCard
                }
            }, right: {
                VStack(spacing: SettingsMetrics.cardSpacing) {
                    laserCard
                }
            })
        }
    }

    private var drawingCard: some View {
        SettingsCard(title: "Drawing", symbol: "pencil.tip") {
            SettingRow(
                title: "Show drawing frame",
                detail: "A thin frame in the active ink marks every display that will take a mark.",
                content: Toggle("", isOn: $model.showArmedFrame)
                    .labelsHidden()
            )
            SettingRow(
                title: "Keep marks and pages",
                detail: "What is drawn and the whiteboard pages survive closing Stare or leaving a mode, until the Mac restarts. Turning it off discards what was stored.",
                content: Toggle("", isOn: $model.persistsSession)
                    .labelsHidden()
            )
        }
    }

    private var displaysCard: some View {
        SettingsCard(title: "Displays", symbol: "display.2") {
            SettingRow(
                title: "Draw on",
                content: Picker("", selection: $model.scope) {
                    ForEach(OverlayScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            )
            SettingRow(
                title: "Open the palette",
                content: Picker("", selection: $model.palettePlacement) {
                    ForEach(PalettePlacement.allCases, id: \.self) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            )
            Text("Marking every display is the default; the palette follows the pointer unless told otherwise.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var laserCard: some View {
        SettingsCard(title: "Laser", symbol: "cursor.rays") {
            SettingRow(
                title: "Laser lasts",
                content: Picker("", selection: $model.laserLifetime) {
                    ForEach(LaserLifetime.allCases, id: \.self) { lifetime in
                        Text(lifetime.title).tag(lifetime)
                    }
                }
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            )
            Text("Laser marks fade out and never appear in a capture.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Bar

/// The bar: where it docks, and which tools it carries (T6/S5). The live bar is
/// the pane's stage — the real `ToolbarView`, not a mock — so the order the
/// organiser shows is the order the overlay draws.
/// Internal, not private, so the tests can instantiate the pane and drive its
/// real drop handlers against a real `PreferencesModel` (T4/S4): the handlers
/// and the draft they write are the organiser's behaviour.
struct BarPane: View {
    @ObservedObject var model: PreferencesModel
    let cardsWidth: CGFloat

    // MARK: Toolbar edge validity (T3/S4)

    /// The orientation picker's binding: flipping the orientation may leave
    /// the stored border invalid for the new shape (a top dock on a vertical
    /// column), so the same fallback the decode applies re-docks the border on
    /// the new orientation's default edge at once — the stored pair is never
    /// left inconsistent, and the bar moves to that edge through the panel's
    /// own re-dock path.
    private var toolbarOrientationSelection: Binding<ToolbarOrientation> {
        Binding(
            get: { model.toolbarOrientation },
            set: { orientation in
                model.toolbarOrientation = orientation
                model.toolbarBorder = model.toolbarBorder.validated(for: orientation)
            }
        )
    }

    // MARK: Toolbar organiser (T6/S5)

    /// A detached editor state the live preview runs on: the real bar view
    /// on the current orientation, border, tool and ink. The organiser keeps
    /// it in step with the model below; it never touches the app's own
    /// state.
    @StateObject private var toolbarPreviewState = EditorState()
    /// The bar's measured item sizes, picked up from the real bar view's
    /// own measurement, and the pool chips' measured sizes.
    @State private var poolSizes: [Tool: CGSize] = [:]

    /// The bar's size before scaling, measured from the bar itself the first
    /// time it lays out: what the fit-to-width factor is computed from.
    @State private var barNaturalSize: CGSize = .zero

    /// How much the preview shrinks to sit inside the stage: never up, only
    /// down, so a narrow window still shows the whole bar (S2).
    private var barPreviewScale: CGFloat {
        let available = cardsWidth - SettingsMetrics.stageChrome
        guard barNaturalSize.width > 0, available > 0 else { return 1 }
        return min(1, available / barNaturalSize.width)
    }

    /// The bar's own width and height, reported by the bar in the stage.
    private struct ToolbarPreviewSizeKey: PreferenceKey {
        static var defaultValue: CGSize { .zero }
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            let next = nextValue()
            if next != .zero { value = next }
        }
    }

    /// The measured chip sizes the pool's drop targets read.
    private struct ToolbarPoolChipSizeKey: PreferenceKey {
        static var defaultValue: [Tool: CGSize] { [:] }
        static func reduce(
            value: inout [Tool: CGSize],
            nextValue: () -> [Tool: CGSize]
        ) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }

    /// The drop delegate the pool's end zone uses: a tool lands at the end
    /// of the pool, and a placed separator comes back off the bar — the one
    /// way out for a placed separator. The pool never stores separators as
    /// pool items.
    private struct ToolbarPoolEndDropDelegate: DropDelegate {
        let onDrop: @MainActor (ToolbarLayoutItem) -> Void

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
            // The shared main-actor hop (S5, verifier finding): the
            // completion of `loadObject` is off the main thread and this
            // drop's handler mutates the `@MainActor` `PreferencesModel`.
            ToolbarOrganiserHooks.deliverPayload(of: provider) { payload in
                onDrop(payload)
            }
            return true
        }
    }

    private func syncToolbarPreview() {
        toolbarPreviewState.toolbarTools = model.toolbarTools
        // The preview always renders horizontal (S1): a vertical bar inside the
        // stage distorted the pane and hid most of the tools, so the preview
        // answers what is on the bar and the orientation picker answers the
        // rest. Nothing else of the real bar's state changes here.
        toolbarPreviewState.toolbarOrientation = .horizontal
        toolbarPreviewState.toolbarBorder = model.toolbarBorder
        toolbarPreviewState.tool = model.tool
        toolbarPreviewState.ink = model.ink
    }

    /// The pool: the tools that are not on the bar, in the pool's order,
    /// plus the separator — always available, never stored, one drop adds
    /// one. Chips drag into the bar and reorder among themselves by their
    /// halves; the dashed zone at the end always accepts a drop at the end
    /// of the pool, even when it is empty.
    private var toolbarPoolRow: some View {
        HStack(spacing: 8) {
            ForEach(model.toolbarTools.pool) { tool in
                toolbarPoolChip(tool)
            }
            toolbarPoolSeparatorChip
            toolbarPoolEndZone
        }
        .onPreferenceChange(ToolbarPoolChipSizeKey.self) { poolSizes = $0 }
    }

    private func toolbarPoolChip(_ tool: Tool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: tool.symbolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(tool.displayName)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onDrag { NSItemProvider(object: ToolbarLayoutItem.tool(tool).identifier as NSString) }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ToolbarPoolChipSizeKey.self, value: [tool: geo.size])
            }
        )
        .onDrop(of: [UTType.plainText], delegate: ToolbarSlotDropDelegate(
            target: .tool(tool),
            size: poolSizes[tool] ?? CGSize(width: 80, height: 26),
            axisVertical: false,
            onDrop: { target, edge, payload in
                handlePoolDrop(target: target, edge: edge, payload: payload)
            }
        ))
        .help(Text(verbatim: "Drag \(tool.displayName) onto the bar"))
    }

    /// The separator chip: always available to drag onto the bar; it never
    /// takes drops, because separators do not stack in the pool.
    private var toolbarPoolSeparatorChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Separator")
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onDrag { NSItemProvider(object: ToolbarLayoutItem.separator.identifier as NSString) }
        .help(Text(verbatim: "Drag a separator onto the bar"))
    }

    /// The always-open end of the pool: guides a drop when there is nothing
    /// else to drop onto, landing the tool at the end of the pool.
    private var toolbarPoolEndZone: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .medium))
            Text("Drop to pool")
                .font(.system(size: 10))
        }
        .foregroundStyle(.tertiary)
        .frame(minWidth: 72, minHeight: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(Color.secondary.opacity(0.35))
        )
        .onDrop(of: [UTType.plainText], delegate: ToolbarPoolEndDropDelegate { payload in
            handlePoolEndDrop(payload: payload)
        })
    }

    // MARK: Toolbar organiser drops (T6/S5)

    /// Handles a drop on the bar: a payload already on the bar reorders in
    /// place, a payload from the pool is inserted — a tool comes out of the
    /// pool at that very spot, a separator joins the bar. The destination
    /// slot is the target item's position plus the drop's side.
    /// Internal (T4/S4) so the tests drive the real handler on a real model.
    func handleBarDrop(target: ToolbarLayoutItem, edge: ToolbarOrganiserHooks.Edge, payload: ToolbarLayoutItem) {
        let layout = model.toolbarTools
        guard let targetIndex = layout.items.firstIndex(of: target) else { return }
        let slot = targetIndex + (edge == .after ? 1 : 0)
        if layout.items.contains(payload) {
            // The move index is the insert position in the list as it would
            // be without the item, so a slot the payload itself sits before
            // closes up by one.
            guard let currentIndex = layout.items.firstIndex(of: payload) else { return }
            let adjusted = currentIndex < slot ? slot - 1 : slot
            model.toolbarTools = layout.moving(payload, to: adjusted)
        } else {
            model.toolbarTools = layout.inserting(payload, at: slot)
        }
    }

    /// Handles a drop on a pool chip: a payload already in the pool
    /// reorders, a payload on the bar enters the pool at that very spot, and
    /// a placed separator comes off the bar (T4/S3) — the pool never stores
    /// separators as pool items, so the drop's side lands it nowhere but
    /// off the bar. The bar's first tool cannot leave (T3/S2): the drag-out
    /// refuses on either half of a chip and the draft stays as it was.
    /// Internal (T4/S4) so the tests drive the real handler on a real model.
    func handlePoolDrop(target: ToolbarLayoutItem, edge: ToolbarOrganiserHooks.Edge, payload: ToolbarLayoutItem) {
        let layout = model.toolbarTools
        if case .separator = payload {
            guard layout.items.contains(payload) else { return }
            model.toolbarTools = layout.removing(.separator)
            return
        }
        guard case .tool(let tool) = payload, case .tool(let targetTool) = target else { return }
        guard layout.canLeave(payload) else { return }
        guard let targetIndex = layout.pool.firstIndex(of: targetTool) else { return }
        let slot = targetIndex + (edge == .after ? 1 : 0)
        if layout.pool.contains(tool) {
            let currentIndex = layout.pool.firstIndex(of: tool) ?? layout.pool.count
            let adjusted = currentIndex < slot ? slot - 1 : slot
            model.toolbarTools = layout.movingInPool(tool, to: adjusted)
        } else {
            model.toolbarTools = layout.removing(.tool(tool), intoPoolAt: slot)
        }
    }

    /// Handles a drop on the pool's end zone: a bar tool lands at the end of
    /// the pool and a pool tool moves there, a placed separator comes off
    /// the bar, and the bar's first tool cannot leave (T3/S2) — the drag-out
    /// refuses and the draft stays as it was. Internal (T4/S4) so the tests
    /// drive the real handler on a real model.
    func handlePoolEndDrop(payload: ToolbarLayoutItem) {
        let layout = model.toolbarTools
        guard layout.canLeave(payload) else { return }
        if case .tool(let tool) = payload {
            if layout.items.contains(payload) {
                model.toolbarTools = layout.removing(.tool(tool))
            } else if layout.pool.contains(tool) {
                model.toolbarTools = layout.movingInPool(tool, to: layout.pool.count)
            }
        } else if layout.items.contains(payload) {
            model.toolbarTools = layout.removing(.separator)
        }
    }

    // MARK: Pane

    var body: some View {
        StageSettingsPane(
            title: "Bar",
            subtitle: "The tools palette, where it docks, and what it carries."
        ) {
            // The pool is the other half of the bar (S1): it sits in the pinned
            // region directly under the preview, so dragging between the two
            // never needs a scroll. Placement — which is about where the bar
            // docks, not what it carries — scrolls below them.
            VStack(spacing: SettingsMetrics.cardSpacing) {
                toolbarStage
                poolCard
            }
        } cards: {
            VStack(spacing: SettingsMetrics.cardSpacing) {
                placementCard
            }
            // The bar is the stage above; the cards beside it are ordinary
            // rows, so they take the same single-column cap as every other
            // non-columnar pane.
            .settingsSingleColumn()
        }
    }

    /// The stage: the bar itself, on the draft layout. Every item is a drag
    /// source and a two-sided drop target, and the pool below is the other half
    /// of the same draft. It renders horizontal whatever the bar's orientation
    /// is (S1), and it is fitted to the stage's width (S2) instead of
    /// scrolling: the whole bar stays visible, because a preview that cuts the
    /// tools it is meant to show answers nothing. Scaling is a transform, so
    /// every item keeps its drag hooks.
    private var toolbarStage: some View {
        SettingsStage(
            label: "On the bar",
            note: "Drag a tool out of the pool onto the bar."
        ) {
            ToolbarView(
                state: toolbarPreviewState,
                onUndo: {}, onRedo: {}, onClear: {}, onDone: {},
                toolItems: model.toolbarTools.items,
                organiser: ToolbarOrganiserHooks(
                    dragProvider: { NSItemProvider(object: $0.identifier as NSString) },
                    drop: { target, edge, payload in
                        handleBarDrop(target: target, edge: edge, payload: payload)
                    },
                    fixed: { item in !model.toolbarTools.canLeave(item) }
                )
            )
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ToolbarPreviewSizeKey.self, value: geo.size)
                }
            )
            .scaleEffect(barPreviewScale, anchor: .center)
            .frame(
                width: max(barNaturalSize.width, 1) * barPreviewScale,
                height: max(barNaturalSize.height, 34) * barPreviewScale
            )
            .onPreferenceChange(ToolbarPreviewSizeKey.self) { size in
                barNaturalSize = size
            }
            .padding(.vertical, 8)
        }
        // The stage is the preview: it follows the model on every change, and
        // starts in step on appear instead of waiting for the first change.
        .onAppear { syncToolbarPreview() }
        .onReceive(model.$toolbarTools) { _ in syncToolbarPreview() }
        .onReceive(model.$toolbarOrientation) { _ in syncToolbarPreview() }
        .onReceive(model.$toolbarBorder) { _ in syncToolbarPreview() }
        .onReceive(model.$tool) { _ in syncToolbarPreview() }
        .onReceive(model.$ink) { _ in syncToolbarPreview() }
    }

    private var placementCard: some View {
        SettingsCard(title: "Placement", symbol: "rectangle.inset.filled") {
            SettingRow(
                title: "Bar orientation",
                detail: "Horizontal lays the tools in a row; vertical stacks them in one column.",
                content: Picker("", selection: toolbarOrientationSelection) {
                    ForEach(ToolbarOrientation.allCases, id: \.self) { orientation in
                        Text(orientation.title).tag(orientation)
                    }
                }
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            )
            SettingRow(
                title: "Docked edge",
                detail: "The edge of the screen the bar rests at when it has not been dragged.",
                content: Picker("", selection: $model.toolbarBorder) {
                    // Only the edges the chosen orientation can sit on
                    // (T3/S4): horizontal → top/bottom, vertical → left/right.
                    ForEach(ToolbarBorder.validEdges(for: model.toolbarOrientation), id: \.self) { border in
                        Text(border.title).tag(border)
                    }
                }
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            )
            SettingRow(
                title: "Reset position",
                detail: "Puts the bar back where a fresh install opens it, and moves it at once if it is on screen.",
                content: Button("Reset") {
                    ToolbarPanel.requestPositionReset()
                }
            )
            Text("The bar moves to the new edge as soon as you pick, and right-clicking the ⠇⠇ handle always returns it there.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var poolCard: some View {
        SettingsCard(title: "In the pool", symbol: "tray") {
            toolbarPoolRow
            Text("Pool tools keep their shortcuts while off the bar. Drag a chip onto the bar, or a placed separator back onto any pool spot. The bar's first tool cannot leave — the preview dims it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - General

/// Startup and updates: what an app-level General pane owns now that drawing,
/// the displays and the bar have panes of their own.
private struct GeneralPane: View {
    @ObservedObject var model: PreferencesModel
    let cardsWidth: CGFloat
    /// The real login-item service, re-read every time the pane appears; the
    /// pane never caches a status the system has since changed.
    @StateObject private var login = LaunchAtLogin()

    var body: some View {
        SettingsPane(title: "General", subtitle: "How Stare starts and keeps itself current.") {
            VStack(spacing: SettingsMetrics.cardSpacing) {
                startupCard
                updatesCard
            }
            .settingsSingleColumn()
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
                .frame(width: 160, alignment: .trailing)
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

/// The starting ink and the per-tool shortcuts (T8/S6). Every control writes
/// through the one preferences blob. The bar itself has its own pane now, so
/// its Reset control lives there instead of riding along here.
private struct ToolsPane: View {
    @ObservedObject var model: PreferencesModel
    let cardsWidth: CGFloat
    /// The tool whose shortcut is being captured, if any.
    @State private var recordingTool: Tool?
    /// The last refusal, shown instead of a silent no-op.
    @State private var notice: String?

    var body: some View {
        SettingsPane(title: "Tools", subtitle: "The ink you start with, the tool keys and the palette.") {
            VStack(spacing: SettingsMetrics.cardSpacing) {
                inkCard
                toolShortcutsCard
            }
            .settingsSingleColumn()

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

    private var inkCard: some View {
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
    }

    private var toolShortcutsCard: some View {
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
    let cardsWidth: CGFloat
    @State private var recording: HotkeyAction?
    @State private var notice: String?

    var body: some View {
        SettingsPane(title: "Shortcuts", subtitle: "The system-wide shortcuts Stare answers to.") {
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
            .settingsSingleColumn()

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
    let cardsWidth: CGFloat
    /// Representative ink for the preview and the swatch-less case: the real
    /// highlight follows the active ink while drawing.
    private let sampleInk: Ink = .red

    /// Where the highlight's colour comes from, as the picker sees it.
    private enum ColourMode {
        case followInk, fixed
    }

    var body: some View {
        StageSettingsPane(
            title: "Pointer Highlight",
            subtitle: "The highlight that follows the pointer (⌥⇧M)."
        ) {
            pointerStage
        } cards: {
            SettingsColumns(width: cardsWidth, left: {
                VStack(spacing: SettingsMetrics.cardSpacing) {
                    shapeCard
                    strokeCard
                }
            }, right: {
                VStack(spacing: SettingsMetrics.cardSpacing) {
                    motionCard
                    colourCard
                }
            })
        }
    }

    /// The pane's stage (S4): the live preview sits pinned above the cards
    /// instead of ending the pane below them, so every size and colour change
    /// is visible the moment it is made. The tiles keep the 168-point canvas
    /// the preview has always shown.
    private var pointerStage: some View {
        SettingsStage(
            label: "Live preview",
            note: "Same renderer the overlay uses. Too large a size is scaled down."
        ) {
            PointerPreviewView(style: model.pointer, ink: sampleInk)
        }
    }

    private var shapeCard: some View {
        SettingsCard(title: "Shape", symbol: "scope") {
            // Under a card called Shape the row repeated the card's name,
            // so the row reads Preset — the named preset it picks.
            SettingRow(
                title: "Preset",
                content: Picker("", selection: $model.pointer.preset) {
                    ForEach(PointerStylePreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 130, alignment: .trailing)
            )
            SettingRow(
                title: "Size",
                content: HStack(spacing: 8) {
                    Slider(value: $model.pointer.size, in: PointerStyle.sizeRange)
                        .frame(width: 130)
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
                        .frame(width: 130)
                    Text("\(Int((model.pointer.bandWidth * 100).rounded())) %")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            )
            Text("The highlight follows the pointer in presentation mode (⌥⇧M) and never takes focus.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var strokeCard: some View {
        SettingsCard(title: "Stroke", symbol: "circle.dashed") {
            SettingRow(
                title: "Border style",
                detail: borderDetail,
                content: Picker("", selection: $model.pointer.borderStyle) {
                    ForEach(PointerBorderStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 130, alignment: .trailing)
                .disabled(!borderApplies)
            )
            SettingRow(
                title: "Opacity",
                detail: "How translucent the whole highlight is, glow included.",
                content: HStack(spacing: 8) {
                    Slider(value: $model.pointer.opacity, in: PointerStyle.opacityRange)
                        .frame(width: 130)
                    Text("\(Int((model.pointer.opacity * 100).rounded())) %")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            )
        }
    }

    private var motionCard: some View {
        SettingsCard(title: "Motion", symbol: "sparkles") {
            SettingRow(
                title: "Click animation",
                detail: "What a click does: it grows, or it turns.",
                content: Picker("", selection: $model.pointer.clickAnimation) {
                    ForEach(PointerClickAnimation.allCases, id: \.self) { animation in
                        Text(animation.title).tag(animation)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 130, alignment: .trailing)
            )
            SettingRow(
                title: "Glow",
                detail: "Soft halo outside the edge; zero turns it off.",
                content: HStack(spacing: 8) {
                    Slider(value: $model.pointer.glowIntensity, in: PointerStyle.glowRange)
                        .frame(width: 130)
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
        }
    }

    private var colourCard: some View {
        SettingsCard(title: "Colour", symbol: "paintpalette") {
            SettingRow(
                title: "Colour",
                detail: "Either the ink active while drawing, or the highlight's own fixed one.",
                content: Picker("", selection: colourMode) {
                    // Short enough to fit a two-column card: the row's detail
                    // already spells out what each side means.
                    Text("Follow ink").tag(ColourMode.followInk)
                    Text("Fixed").tag(ColourMode.fixed)
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
    }

    /// The band is part of the hollow shapes only: the Dot is filled and the
    /// Spotlight has no hard edge, so their appearance ignores the thickness
    /// and the control says so instead of silently doing nothing. The rhombus
    /// is a band like the ring and the squircle.
    private var bandApplies: Bool {
        switch model.pointer.preset {
        case .dot, .spotlight: false
        case .ring, .squircle, .rhombus: true
        }
    }

    /// A border is drawn only by the banded ring shapes; for the filled dot
    /// and the edge-less spotlight the picker is disabled and says so instead
    /// of pretending to do something.
    private var borderApplies: Bool {
        switch model.pointer.preset {
        case .ring, .squircle, .rhombus: true
        case .dot, .spotlight: false
        }
    }

    private var borderDetail: String? {
        borderApplies
            ? "Solid draws the band filled with one line on the outer edge; dashed turns that line into dashes."
            : "The \(model.pointer.preset.title) style has no border; border style is ignored."
    }

    private var bandDetail: String {
        bandApplies
            ? "Thickness of the band, as a share of size."
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
    let cardsWidth: CGFloat

    var body: some View {
        SettingsPane(title: "Capture", subtitle: "How captures are encoded and where they go.") {
            SettingsColumns(width: cardsWidth, left: {
                VStack(spacing: SettingsMetrics.cardSpacing) {
                    destinationCard
                    formatCard
                }
            }, right: {
                VStack(spacing: SettingsMetrics.cardSpacing) {
                    fileNameCard
                }
            })
        }
    }

    private var destinationCard: some View {
        SettingsCard(title: "Destination", symbol: "tray.full") {
            SettingRow(
                title: "Capture goes to",
                content: Picker("", selection: destinationSelection) {
                    Text("Clipboard").tag(0)
                    Text("Folder").tag(1)
                }
                .labelsHidden()
                .frame(width: 180, alignment: .trailing)
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
    }

    private var formatCard: some View {
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
                .frame(width: 140, alignment: .trailing)
                .disabled(isClipboard)
            )
            if isClipboard {
                Text("The clipboard carries PNG and TIFF only; the format applies to folder saves.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fileNameCard: some View {
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
    let cardsWidth: CGFloat

    var body: some View {
        SettingsPane(title: "Whiteboard", subtitle: "What a new board opens with (⌥⇧W).") {
            SettingsColumns(width: cardsWidth, left: {
                VStack(spacing: SettingsMetrics.cardSpacing) {
                    backgroundCard
                    pagesCard
                }
            }, right: {
                VStack(spacing: SettingsMetrics.cardSpacing) {
                    boardCard
                }
            })
        }
    }

    private var backgroundCard: some View {
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
                .frame(width: 160, alignment: .trailing)
            )
        }
    }

    private var pagesCard: some View {
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

    private var boardCard: some View {
        SettingsCard(title: "Board", symbol: "rectangle.on.rectangle") {
            SettingRow(
                title: "Open the board on",
                // The same values the drawing pane's "Draw on" row uses, so
                // both surfaces speak one language (whiteboard-2/S3).
                content: Picker("", selection: $model.whiteboard.scope) {
                    ForEach(OverlayScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            )
            Text("Every display is the default; the scope applies while the board is open, and a display that leaves it keeps its pages.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SettingRow(
                title: "Show border",
                detail: "The board's own frame, whatever the drawing frame does.",
                content: Toggle("", isOn: $model.whiteboard.showsBorder)
                    .labelsHidden()
            )
        }
    }
}

// MARK: - Permissions

/// The Screen Recording permission, shown live through the shared permission
/// model and the T5 client.
private struct PermissionsPane: View {
    @ObservedObject var permission: PermissionProbe

    var body: some View {
        SettingsPane(title: "Permissions", subtitle: "What Stare needs from macOS.") {
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
                                "Quit and reopen Stare. If it still shows this afterwards, switch Stare off and on in System Settings → Screen Recording.",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                }
                .onAppear { permission.refresh() }
            }
            .settingsSingleColumn()
        }
    }
}

// MARK: - About

/// Identity only: the app exposes no web or support links to mirror, so the
/// pane shows the mark, name, version and one description line.
private struct AboutPane: View {
    var body: some View {
        SettingsPane(title: "About", subtitle: "Draw over your screen, together.") {
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
            .settingsSingleColumn()
        }
    }
}
