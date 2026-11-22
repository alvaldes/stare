import AppKit
import SwiftUI
import StareCore

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

/// The handle itself: a 2×3 dot pattern on a hit area big enough to grab,
/// drawn by the view — no new asset.
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

    /// The gripper's frame in window coordinates (T2/S3): what the hosting
    /// view's cursor arbitration reads to stand down its arrow over this rect.
    var frameInWindow: NSRect {
        convert(bounds, to: nil)
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

    override func draw(_ dirtyRect: NSRect) {
        // Two columns of three stacked dots, centred in the hit area.
        let dot: CGFloat = 3
        let pitchX: CGFloat = 6
        let pitchY: CGFloat = 5
        let columns = ToolbarGripperSpec.dotColumns
        let rows = ToolbarGripperSpec.dotRows
        let gridWidth = CGFloat(columns - 1) * pitchX + dot
        let gridHeight = CGFloat(rows - 1) * pitchY + dot
        let originX = (bounds.width - gridWidth) / 2
        let originY = (bounds.height - gridHeight) / 2

        NSColor.secondaryLabelColor.setFill()
        for column in 0..<columns {
            for row in 0..<rows {
                let rect = CGRect(
                    x: originX + CGFloat(column) * pitchX,
                    y: originY + CGFloat(row) * pitchY,
                    width: dot,
                    height: dot
                )
                NSBezierPath(ovalIn: rect).fill()
            }
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

    /// The tool section the bar draws (T8/S10): a fixed palette when one is
    /// passed, or the persisted layout's visible groups — exactly the stored
    /// order with the hidden tools skipped, no gaps, no phantom items,
    /// nothing duplicated. Exposed so the selftest can pin that the rendered
    /// bar follows the configured layout without poking SwiftUI internals.
    var toolSection: [[Tool]] {
        toolGroups ?? state.toolbarTools.visibleGroups
    }

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
    }

    /// Everything the bar offers, in the same order both orientations draw:
    /// the configured tool groups (T8/S10), inks, crop/extra actions, page
    /// controls, then undo, redo, clear, close and the gripper tail (T3/S4).
    @ViewBuilder
    private var barItems: some View {
            ForEach(Array(toolSection.enumerated()), id: \.offset) { index, group in
                if index > 0 { divider }
                ForEach(group) { tool in
                    toolButton(tool)
                }
            }

            divider

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
                    ToolbarGripper().frame(width: 16, height: 26)
                }
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
