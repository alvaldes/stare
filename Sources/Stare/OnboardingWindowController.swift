import AppKit
import SwiftUI
import StareCore

/// Observable shell over `ScreenRecordingPermission` for the guide's SwiftUI
/// view. `ScreenRecordingPermission` is a plain `@MainActor` class with an
/// `onChange` callback, so the window keeps publishing `access` from it and
/// the UI updates without polling races.
@MainActor
final class OnboardingModel: ObservableObject {
    let permission: ScreenRecordingPermission

    @Published private(set) var access: ScreenRecordingAccess = .denied

    /// Also read by the window controller, which stops refreshing once the
    /// state is terminal for this session.
    var onAccessChanged: ((ScreenRecordingAccess) -> Void)?

    init(permission: ScreenRecordingPermission) {
        self.permission = permission
        permission.onChange = { [weak self] access in
            self?.access = access
            self?.onAccessChanged?(access)
        }
    }

    /// Forwards to the permission model: re-reads the three TCC answers.
    @discardableResult
    func refresh() -> ScreenRecordingAccess {
        permission.refresh()
    }

    /// The guide's primary button: prompt the system, then land the user on
    /// the Screen Recording pane so they only have to flip the switch (S1).
    func requestAccess() {
        permission.requestAccess()
    }

    func openSettings() {
        permission.openSettings()
    }
}

/// Owns the onboarding window (T5/S1–S3). Follows the pattern an `.accessory`
/// app needs to open a real key window (`NSApp.activate()` +
/// `orderFrontRegardless()` + a next-runloop re-assert, like
/// `SettingsWindowController` and `CaptureEditorController`), sits above every
/// window the drawing overlay owns, and drives the permission model while it
/// is visible.
///
/// Every close path — "Not now", Continue, the title-bar close button, or a
/// relaunch — reports the guide as finished, so closing it without granting
/// the permission still marks onboarding complete (S3: it never reappears on
/// its own).
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: OnboardingModel
    /// The guide's window, once shown; read by the self test.
    private(set) var window: NSWindow?
    private var refreshTimer: Timer?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var finished = false

    /// Dismisses whatever drawing surface is armed before the guide opens, so
    /// the two never fight for z-order (the guide reads the screen, the
    /// overlay covers it).
    private let onDismissOverlay: () -> Void
    /// Reported exactly once per guide session: `true` when the user pressed
    /// Continue (the caller marks onboarding complete and opens Settings),
    /// `false` when the guide closed any other way.
    private let onFinish: (Bool) -> Void

    /// The permission state the guide is showing; read by the self test.
    var access: ScreenRecordingAccess { model.access }

    init(
        permission: ScreenRecordingPermission,
        onDismissOverlay: @escaping () -> Void,
        onFinish: @escaping (Bool) -> Void
    ) {
        self.model = OnboardingModel(permission: permission)
        self.onDismissOverlay = onDismissOverlay
        self.onFinish = onFinish
        super.init()
        model.onAccessChanged = { [weak self] _ in self?.observeTerminalState() }
    }

    // MARK: Showing

    func show() {
        onDismissOverlay()

        let window = self.window ?? makeWindow()
        self.window = window
        window.center()
        finished = false

        // An `.accessory` app opens a real key window by activating first,
        // ordering front regardless, and re-asserting once the activation
        // settles (next runloop turn).
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        startObserving()
        refreshPermission()
        Diag.log("onboarding opened state=\(model.access)")
    }

    /// A titled window in an accessory app already becomes key; the self test
    /// still asserts this, because the guide is useless if it cannot take the
    /// click that reaches System Settings.
    private func makeWindow() -> NSWindow {
        // Fixed content size: the guide is one card of copy and buttons.
        let size = CGSize(width: 460, height: 430)
        let hosting = NSHostingView(rootView: OnboardingView(
            model: model,
            onContinue: { [weak self] in self?.continueToSettings() },
            onRestart: { [weak self] in self?.restartApp() },
            onNotNow: { [weak self] in self?.window?.close() }
        ))
        // The root view fills the window with a flexible `.frame`, so the
        // hosting view's default self-sizing constraints would drive the
        // window to the view's maximum fitting size. Self-sizing stays off:
        // the window is the fixed size, the view fills it.
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stare"
        window.isReleasedWhenClosed = false
        window.delegate = self
        // The drawing overlay sits at `.screenSaver`, the palette one level
        // above it and the capture card two (see `OverlayWindow`,
        // `ToolbarPanel`, `CaptureCard`). Three levels above the overlay keeps
        // the guide readable no matter what the app has armed.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        window.collectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = hosting
        window.setContentSize(size)
        return window
    }

    // MARK: Driving the model

    private func startObserving() {
        guard refreshTimer == nil, didBecomeActiveObserver == nil else { return }

        // Coming back from System Settings re-reads the state (S2).
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPermission()
        }

        // A short poll while the guide is visible catches the switch flip even
        // when activation does not change.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPermission()
        }
    }

    private func stopObserving() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let observer = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            didBecomeActiveObserver = nil
        }
    }

    /// Re-reads the permission. Once a real capture has succeeded in this
    /// process the state is terminal: a per-process grant cannot become
    /// pending-restart again without a restart, so skipping the probe keeps
    /// the timer tick free of captures.
    private func refreshPermission() {
        guard model.access != .granted else { return }
        model.refresh()
    }

    /// Once granted there is nothing left to poll: the state cannot change
    /// without a restart.
    private func observeTerminalState() {
        if model.access == .granted {
            stopObserving()
        }
    }

    // MARK: Closing

    /// Continue (S2): enabled only when the access is granted. Reports the
    /// finish first so the flag is written before the Settings window opens,
    /// then closes the guide.
    private func continueToSettings() {
        finish(continueToSettings: true)
        window?.close()
    }

    /// Relaunches Stare via `NSWorkspace` so the per-process TCC grant lands
    /// in the fresh process (S2).
    private func restartApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            if let error { Diag.log("relaunch failed: \(error)") }
        }
        finish(continueToSettings: false)
        NSApp.terminate(nil)
    }

    private func finish(continueToSettings: Bool) {
        guard !finished else { return }
        finished = true
        stopObserving()
        onFinish(continueToSettings)
        Diag.log("onboarding finished continueToSettings=\(continueToSettings)")
    }

    func windowWillClose(_ notification: Notification) {
        // Any close without Continue still marks the guide as seen (S3).
        finish(continueToSettings: false)
    }
}
