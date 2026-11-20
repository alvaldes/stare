import AppKit
import SwiftUI

/// Owns the settings window. It is a normal window, so this is the one place
/// where activating Stare is correct.
final class SettingsWindowController {
    private var window: NSWindow?
    private let state: EditorState

    init(state: EditorState) {
        self.state = state
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        if self.window === window, window.isVisible == false, window.frame.origin == .zero {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        Diag.log("settings opened")
    }

    private func makeWindow() -> NSWindow {
        // A fixed content size: NSHostingView.fittingSize is zero before a layout
        // pass, and a zero-sized window is created but never seen.
        let size = CGSize(width: 420, height: 560)
        let hosting = NSHostingView(rootView: SettingsView(state: state))
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stare Settings"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(size)
        return window
    }
}
