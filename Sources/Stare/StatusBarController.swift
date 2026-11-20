import AppKit

/// Menu bar entry point. Stare has no Dock icon and no main window.
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let state: EditorState
    private let onDraw: () -> Void
    private let onClear: () -> Void
    private let frameItem = NSMenuItem(title: "Show Drawing Frame", action: nil, keyEquivalent: "")

    init(state: EditorState, onDraw: @escaping () -> Void, onClear: @escaping () -> Void) {
        self.state = state
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
        frameItem.action = #selector(toggleFrame)
        frameItem.target = self
        frameItem.state = state.showArmedFrame ? .on : .off
        menu.addItem(frameItem)
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
    @objc private func toggleFrame() {
        state.showArmedFrame.toggle()
        frameItem.state = state.showArmedFrame ? .on : .off
    }
    @objc private func clear() { onClear() }
    @objc private func quit() { NSApp.terminate(nil) }
}
