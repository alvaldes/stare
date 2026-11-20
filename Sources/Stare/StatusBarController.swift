import AppKit

/// Menu bar entry point. Stare has no Dock icon and no main window.
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let state: EditorState
    private let onDraw: () -> Void
    private let onClear: () -> Void
    private let onPointerToggle: () -> Void
    private let frameItem = NSMenuItem(title: "Show Drawing Frame", action: nil, keyEquivalent: "")
    private let pointerItem = NSMenuItem(title: "Pointer Highlight  ⌥⇧M", action: nil, keyEquivalent: "")
    private var glowMenuItem: NSMenuItem?
    private var fadeMenuItem: NSMenuItem?

    init(
        state: EditorState,
        onDraw: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onPointerToggle: @escaping () -> Void
    ) {
        self.onPointerToggle = onPointerToggle
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

        pointerItem.action = #selector(togglePointer)
        pointerItem.target = self
        menu.addItem(pointerItem)

        let laserMenu = NSMenu()
        for seconds in [1.0, 2.0, 3.0, 5.0] {
            let item = NSMenuItem(
                title: "\(Int(seconds)) seconds",
                action: #selector(setLaserLifetime(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = seconds
            item.state = abs(state.laserLifetime - seconds) < 0.01 ? .on : .off
            laserMenu.addItem(item)
        }
        let laserItem = NSMenuItem(title: "Laser Duration", action: nil, keyEquivalent: "")
        laserItem.submenu = laserMenu
        menu.addItem(laserItem)

        let sizeMenu = NSMenu()
        for size in [32.0, 44.0, 60.0, 80.0] {
            let item = NSMenuItem(
                title: "\(Int(size)) pt",
                action: #selector(setPointerSize(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = size
            item.state = abs(state.pointerSize - CGFloat(size)) < 0.5 ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Pointer Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let shapeMenu = NSMenu()
        for (title, value) in [("Circle", "circle"), ("Squircle", "squircle")] {
            let item = NSMenuItem(title: title, action: #selector(setPointerShape(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = state.pointerShape == value ? .on : .off
            shapeMenu.addItem(item)
        }
        let shapeItem = NSMenuItem(title: "Pointer Shape", action: nil, keyEquivalent: "")
        shapeItem.submenu = shapeMenu
        menu.addItem(shapeItem)

        let glowItem = NSMenuItem(title: "Pointer Glow", action: #selector(toggleGlow), keyEquivalent: "")
        glowItem.target = self
        glowItem.state = state.pointerGlow ? .on : .off
        glowMenuItem = glowItem
        menu.addItem(glowItem)

        let fadeItem = NSMenuItem(title: "Fade When Idle", action: #selector(toggleFade), keyEquivalent: "")
        fadeItem.target = self
        fadeItem.state = state.pointerFadeWhenIdle ? .on : .off
        fadeMenuItem = fadeItem
        menu.addItem(fadeItem)
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
    @objc private func togglePointer() { onPointerToggle() }

    @objc private func setLaserLifetime(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        state.laserLifetime = seconds
        for item in sender.menu?.items ?? [] {
            item.state = (item.representedObject as? Double) == seconds ? .on : .off
        }
    }

    @objc private func setPointerSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Double else { return }
        state.pointerSize = CGFloat(size)
        for item in sender.menu?.items ?? [] {
            item.state = (item.representedObject as? Double) == size ? .on : .off
        }
    }

    @objc private func setPointerShape(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        state.pointerShape = value
        for item in sender.menu?.items ?? [] {
            item.state = (item.representedObject as? String) == value ? .on : .off
        }
    }

    @objc private func toggleGlow() {
        state.pointerGlow.toggle()
        glowMenuItem?.state = state.pointerGlow ? .on : .off
    }

    @objc private func toggleFade() {
        state.pointerFadeWhenIdle.toggle()
        fadeMenuItem?.state = state.pointerFadeWhenIdle ? .on : .off
    }

    @objc private func toggleFrame() {
        state.showArmedFrame.toggle()
        frameItem.state = state.showArmedFrame ? .on : .off
    }
    @objc private func clear() { onClear() }
    @objc private func quit() { NSApp.terminate(nil) }
}
