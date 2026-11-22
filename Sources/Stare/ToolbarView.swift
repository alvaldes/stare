import AppKit
import SwiftUI
import StareCore
import UniformTypeIdentifiers

/// An action that lives in the palette itself, so the editor needs no second bar.
/// `isSelected` marks it as the palette's one armed item (S6), in the same
/// accent style the tool buttons mark theirs — the crop uses this, copy and
/// save stay plain.
struct ToolbarAction: Identifiable {
    let id = UUID()
    let symbolName: String
    let help: String
    var isSelected: Bool = false
    let handler: () -> Void
}

/// The `⠇⠇` grab handle after the close button (T3/S4). An AppKit view
/// because both actions it owns are window-level: dragging calls the window's
/// own `performDrag` — the same move path the bar's background already has —
/// and right-clicking resets the palette to the anchor the app persists, the
/// path `ToolbarPanel.requestPositionReset()` provides (S12 ties that default
/// to the orientation/border settings later).
private struct ToolbarGripper: NSViewRepresentable {
    func makeNSView(context: Context) -> ToolbarGripperView { ToolbarGripperView() }
    func updateNSView(_ nsView: ToolbarGripperView, context: Context) {}
}

/// The dots the gripper shows (T5/S5), drawn by SwiftUI with the same
/// `Color.secondary` the bar's other items use. The dots used to be drawn by
/// the AppKit view itself with `NSColor.secondaryLabelColor`: measured over
/// the bar's material the AppKit fill stayed near-constant across system
/// appearances (≈128/255 in light, ≈124/255 in dark) while the SwiftUI glyphs
/// tracked the appearance (≈120 light, ≈151 dark) — the hosted NSView's draw
/// does not receive the vibrancy treatment the material gives the SwiftUI
/// content, so in light the dots washed out on the white bar and in dark they
/// went dim. Drawing them in SwiftUI puts them in the same colour resolution
/// path as every glyph, which the render test pins in both appearances.
private struct ToolbarGripperDots: View {
    var body: some View {
        GeometryReader { geo in
            // Centred 2×3 grid: the same origin math the view's old `draw`
            // used, expressed as offsets from the centre of the hit area.
            let pitchX: CGFloat = 6
            let pitchY: CGFloat = 5
            let dot: CGFloat = 3
            let gridWidth = CGFloat(ToolbarGripperSpec.dotColumns - 1) * pitchX + dot
            let gridHeight = CGFloat(ToolbarGripperSpec.dotRows - 1) * pitchY + dot
            ZStack(alignment: .center) {
                ForEach(0..<ToolbarGripperSpec.dotColumns, id: \.self) { column in
                    ForEach(0..<ToolbarGripperSpec.dotRows, id: \.self) { row in
                        Circle()
                            .fill(.secondary)
                            .frame(width: dot, height: dot)
                            .offset(
                                x: CGFloat(column) * pitchX - (gridWidth - dot) / 2,
                                y: CGFloat(row) * pitchY - (gridHeight - dot) / 2
                            )
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// The handle itself: a hit area big enough to grab, over the SwiftUI-drawn
/// `ToolbarGripperDots` (T5/S5) — the view itself draws nothing, so the dots
/// render through the same appearance path as the bar's other glyphs.
final class ToolbarGripperView: NSView {
    /// Whether the gripper's own drag is running (T2/S3). While it does, the
    /// cursor is the closed hand — the same pair the board's pan shows.
    private(set) var isDragging = false

    /// The cursor the gripper shows while hovered (T2/S3): an open hand, or a
    /// closed one while the drag runs. Every cursor path below serves this
    /// one answer, so hover and drag can never disagree.
    var hoverCursor: NSCursor { isDragging ? .closedHand : .openHand }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = ToolbarGripperSpec.tooltip
        setAccessibilityElement(true)
        setAccessibilityLabel(ToolbarGripperSpec.tooltip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ToolbarGripperView is created in code only")
    }

    override var intrinsicContentSize: NSSize {
        // Comfortably wider than the dots themselves, so the whole area grabs.
        NSSize(width: 16, height: 26)
    }

    override func mouseDown(with event: NSEvent) {
        beginDrag()
        window?.performDrag(with: event)
        endDrag()
    }

    override func rightMouseDown(with event: NSEvent) {
        ToolbarPanel.requestPositionReset()
    }

    /// Opens the drag (T2/S3): the closed hand takes over, exactly like the
    /// board's pan. Split from `mouseDown` so the selftest and the unit tests
    /// can pin the hand pair without performing a real window drag.
    func beginDrag() {
        isDragging = true
        NSCursor.closedHand.set()
    }

    /// Closes the drag (T2/S3): the pointer is over the gripper still after
    /// the move, so the open hand returns — never a stale closed hand or
    /// arrow left by the bar.
    func endDrag() {
        isDragging = false
        NSCursor.openHand.set()
    }

    /// The drag ends because the view is going away (T2/S3): forget the drag
    /// state and hand the cursor back as the neutral arrow — whatever sits
    /// under the bar (overlay or board) owns the real cursor next and
    /// re-asserts it on its first pointer event.
    func abandonDrag() {
        isDragging = false
        NSCursor.arrow.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { abandonDrag() }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: hoverCursor)
    }

    /// The gripper's frame in window coordinates (T2/S3): what the bar's
    /// cursor arbitration reads to stand its hand down from over this rect.
    var frameInWindow: NSRect {
        convert(bounds, to: nil)
    }

    // MARK: Bar cursor arbitration (T6/S6)

    /// The cursor the bar shows for a pointer at `point` in window
    /// coordinates (T6/S6): the gripper's hand pair inside the gripper's
    /// frame, the arrow everywhere else on the bar. This is the one decision
    /// the overlay's cursor monitor applies (S6), split out here so the tests
    /// pin the arbitration without a live pointer over the panel.
    static func barCursor(at point: CGPoint, in window: NSWindow) -> NSCursor {
        locate(in: window)?.cursor(atWindowPoint: point) ?? .arrow
    }

    /// The answer for one pointer position over this bar: the hover pair over
    /// the gripper's own rect, the arrow off it. An instance method so the
    /// drag state is read live — closed hand while the drag runs.
    func cursor(atWindowPoint point: CGPoint) -> NSCursor {
        frameInWindow.contains(point) ? hoverCursor : .arrow
    }

    /// The gripper subview in `window`'s content tree, if present (T6/S6):
    /// the representable nests it below SwiftUI's intermediate views, so the
    /// lookup walks the tree — shallow, and only ever run when the pointer
    /// moves over the bar. Mirrors the hosting view's own private lookup.
    static func locate(in window: NSWindow) -> ToolbarGripperView? {
        guard var stack = window.contentView.map({ [$0] }) else { return nil }
        while let view = stack.popLast() {
            if let gripper = view as? ToolbarGripperView { return gripper }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    /// `.activeAlways` mirrors the overlay's own cursor discipline: the bar
    /// floats above other apps, so its pointers must hold while Stare is not
    /// the active one, which cursor rectangles alone do not allow.
    override func cursorUpdate(with event: NSEvent) {
        hoverCursor.set()
    }
}

/// The Settings organiser's hooks on the real bar (T6/S5). The preview
/// embeds `ToolbarView` itself — not a mock — and installs these hooks so
/// every placeable item becomes a drag source and a two-sided drop target:
/// what the user arranges is the bar. The plain drawing bar installs
/// nothing and behaves exactly as before.
struct ToolbarOrganiserHooks {
    /// The side of the target item a drop landed on.
    enum Edge { case before, after }

    /// Builds the drag payload for `item`: its stable identifier as plain
    /// text (`ToolbarLayoutItem.identifier`). The payload names the item, never a
    /// slot, so both zones of the organiser decode the same wire format and
    /// a drag can start in the pool and land on the bar or the other way
    /// round, and it stays meaningful however the draft changes while the
    /// drag is in flight. Plain text because an `NSString` provider is the
    /// format both the drag source and every drop target read without
    /// registering a custom UTType.
    var dragProvider: (ToolbarLayoutItem) -> NSItemProvider
    /// Handles a drop of `payload` on the given side of `target`. Main-actor
    /// typed on purpose (S5, verifier finding): the drop path hops to the
    /// main actor before it delivers anything, so the handlers here can
    /// mutate the `@MainActor` `PreferencesModel` without a second hop.
    var drop: @MainActor (ToolbarLayoutItem, Edge, ToolbarLayoutItem) -> Void

    /// The single payload hop (S5, verifier finding): the completion of
    /// `NSItemProvider.loadObject` is NOT the main thread — pinned by
    /// `SettingsOrganiserDropTests.testALoadObjectCompletionCallsBackOffTheMainThread`
    /// — and everything downstream of it touches the `@MainActor`
    /// `PreferencesModel`. Applying a drop straight from the completion ran
    /// the read-modify-write off main, where two quick drops could read the
    /// same draft and lose one, and `persist()` hit UserDefaults off main.
    /// The completion therefore only decodes the payload; the item is
    /// delivered on the main actor, always, so the applications serialize
    /// and both land.
    static func deliverPayload(
        of provider: NSItemProvider,
        onMain deliver: @escaping @MainActor (ToolbarLayoutItem) -> Void
    ) {
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String, let payload = ToolbarLayoutItem(identifier: raw) else { return }
            Task { @MainActor in deliver(payload) }
        }
    }
}

/// The measured sizes of the bar's items for the organiser: a drop's side
/// needs the item's own midpoint, and the background GeometryReader passes
/// it up to the bar that hosts the drop targets.
private struct ToolbarItemSizeKey: PreferenceKey {
    static var defaultValue: [ToolbarLayoutItem: CGSize] { [:] }
    static func reduce(
        value: inout [ToolbarLayoutItem: CGSize],
        nextValue: () -> [ToolbarLayoutItem: CGSize]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// The drop delegate one organiser slot uses: the drop's position inside the
/// item decides the side — before its midpoint, after it. The payload is the
/// item's stable identifier, decoded the same way in every zone.
struct ToolbarSlotDropDelegate: DropDelegate {
    let target: ToolbarLayoutItem
    let size: CGSize
    let axisVertical: Bool
    let onDrop: @MainActor (ToolbarLayoutItem, ToolbarOrganiserHooks.Edge, ToolbarLayoutItem) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
        let centre = axisVertical ? size.height / 2 : size.width / 2
        let along = axisVertical ? info.location.y : info.location.x
        let edge: ToolbarOrganiserHooks.Edge = along < centre ? .before : .after
        dropPayload(from: provider, edge: edge)
        return true
    }

    /// Decodes `provider`'s payload and delivers it through the organiser's
    /// main-actor hop (see `ToolbarOrganiserHooks.deliverPayload`). Split
    /// from `performDrop` — `DropInfo` cannot be constructed by anything but
    /// SwiftUI, so this seam is how the tests fire a real drop's payload path
    /// from a background queue.
    func dropPayload(from provider: NSItemProvider, edge: ToolbarOrganiserHooks.Edge) {
        ToolbarOrganiserHooks.deliverPayload(of: provider) { payload in
            self.onDrop(self.target, edge, payload)
        }
    }
}

struct ToolbarView: View {
    @ObservedObject var state: EditorState
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onClear: () -> Void
    let onDone: () -> Void
    var extraActions: [ToolbarAction] = []
    /// Whiteboard page controls (T6): shown while the board is open and the
    /// callbacks exist, hidden in the plain overlay and the editor bar.
    var onPreviousPage: (() -> Void)? = nil
    var onNextPage: (() -> Void)? = nil
    /// Whiteboard delete affordance (T12/S9): nil hides it (the plain overlay
    /// and the editor bar never show it). Disabled while one page remains,
    /// since the board can never go empty.
    var onDeletePage: (() -> Void)? = nil
    /// The tools the bar offers. Nil (the default) means the drawing toolbar:
    /// the section follows the persisted tool layout (T8/S10) mirrored in the
    /// state, so a Settings change re-lays the bar live. A non-nil value is a
    /// fixed palette — the capture editor passes the tools that can work over
    /// a still image, so no dead button is shown and the configurable layout
    /// never touches that surface.
    var toolGroups: [[Tool]]? = nil
    /// The exact items the bar draws (T6/S5): nil (the default) means the
    /// drawing toolbar follows the persisted layout's item list mirrored in
    /// the state, so a Settings change re-lays the bar live. A non-nil value
    /// pins the items — the Settings organiser's live preview passes the
    /// draft, so what the user arranges is what this bar shows.
    var toolItems: [ToolbarLayoutItem]? = nil
    /// The Settings organiser hooks (T6/S5): nil keeps the bar inert, exactly
    /// as every surface outside the organiser needs.
    var organiser: ToolbarOrganiserHooks? = nil
    /// The organiser's measured item sizes, for the drop targets' midpoints.
    @State private var itemSizes: [ToolbarLayoutItem: CGSize] = [:]

    /// The item list the bar draws (T6/S5): the organiser's draft when one
    /// is passed, or the persisted layout's items — the stored order with
    /// separators in place, no gaps, no phantom items, nothing duplicated.
    /// Exposed so the tests and the selftest can pin that the rendered bar
    /// follows the configured layout without poking SwiftUI internals.
    var toolSection: [ToolbarLayoutItem] {
        toolItems ?? state.toolbarTools.items
    }

    /// The fixed tool groups the capture editor passes (S5/S7): the fixed
    /// family-grouped palette over a still image, drawn with the same family
    /// dividers as always. Exposed for the tests and the selftest.
    var fixedToolGroups: [[Tool]]? { toolGroups }

    /// The fixed trailing items in the order the bar draws them (T3/S4): the
    /// `⠇⠇` grab handle sits directly after the close button. The array is
    /// the single source the `body` tail maps over, so the tests pin the
    /// order here instead of inspecting SwiftUI internals.
    enum TrailingItem: CaseIterable, Equatable {
        case undo, redo, clear, close, gripper
    }

    static let trailingItems: [TrailingItem] = TrailingItem.allCases

    /// The stacking direction the bar draws in (T9/S12), read from the
    /// state's mirror of the persisted preference so a Settings change re-lays
    /// out the bar live.
    private var isVertical: Bool {
        state.toolbarOrientation == .vertical
    }

    var body: some View {
        Group {
            if isVertical {
                VStack(alignment: .center, spacing: 4) { barItems }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
            } else {
                HStack(spacing: 4) { barItems }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onPreferenceChange(ToolbarItemSizeKey.self) { itemSizes = $0 }
    }

    /// Everything the bar offers, in the same order both orientations draw:
    /// the configured tools (T6/S5: the stored item list, or the capture
    /// editor's fixed grouped palette), inks, crop/extra actions, page
    /// controls, then undo, redo, clear, close and the gripper tail (T3/S4).
    @ViewBuilder
    private var barItems: some View {
        if let toolGroups {
            ForEach(Array(toolGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 { divider }
                ForEach(group) { tool in
                    toolButton(tool)
                }
            }

            divider
        } else {
            // The stored list, drawn exactly as stored: tools as buttons,
            // separators as the same dividers the grouped bar always drew.
            ForEach(Array(toolSection.enumerated()), id: \.offset) { _, item in
                switch item {
                case .tool(let tool):
                    organiserWrapped(toolButton(tool), item)
                case .separator:
                    organiserWrapped(divider, item)
                }
            }
            // The fixed divider before the inks, unless the layout already
            // ends in a placed separator — the bar must not draw two
            // adjacent dividers.
            if toolSection.last?.tool != nil {
                divider
            }
        }

            ForEach(Ink.allCases) { ink in
                inkButton(ink)
            }

            if !extraActions.isEmpty {
                divider
                ForEach(extraActions) { action in
                    iconButton(
                        action.symbolName,
                        help: action.help,
                        isMarked: action.isSelected,
                        action: action.handler
                    )
                }
            }

            if let page = state.whiteboardPage, let previous = onPreviousPage, let next = onNextPage {
                divider
                iconButton("chevron.left", help: "Previous page (⌘←)", action: previous)
                Text("\(page.current)/\(page.total)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.secondary)
                    .frame(minWidth: 26)
                iconButton("chevron.right", help: "Next page (⌘→)", action: next)
                if let onDeletePage {
                    Button(action: onDeletePage) {
                        Image(systemName: "rectangle.stack.badge.minus")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 26, height: 26)
                            .foregroundStyle(Color.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(page.total <= 1)
                    .opacity(page.total <= 1 ? 0.3 : 1)
                    .help(Text(verbatim: "Delete page (⌘⌫)"))
                }
            }

            divider

            ForEach(ToolbarView.trailingItems, id: \.self) { item in
                switch item {
                case .undo:
                    iconButton("arrow.uturn.backward", help: "Undo (⌘Z)", action: onUndo)
                case .redo:
                    iconButton("arrow.uturn.forward", help: "Redo (⇧⌘Z)", action: onRedo)
                case .clear:
                    iconButton("trash", help: "Clear all (esc)", action: onClear)
                case .close:
                    iconButton("xmark", help: "Done (esc)", action: onDone)
                case .gripper:
                    ToolbarGripper()
                        .background(ToolbarGripperDots())
                        .frame(width: 16, height: 26)
                }
            }
        }

    /// Wraps an item in the organiser's drag and drop handling (T6/S5): a
    /// drag source carrying the item's stable identifier, and a two-sided
    /// drop target. Only the Settings preview installs the hooks.
    @ViewBuilder
    private func organiserWrapped(_ view: some View, _ item: ToolbarLayoutItem) -> some View {
        if let organiser {
            view
                .onDrag { organiser.dragProvider(item) }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ToolbarItemSizeKey.self, value: [item: geo.size])
                    }
                )
                .onDrop(of: [UTType.plainText], delegate: ToolbarSlotDropDelegate(
                    target: item,
                    size: itemSizes[item] ?? Self.fallbackItemSize(item),
                    axisVertical: isVertical,
                    onDrop: { target, edge, payload in organiser.drop(target, edge, payload) }
                ))
        } else {
            view
        }
    }

    /// The size an item renders before the first measurement pass answers.
    private static func fallbackItemSize(_ item: ToolbarLayoutItem) -> CGSize {
        if item.tool != nil {
            CGSize(width: 28, height: 26)
        } else {
            CGSize(width: 12, height: 28)
        }
    }

    /// The separator the bar places between groups: a vertical rule in the
    /// horizontal row, a horizontal rule in the vertical stack.
    private var divider: some View {
        Group {
            if isVertical {
                Divider()
                    .frame(width: 20)
            } else {
                Divider()
                    .frame(height: 20)
            }
        }
        .padding(.horizontal, isVertical ? 0 : 4)
        .padding(.vertical, isVertical ? 4 : 0)
    }

    private func toolButton(_ tool: Tool) -> some View {
        // The marking answers the editor's single armed item (S6): with the
        // crop armed no tool is marked, exactly as picking a tool unmarks the
        // crop. Outside the capture editor the armed item is always the
        // current tool, so this reduces to today's `tool == tool` marking.
        let marked = state.isToolMarked(tool)
        return Button { state.select(tool) } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .foregroundStyle(marked ? Color.white : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(marked ? Color.accentColor.opacity(0.55) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: "\(tool.displayName) (\(state.toolShortcuts[tool]))"))
    }

    private func inkButton(_ ink: Ink) -> some View {
        Button { state.ink = ink } label: {
            Circle()
                .fill(color(for: ink))
                .frame(width: 15, height: 15)
                .overlay(
                    Circle()
                        .strokeBorder(
                            state.ink == ink ? Color.primary : Color.primary.opacity(0.25),
                            lineWidth: state.ink == ink ? 2 : 1
                        )
                )
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: "\(ink.displayName) (\(ink.number))"))
    }

    private func iconButton(
        _ symbol: String,
        help: String,
        isMarked: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(isMarked ? Color.white : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isMarked ? Color.accentColor.opacity(0.55) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func color(for ink: Ink) -> Color {
        Color(
            .sRGB,
            red: Double(ink.rgb.red),
            green: Double(ink.rgb.green),
            blue: Double(ink.rgb.blue),
            opacity: 1
        )
    }
}
