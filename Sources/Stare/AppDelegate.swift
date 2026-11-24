import AppKit
import Combine
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
        preferences: preferences,
        // The boot-scoped session archive (T10/S11): the production path —
        // the app's standard domain, tagged with the machine's boot instant.
        sessionStore: BootSessionStore()
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
    /// The OCR/QR gesture (T5/S7): ⌥⇧O, its own selection surface, on-device
    /// Vision, clipboard copy. Works with no drawing session; the recogniser
    /// reuses the capture service's permission preflight so the gesture never
    /// prompts mid-way.
    @MainActor private lazy var recognitionFlow = TextRecognitionFlow(
        client: TextRecognitionClient(captureService: captureService)
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
    /// The four global hotkeys, registered from the live `HotkeyBindings`
    /// (T9/S6) instead of hardcoded constants; the registration path re-runs
    /// whenever the bindings change in Settings.
    private let hotkeyManager = GlobalHotkeyManager()
    private var hotkeysCancellable: AnyCancellable?
    /// The bindings currently registered, so a changed action can be applied
    /// alone and a refused one can be reverted to what was live.
    private var appliedHotkeys: HotkeyBindings = .standard

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
            onRecognizeText: { [weak self] in self?.recognitionFlow.begin() },
            isPinned: { [weak self] in self?.overlay.isPinned ?? false },
            // Whiteboard page actions (T12/S9): the enablement queries and the
            // actions all route through the controller to the display under
            // the pointer.
            isBoardOpen: { [weak self] in self?.overlay.isBoardActive ?? false },
            boardPageState: { [weak self] in self?.overlay.boardPageState },
            onDeleteBoardPage: { [weak self] in self?.overlay.deleteBoardPage() },
            onMoveBoardPageLeft: { [weak self] in self?.overlay.moveBoardPageLeft() },
            onMoveBoardPageRight: { [weak self] in self?.overlay.moveBoardPageRight() },
            onResetBoardPan: { [weak self] in self?.overlay.resetBoardPan() }
        )

        registerGlobalHotkeys(from: preferences.hotkeys)
        hotkeysCancellable = preferences.$hotkeys.dropFirst().sink { [weak self] bindings in
            guard let self else { return }
            MainActor.assumeIsolated { self.registerGlobalHotkeys(from: bindings) }
        }

        // Updates (T10/S6): the persisted schedule decides whether a check is
        // due at launch. The app is not notarized, so a check only informs and
        // links to the release page; nothing is ever installed, and a result
        // only lands in the pane's status plus the persisted lastCheck.
        if preferences.updateSchedule != .never {
            Task { @MainActor in await UpdateFlow.checkIfDue(model: preferences) }
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
            "hotkeys \(hotkeyManager.registeredBindings.map { "\($0.key.rawValue)=\($0.value.displayTitle)" }.sorted().joined(separator: " ")) policy=\(NSApp.activationPolicy().rawValue) capture=\(captureService.hasPermission)"
        )
    }

    /// Registers (or re-registers) the global hotkeys from `bindings`. Every
    /// action registers independently, so one refusal at launch leaves the
    /// rest working (T9/S7). A refused binding is reverted to the previous
    /// one — which stayed registered — and reported to the Settings pane,
    /// where the refusal is visible instead of silent.
    @MainActor
    private func registerGlobalHotkeys(from bindings: HotkeyBindings) {
        let handlers: [HotkeyAction: () -> Void] = [
            .drawOverlay: { [weak self] in self?.overlay.toggle() },
            .pointerHighlight: { [weak self] in self?.overlay.togglePointer() },
            .pin: { [weak self] in self?.overlay.togglePin() },
            .whiteboard: { [weak self] in self?.overlay.toggleBoard() },
            .captureHistory: { [weak self] in self?.overlay.toggleCaptureHistory() },
        ]
        var refused: (action: HotkeyAction, binding: HotkeyBinding)?
        for action in HotkeyAction.allCases {
            let binding = bindings[action]
            if hotkeyManager.apply(binding, to: action, handler: handlers[action] ?? {}) {
                appliedHotkeys.assigning(binding, to: action)
            } else if refused == nil {
                refused = (action, binding)
            }
        }
        if let refused {
            // The previous binding stayed registered, so the model goes back
            // to it too: what the pane shows is what the system answers to.
            preferences.hotkeys = appliedHotkeys
            preferences.hotkeyRejection = HotkeyRejection(action: refused.action, binding: refused.binding)
        } else {
            preferences.hotkeyRejection = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// S11: at termination whatever is drawn and the boards' pages are stored
    /// one last time, so they come back at the next launch of the same boot.
    /// Cheap and lossless against the in-memory session by contract.
    func applicationWillTerminate(_ notification: Notification) {
        overlay.saveSession()
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
