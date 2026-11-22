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
    /// The tools the bar offers. Defaults to the full drawing palette; a
    /// surface where some tools cannot work (the capture editor) offers a
    /// filtered set, so no dead button is shown and no dead shortcut arms a
    /// hidden tool.
    var toolGroups: [[Tool]] = Tool.toolbarGroups

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(toolGroups.enumerated()), id: \.offset) { index, group in
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

            iconButton("arrow.uturn.backward", help: "Undo (⌘Z)", action: onUndo)
            iconButton("arrow.uturn.forward", help: "Redo (⇧⌘Z)", action: onRedo)
            iconButton("trash", help: "Clear all (esc)", action: onClear)
            iconButton("xmark", help: "Done (esc)", action: onDone)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var divider: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 4)
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
