import AppKit
import SwiftUI
import StareCore

/// Owns the settings window: a resizable sidebar + panes shell. It is a normal
/// window, so this is the one place where activating Stare is correct.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: PreferencesModel
    private let permissionProbe: PermissionProbe

    /// Default open size, taken from the size the owner actually works at:
    /// a 1000x812 frame, which is 1000x780 of content (the title bar is 32 pt
    /// on this window). The old 1000x660 opened shorter than every pane wanted
    /// and had to be resized on the way in.
    private static let defaultSize = CGSize(width: 1000, height: 780)

    /// The floor the window stops at, and the ONE number behind it (B7): the
    /// window enforces it through `contentMinSize` and the SwiftUI root lays
    /// itself out from the same value. It used to be written twice — once here
    /// and once as a literal in `SettingsView` — so the width the cards are
    /// computed from and the width a drag stops at could drift apart.
    static let minimumContentSize = CGSize(width: 860, height: 560)

    init(model: PreferencesModel, permission: ScreenRecordingPermission) {
        self.model = model
        self.permissionProbe = PermissionProbe(permission: permission)
        super.init()
    }

    /// The floor on the FRAME, derived from the content floor. `contentMinSize`
    /// on its own is not enough to stop a drag: AppKit re-derives the content
    /// minimum from the content view's constraints, and an `NSHostingView`
    /// carries none, so the clamp is also imposed on the frame and re-asserted
    /// at the one place a live resize passes — the delegate.
    private static func minimumFrameSize(for window: NSWindow) -> NSSize {
        window.frameRect(
            forContentRect: CGRect(origin: .zero, size: minimumContentSize)
        ).size
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minimum = Self.minimumFrameSize(for: sender)
        return NSSize(
            width: max(frameSize.width, minimum.width),
            height: max(frameSize.height, minimum.height)
        )
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // The selected area lives in SwiftUI `@State`, and every open starts on
        // General (netty's behaviour): `show()` recreates the hosting view, so
        // the state and pane scroll position reset deterministically even
        // though closing the window does not tear the SwiftUI tree down.
        //
        // The new hosting view takes the size the window has NOW: assigning a
        // content view resizes the window to its frame, so a fixed default here
        // threw away every resize the user had made on a previous open (B7).
        let size = window.contentView?.frame.size ?? Self.defaultSize
        window.contentView = makeHostingView(size: size)
        // Assigning a content view with auto-layout constraints makes AppKit
        // re-derive the window's content minimum from them, and an
        // `NSHostingView` reports none: the floor set in `makeWindow()` is
        // silently back to zero on the first open, which is exactly how the
        // window could be dragged away to nothing. Both the content floor and
        // the frame floor are re-asserted after every assignment.
        window.contentMinSize = Self.minimumContentSize
        window.minSize = Self.minimumFrameSize(for: window)

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
        window.delegate = self
        window.contentMinSize = Self.minimumContentSize
        window.contentView = makeHostingView(size: Self.defaultSize)
        window.minSize = Self.minimumFrameSize(for: window)
        window.setContentSize(Self.defaultSize)
        return window
    }

    private func makeHostingView(size: CGSize) -> NSHostingView<SettingsView> {
        // The root view carries the flexible `.frame(minWidth:minHeight:)`, but
        // self-sizing stays off so the window — not the view's fitting size —
        // owns the geometry (see the guide, and the DEVELOPMENT.md note that
        // `fittingSize` is zero before layout).
        let hosting = NSHostingView(rootView: SettingsView(
            model: model,
            permission: permissionProbe,
            minimumContentSize: Self.minimumContentSize
        ))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = CGRect(origin: .zero, size: size)
        return hosting
    }
}
