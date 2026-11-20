import AppKit

/// Menu bar entry point. Stare has no Dock icon and no main window.
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onDraw: () -> Void
    private let onClear: () -> Void

    init(onDraw: @escaping () -> Void, onClear: @escaping () -> Void) {
        self.onDraw = onDraw
        self.onClear = onClear
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "pencil.tip",
                accessibilityDescription: "Stare"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(menuItem(title: "Draw Over Screen  ⌥⇧A", action: #selector(draw)))
        menu.addItem(menuItem(title: "Clear Drawing", action: #selector(clear)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit Stare", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func draw() { onDraw() }
    @objc private func clear() { onClear() }
    @objc private func quit() { NSApp.terminate(nil) }
}
