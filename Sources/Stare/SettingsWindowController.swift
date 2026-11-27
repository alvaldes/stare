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

    /// The title the window carries. Owned by the capture filter (`ScreenContent`,
    /// S8), whose exclusion keys on the title the window server reports for the
    /// one Stare window it keeps visible in the pixels; the controller names its
    /// window with the same constant, so the two cannot drift apart.

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

    /// The level Settings rests at while a mode is on screen (S7): the app's
    /// own drawing surfaces live at `.screenSaver` and above — the drawing
    /// panels at `.screenSaver`, the palette at +1, the capture cards at +2,
    /// the history sheet and the setup guide at +3 — so a normal-level
    /// Settings window would open BEHIND everything the user is watching and
    /// ⌘, would look like a keystroke that did nothing. The same band the
    /// history sheet and the guide sit on; `makeKeyAndOrderFront` puts it
    /// first inside that band.
    static let overlaySurfaceLevel = NSWindow.Level(
        rawValue: NSWindow.Level.screenSaver.rawValue + 3
    )

    /// The level an open uses: laid back at `.normal` when nothing of the
    /// app's own is on screen, lifted into the overlay band when a mode holds
    /// the screen (`aboveOverlay`, S7).
    static func level(aboveOverlay: Bool) -> NSWindow.Level {
        aboveOverlay ? overlaySurfaceLevel : .normal
    }

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

    /// `aboveOverlay` (S7): whether a screen-holding overlay surface is on
    /// screen. While one is, the open lifts the window into the overlay band
    /// (`overlaySurfaceLevel`), because a `.normal` window sits behind the
    /// `.screenSaver` drawing panels and the user sees nothing. The caller —
    /// the one open path in `AppDelegate` — reads the decision from the
    /// overlay controller (`isAnyOverlaySurfaceActive`), and the window goes
    /// back to its normal level on every later open, so an open that starts
    /// after the modes closed never keeps the lift.
    func show(aboveOverlay: Bool = false) {
        let window = self.window ?? makeWindow()
        self.window = window
        window.level = Self.level(aboveOverlay: aboveOverlay)
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
        reassertActivationAfterShow(window: window)
        Diag.log("settings opened")
    }

    /// The open's re-assert, one runloop turn later: activation settles
    /// asynchronously, so `show` queues `NSApp.activate` + a
    /// `makeKeyAndOrderFront` for the next turn, exactly the way the guide
    /// does. The queued turn is a stored, cancellable item, and this is the
    /// gate that keeps it from firing into whatever runs after the settings
    /// window's owner is gone: the window's own close path cancels the item
    /// (a queued turn must never re-activate a closed window's dead state), a
    /// later `show` cancels and re-arms the latest, and the body's own
    /// `isVisible` guard answers nothing for an already-hidden window.
    private var queuedReassert: DispatchWorkItem?

    private func reassertActivationAfterShow(window: NSWindow) {
        queuedReassert?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        queuedReassert = work
        DispatchQueue.main.async(execute: work)
    }

    private func cancelQueuedReassert() {
        queuedReassert?.cancel()
        queuedReassert = nil
    }

    func windowWillClose(_ notification: Notification) {
        // The owner's exit: any queued re-assert belongs to a window that no
        // longer exists, so it must not run.
        cancelQueuedReassert()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ScreenContent.settingsWindowTitle
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
