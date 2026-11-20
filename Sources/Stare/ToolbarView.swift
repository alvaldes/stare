import AppKit
import SwiftUI
import StareCore

struct ToolbarView: View {
    @ObservedObject var state: EditorState
    let onUndo: () -> Void
    let onPointerToggle: () -> Void
    let onClear: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Tool.allCases) { tool in
                toolButton(tool)
            }

            divider

            ForEach(Ink.allCases) { ink in
                inkButton(ink)
            }

            divider

            toggleButton(
                "cursorarrow",
                isOn: state.pointerActive,
                help: Text(verbatim: "Pointer highlight (⌥⇧M)")
            ) {
                onPointerToggle()
            }

            divider

            iconButton("arrow.uturn.backward", help: "Undo (⌘Z)", action: onUndo)
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
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var divider: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 4)
    }

    private func toolButton(_ tool: Tool) -> some View {
        Button { state.tool = tool } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .foregroundStyle(state.tool == tool ? Color.white : Color.white.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(state.tool == tool ? Color.accentColor.opacity(0.55) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: "\(tool.displayName) (\(tool.shortcut))"))
    }

    private func inkButton(_ ink: Ink) -> some View {
        Button { state.ink = ink } label: {
            Circle()
                .fill(color(for: ink))
                .frame(width: 15, height: 15)
                .overlay(
                    Circle()
                        .strokeBorder(
                            state.ink == ink ? Color.white : Color.white.opacity(0.25),
                            lineWidth: state.ink == ink ? 2 : 1
                        )
                )
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: "\(ink.displayName) (\(ink.number))"))
    }

    private func toggleButton(
        _ symbol: String,
        isOn: Bool,
        help: Text,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.55) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(Color.white.opacity(0.7))
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
