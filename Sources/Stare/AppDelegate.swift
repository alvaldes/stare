import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureService = CaptureService()
    private lazy var overlay = OverlayController(captureService: captureService)
    private var statusBar: StatusBarController?
    private lazy var settings = SettingsWindowController(state: overlay.state)
    private var hotkey: GlobalHotkey?
    private var pointerHotkey: GlobalHotkey?
    private var pinHotkey: GlobalHotkey?
    private var whiteboardHotkey: GlobalHotkey?

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

        // Ask for Screen Recording now, not when the user is mid-explanation.
        // A missing permission must never surface as a system prompt on the S key.
        if !captureService.hasPermission {
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
}
