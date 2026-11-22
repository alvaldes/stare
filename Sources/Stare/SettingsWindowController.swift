import AppKit
import SwiftUI
import StareCore

/// Owns the settings window: a resizable sidebar + panes shell. It is a normal
/// window, so this is the one place where activating Stare is correct.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: PreferencesModel
    private let permissionProbe: PermissionProbe

    /// Default open size is 1000x660; the shell itself shrinks to 860x560
    /// and stretches with the window (`contentMinSize`).
    private static let defaultSize = CGSize(width: 1000, height: 660)
    private static let minSize = CGSize(width: 860, height: 560)

    init(model: PreferencesModel, permission: ScreenRecordingPermission) {
        self.model = model
        self.permissionProbe = PermissionProbe(permission: permission)
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // The selected area lives in SwiftUI `@State`, and every open starts on
        // General (netty's behaviour): `show()` recreates the hosting view, so
        // the state and pane scroll position reset deterministically even
        // though closing the window does not tear the SwiftUI tree down.
        window.contentView = makeHostingView()

        if self.window === window, window.isVisible == false, window.frame.origin == .zero {
            window.center()
        }
        // An `.accessory` app opens a real key window by activating first,
        // ordering front regardless, and re-asserting once the activation
        // settles (next runloop turn) — the same pattern the guide uses.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        Diag.log("settings opened")
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stare Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minSize
        window.contentView = makeHostingView()
        window.setContentSize(Self.defaultSize)
        return window
    }

    private func makeHostingView() -> NSHostingView<SettingsView> {
        // The root view carries the flexible `.frame(minWidth:minHeight:)`, but
        // self-sizing stays off so the window — not the view's fitting size —
        // owns the geometry (see the guide, and the DEVELOPMENT.md note that
        // `fittingSize` is zero before layout).
        let hosting = NSHostingView(rootView: SettingsView(
            model: model,
            permission: permissionProbe
        ))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = CGRect(origin: .zero, size: Self.defaultSize)
        return hosting
    }
}
