import AppKit
import StareCore
import SwiftUI

/// The hidden tools as their own window (T6): a minimal, non-activating panel
/// that opens beside the bar — toward the middle of the screen, never toward the
/// edge the bar is docked to. It holds nothing but the tools the bar hides: no
/// inks, no dividers, no undo/close tail, so it reads as one small thing that
/// appeared next to the bar and not as a second bar.
///
/// `ToolbarOverflowPlacement` owns the geometry, so the placement is pinned by
/// tests without a screen.
final class ToolbarOverflowPanel: NSPanel {
    /// The level the bar itself uses: the extras must sit with it, above the
    /// drawing layer, and never under it.
    static let panelLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)

    private let hosting: NSHostingView<ToolbarOverflowExtrasView>
    private let onPick: (Tool) -> Void

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(state: EditorState, hidden: [Tool], vertical: Bool, onPick: @escaping (Tool) -> Void) {
        self.onPick = onPick
        hosting = NSHostingView(rootView: ToolbarOverflowExtrasView(
            state: state,
            hidden: hidden,
            vertical: vertical,
            onPick: onPick
        ))
        hosting.sizingOptions = [.intrinsicContentSize]
        let size = hosting.fittingSize
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = Self.panelLevel
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        contentView = hosting
        setContentSize(size)
    }

    /// Puts the panel beside the bar on the side that faces the middle of the
    /// screen, clamped into the screen's visible frame.
    func place(beside barFrame: CGRect, border: ToolbarBorder, screen: NSScreen) {
        let size = hosting.fittingSize
        let rect = ToolbarOverflowPlacement.panelFrame(
            panelSize: size,
            barFrame: barFrame,
            border: border,
            visibleFrame: screen.visibleFrame
        )
        setFrame(rect, display: false)
    }

    /// Selects a hidden tool. The button calls this; the tests call it too, so
    /// the "pick one and the panel closes" rule is pinned without synthesising a
    /// click.
    func pick(_ tool: Tool) {
        onPick(tool)
    }
}

/// What the extras panel shows: just the hidden tools, in the axis the bar is
/// laid out in — a column beside a vertical bar, a row beside a horizontal one.
struct ToolbarOverflowExtrasView: View {
    @ObservedObject var state: EditorState
    let hidden: [Tool]
    let vertical: Bool
    let onPick: (Tool) -> Void

    var body: some View {
        Group {
            if vertical {
                VStack(spacing: 4) { buttons }
            } else {
                HStack(spacing: 4) { buttons }
            }
        }
        .padding(8)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(hidden, id: \.self) { tool in
            Button { onPick(tool) } label: {
                Image(systemName: tool.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 26)
                    .foregroundStyle(state.isToolMarked(tool) ? Color.white : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(state.isToolMarked(tool) ? Color.accentColor.opacity(0.55) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(verbatim: "\(tool.displayName) (\(state.toolShortcuts[tool]))"))
        }
    }
}
