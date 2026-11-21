import AppKit
import StareCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureService = CaptureService()
    /// The single persisted owner of the app-wide preferences blob (T6
    /// slice 1): every control reads and writes through this instance, and
    /// nothing else loads the blob from the store. The model is main-actor
    /// isolated and the delegate is only ever created on the main thread,
    /// hence the assumed isolation here.
    private let preferences = MainActor.assumeIsolated { PreferencesModel() }
    private lazy var overlay = OverlayController(
        captureService: captureService,
        preferences: preferences
    )
    private var statusBar: StatusBarController?
    /// The Settings shell now observes the single preferences owner and the
    /// shared permission model directly (T6 slice 2); it no longer goes
    /// through the overlay editor's mirrored state.
    @MainActor private lazy var settings = SettingsWindowController(
        model: preferences,
        permission: screenRecording
    )
    /// One permission model for the whole app; the onboarding guide drives it.
    @MainActor private lazy var screenRecording = ScreenRecordingPermission(
        client: SystemScreenRecordingClient(captureService: captureService)
    )
    @MainActor private lazy var onboarding = OnboardingWindowController(
        permission: screenRecording,
        onDismissOverlay: { [weak self] in
            guard let self else { return }
            // The guide replaces whatever drawing surface is armed, through
            // its existing dismiss APIs: the overlay must not fight the
            // guide for z-order.
            if self.overlay.isActive {
                self.overlay.deactivate(restoringFocus: false)
            }
            if self.overlay.isBoardActive {
                self.overlay.toggleBoard()
            }
            if self.overlay.isPointerActive {
                self.overlay.togglePointer()
            }
        },
        onFinish: { [weak self] continueToSettings in
            self?.markOnboardingComplete()
            if continueToSettings {
                self?.settings.show()
            }
        }
    )
    private var hotkey: GlobalHotkey?
    private var pointerHotkey: GlobalHotkey?
    private var pinHotkey: GlobalHotkey?
    private var whiteboardHotkey: GlobalHotkey?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        Diag.reset()
        Diag.log("launched path=\(Bundle.main.bundlePath)")

        statusBar = StatusBarController(
            onDraw: { [weak self] in self?.overlay.toggle() },
            onClear: { [weak self] in self?.overlay.clearAll() },
            onPointerToggle: { [weak self] in self?.overlay.togglePointer() },
            onPinToggle: { [weak self] in self?.overlay.togglePin() },
            onBoardToggle: { [weak self] in self?.overlay.toggleBoard() },
            onOpenSettings: { [weak self] in self?.settings.show() },
            onOpenOnboarding: { [weak self] in self?.onboarding.show() },
            isPinned: { [weak self] in self?.overlay.isPinned ?? false }
        )

        hotkey = GlobalHotkey(
            keyCode: HotkeyDefaults.keyCode,
            carbonModifiers: HotkeyDefaults.carbonModifiers
        ) { [weak self] in
            self?.overlay.toggle()
        }

        pointerHotkey = GlobalHotkey(
            keyCode: HotkeyDefaults.pointerKeyCode,
            carbonModifiers: HotkeyDefaults.carbonModifiers
        ) { [weak self] in
            self?.overlay.togglePointer()
        }

        // Pinning is only useful while another app has focus, so it has to be a
        // global shortcut and not a local key monitor.
        pinHotkey = GlobalHotkey(
            keyCode: HotkeyDefaults.pinKeyCode,
            carbonModifiers: HotkeyDefaults.carbonModifiers
        ) { [weak self] in
            self?.overlay.togglePin()
        }

        // T6: the whiteboard replaces the transparent overlay with an opaque,
        // permission-free board.
        whiteboardHotkey = GlobalHotkey(
            keyCode: HotkeyDefaults.whiteboardKeyCode,
            carbonModifiers: HotkeyDefaults.carbonModifiers
        ) { [weak self] in
            self?.overlay.toggleBoard()
        }

        // First run (T5/S3): the setup guide is the one asking for Screen
        // Recording now, so the launch-time prompt stays out of the way — the
        // user must not be asked twice. Every later launch keeps exactly
        // today's behaviour: request the permission at launch if it is
        // missing, so it never surfaces as a system prompt on the S key.
        if !preferences.hasCompletedOnboarding {
            Diag.log("first launch, showing setup guide")
            onboarding.show()
        } else if !captureService.hasPermission {
            Diag.log("screen recording missing, asking at launch")
            captureService.requestPermission()
        }

        Diag.log(
            "hotkeys draw=\(hotkey != nil) pointer=\(pointerHotkey != nil) pin=\(pinHotkey != nil) whiteboard=\(whiteboardHotkey != nil) policy=\(NSApp.activationPolicy().rawValue) capture=\(captureService.hasPermission)"
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Marks the guide as seen, once. Idempotent, so reopening it from the
    /// menu never flips the flag (S3); writing through the preferences model
    /// also carries the legacy per-key migration into the blob on the first
    /// save.
    @MainActor
    private func markOnboardingComplete() {
        guard !preferences.hasCompletedOnboarding else { return }
        preferences.hasCompletedOnboarding = true
        Diag.log("onboarding marked complete")
    }
}
