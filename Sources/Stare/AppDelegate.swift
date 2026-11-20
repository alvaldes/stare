import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private var statusBar: StatusBarController?
    private var hotkey: GlobalHotkey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diag.reset()
        Diag.log("launched")

        statusBar = StatusBarController(
            state: overlay.state,
            onDraw: { [weak self] in self?.overlay.toggle() },
            onClear: { [weak self] in self?.overlay.clearAll() }
        )

        hotkey = GlobalHotkey(
            keyCode: HotkeyDefaults.keyCode,
            carbonModifiers: HotkeyDefaults.carbonModifiers
        ) { [weak self] in
            self?.overlay.toggle()
        }

        Diag.log(
            "hotkey \(HotkeyDefaults.displayName) registered=\(hotkey != nil) activePolicy=\(NSApp.activationPolicy().rawValue)"
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
