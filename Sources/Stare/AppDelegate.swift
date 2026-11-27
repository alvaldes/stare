import AppKit
import Combine
import StareCore

/// S7 (round three): the object the app menu's `Settings…` item acts through.
/// A menu action is delivered to a RETAINED target, and a bare closure cannot
/// be one — this tiny target keeps the closure alive inside the menu and
/// translates the action into the call. It exists so `AppDelegate`
/// `makeMainMenu` stays testable: a test builds the real menu around a
/// witness target and drives ⌘, against it.
@MainActor
final class SettingsShortcutMenuTarget: NSObject {

    private let onOpenSettings: () -> Void

    init(onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        super.init()
    }

    @objc func openSettings(_ sender: Any?) {
        onOpenSettings()
    }
}

/// Round four S8: the retained target the app menu's `Close Editor` (⌘W)
/// item acts through. Why it exists: Stare's menu-less accessory app gets
/// its key equivalents through the main menu's own key pass — before any
/// responder — and the menu never carried ⌘W, so the keystroke died there
/// and never reached the editor window at all. The route is the one the
/// window's own close button takes: the target closes the CAPTURE EDITOR
/// window only, the key window when the key window IS an editor's, through
/// its `performClose` and so through the window's close tail. The Settings
/// window, a floating panel and the app itself are never touched: the
/// guard reads nil for every other key window and the item's action is a
/// silent no-op for them.
@MainActor
final class EditorCloseShortcutTarget: NSObject {

    /// The dispatch's own question: the key window when it is an editor's,
    /// nil otherwise. Production reads `NSApp`; tests inject the witness.
    private let keyEditorWindow: () -> CaptureEditorWindow?

    init(keyEditorWindow: @escaping () -> CaptureEditorWindow? = {
        NSApp.keyWindow as? CaptureEditorWindow
    }) {
        self.keyEditorWindow = keyEditorWindow
        super.init()
    }

    @objc func closeEditorWindow(_ sender: Any?) {
        keyEditorWindow()?.performClose(sender)
    }
}

/// editor-save-in-place S4: the retained target the app menu's `Save Editor`
/// (⌘S) item acts through, and the ⌘W item's exact shape: the same
/// retained-target contract (a menu action needs a retained target) and the
/// same key-window gate — the CAPTURE EDITOR key window when the key window
/// IS an editor's, so the Settings window, a floating panel and the app
/// itself are never touched: the gate reads nil for every other key window
/// and the item's action is a silent no-op for them.
@MainActor
final class EditorSaveShortcutTarget: NSObject {

    /// The dispatch's own question: the key window when it is an editor's,
    /// nil otherwise. Production reads `NSApp`; tests inject the witness.
    private let keyEditorWindow: () -> CaptureEditorWindow?

    init(keyEditorWindow: @escaping () -> CaptureEditorWindow? = {
        NSApp.keyWindow as? CaptureEditorWindow
    }) {
        self.keyEditorWindow = keyEditorWindow
        super.init()
    }

