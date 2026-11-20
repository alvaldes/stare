import AppKit
import SwiftUI

/// Floating, draggable tool palette. Non-activating so that picking a tool
/// never steals focus from the app underneath.
final class ToolbarPanel: NSPanel {
    private static let originKey = "toolbarOrigin"

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(
        state: EditorState,
        onUndo: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        let hosting = NSHostingView(
            rootView: ToolbarView(
                state: state,
                onUndo: onUndo,
                onClear: onClear,
                onDone: onDone
            )
        )
        hosting.sizingOptions = [.intrinsicContentSize]
        let size = hosting.fittingSize

        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true

        contentView = hosting
        setContentSize(size)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistOrigin),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Restores the saved position, or parks the palette at the bottom centre of
    /// the display under the pointer.
    func positionNearPointerDisplay() {
        if let saved = savedOrigin(),
           NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -40, dy: -40).contains(saved) }) {
            setFrameOrigin(saved)
            return
        }

        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        setFrameOrigin(
            CGPoint(
                x: (visible.midX - frame.width / 2).rounded(),
                y: (visible.minY + 48).rounded()
            )
        )
    }

    @objc private func persistOrigin() {
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: Self.originKey)
    }

    private func savedOrigin() -> CGPoint? {
        guard let stored = UserDefaults.standard.string(forKey: Self.originKey) else { return nil }
        let origin = NSPointFromString(stored)
        return origin == .zero ? nil : origin
    }
}
