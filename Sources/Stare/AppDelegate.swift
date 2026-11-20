import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureService = CaptureService()
    private lazy var overlay = OverlayController(captureService: captureService)
    private var statusBar: StatusBarController?
    private lazy var settings = SettingsWindowController(state: overlay.state)
    private var hotkey: GlobalHotkey?
    private var pointerHotkey: GlobalHotkey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diag.reset()
        Diag.log("launched path=\(Bundle.main.bundlePath)")

        statusBar = StatusBarController(
            onDraw: { [weak self] in self?.overlay.toggle() },
            onClear: { [weak self] in self?.overlay.clearAll() },
            onPointerToggle: { [weak self] in self?.overlay.togglePointer() },
            onOpenSettings: { [weak self] in self?.settings.show() }
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

        // Ask for Screen Recording now, not when the user is mid-explanation.
        // A missing permission must never surface as a system prompt on the S key.
        if !captureService.hasPermission {
            Diag.log("screen recording missing, asking at launch")
            captureService.requestPermission()
        }

        Diag.log(
            "hotkeys draw=\(hotkey != nil) pointer=\(pointerHotkey != nil) policy=\(NSApp.activationPolicy().rawValue) capture=\(captureService.hasPermission)"
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