    @objc func saveEditorWindow(_ sender: Any?) {
        _ = keyEditorWindow()?.editorContent?.saveInPlace()
    }
}

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
    /// The retained target the app menu's Settings item acts through (S7):
    /// `NSApp.mainMenu` holds the item, the item holds the target.
    private var settingsMenuTarget: SettingsShortcutMenuTarget?
    /// The retained target the app menu's `Close Editor` (⌘W) item acts
    /// through (round four S8) — the same retention contract
    /// `settingsMenuTarget` documents.
    private var editorCloseTarget: EditorCloseShortcutTarget?
    /// The retained target the app menu's `Save Editor` (⌘S) item acts
    /// through (S4) — the same retention contract `settingsMenuTarget`
    /// documents.
    private var editorSaveTarget: EditorSaveShortcutTarget?
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

        // S7: the app has no Dock icon, so it never had a standard AppKit
        // route to Settings either — ⌘, is delivered through the main menu's
        // key equivalents, and with no main menu the keystroke died in every
        // mode that held the keyboard: a drawing session, the board, the
        // history sheet. The app menu carries `Settings…` with ⌘, and routes
        // it through the ONE open path the status bar and the guide already
        // share. When Stare is not the active app the keystroke belongs to
        // whatever app is: intercepting it globally would take ⌘, away from
        // every other app, so the status-bar menu remains the route into
        // Settings from a background Stare.
        let target = SettingsShortcutMenuTarget { [weak self] in
            MainActor.assumeIsolated { self?.openSettings() }
        }
        settingsMenuTarget = target
        // Round four S8: ⌘W closes the editor window — the item rides the
        // retained target that closes the CAPTURE EDITOR key window only, so
        // the Settings window, a floating panel and the app itself stay out
        // of it.
        let editorTarget = EditorCloseShortcutTarget()
        editorCloseTarget = editorTarget
        // editor-save-in-place S4: ⌘S saves the editor window's image in
        // place — the same editor-only gate ⌘W rides.
        let saveTarget = EditorSaveShortcutTarget()
        editorSaveTarget = saveTarget
        NSApp.mainMenu = Self.makeMainMenu(openSettings: target, closeEditor: editorTarget, saveEditor: saveTarget)

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

    /// S7: the ONE open path the keyboard's ⌘, shares with the status bar's
    /// Settings item and the setup guide's continue. The mode decision is the
    /// overlay controller's own: nothing is cancelled here — a drawing
    /// session stays active underneath, as `settings.show()` has always left
    /// it from the status bar — and while a surface holds the screen the
    /// open lifts Settings above it, or the window would open behind the
    /// `.screenSaver` panels and the shortcut would look like a no-op.
    @MainActor
    func openSettings() {
        settings.show(aboveOverlay: overlay.isAnyOverlaySurfaceActive)
        Diag.log("settings opened from shortcut aboveOverlay=\(overlay.isAnyOverlaySurfaceActive)")
    }

    /// Round four S6: the Finder's "Open With" half. The declared image document
    /// types (Resources/Info.plist) make the system deliver this open-files
    /// event when a file is asked to open by Stare; every file lands in the
    /// editor through the ONE `openFileInEditor` route (the `openCaptureEditor`
    /// handoff). A file that is not an image changes nothing — the route
    /// refuses, nothing opens, and the accessory contract stands. It is the
    /// editor window's existence (the route opens exactly one) that puts Stare
    /// in the Dock (the runtime flip, `CaptureEditorController`'s rule).
    func application(_ application: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            _ = overlay.openFileInEditor(at: URL(fileURLWithPath: filename))
        }
    }

    /// S7 (round three) and S8 (round four): the app's main menu, built here
    /// rather than nib-loaded. The app menu carries `Settings…` with ⌘, and
    /// — when a target is wired — `Close Editor` with ⌘W routed to the
    /// editor-only target. No window menu, no edit menus: nothing else in
    /// this app asked for them, and this menu exists for the shortcuts.
    /// Internal so the tests build the same menu the app runs with and drive
    /// ⌘, and ⌘W against real witness targets.
    @MainActor
    static func makeMainMenu(
        openSettings: SettingsShortcutMenuTarget,
        closeEditor: EditorCloseShortcutTarget? = nil,
        saveEditor: EditorSaveShortcutTarget? = nil
    ) -> NSMenu {
        let appMenu = NSMenu(title: "Stare")
        appMenu.addItem(
            NSMenuItem(
                title: "Settings…",
                action: #selector(SettingsShortcutMenuTarget.openSettings(_:)),
                keyEquivalent: ","
            )
        )
        for item in appMenu.items { item.target = openSettings }
        // Round four S8: the editor's ⌘W closes ONLY the editor window — the
        // item rides its own target, so nil-target validation (first
        // responder → whatever window is key) can never hand ⌘W to the
        // Settings window or a floating panel. Absent target: the menu is
        // unchanged, the exact shape round three S7 built.
        if let closeEditor {
            let close = NSMenuItem(
                title: "Close Editor",
                action: #selector(EditorCloseShortcutTarget.closeEditorWindow(_:)),
                keyEquivalent: "w")
            close.target = closeEditor
            appMenu.addItem(close)
        }
        // editor-save-in-place S4: the editor's ⌘S saves in place through the
        // same editor-only target shape ⌘W rides — no nil-target validation,
        // which would save into whatever NON-editor window held the key.
        // Absent target: the menu is unchanged, the exact shape round four
        // S8 built.
        if let saveEditor {
            let save = NSMenuItem(
                title: "Save Editor",
                action: #selector(EditorSaveShortcutTarget.saveEditorWindow(_:)),
                keyEquivalent: "s")
            save.target = saveEditor
            appMenu.addItem(save)
        }
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        let menu = NSMenu(title: "Main")
        menu.addItem(appMenuItem)
        return menu
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
