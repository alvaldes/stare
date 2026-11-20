import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private var statusBar: StatusBarController?
    private var hotkey: GlobalHotkey?
    private var pointerHotkey: GlobalHotkey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diag.reset()
        Diag.log("launched")

        statusBar = StatusBarController(
            state: overlay.state,
            onDraw: { [weak self] in self?.overlay.toggle() },
            onClear: { [weak self] in self?.overlay.clearAll() },
            onPointerToggle: { [weak self] in self?.overlay.togglePointer() }
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

        Diag.log(
            "hotkeys draw=\(hotkey != nil) pointer=\(pointerHotkey != nil) policy=\(NSApp.activationPolicy().rawValue)"
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
