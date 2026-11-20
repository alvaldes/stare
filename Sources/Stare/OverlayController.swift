import AppKit
import StareCore

/// Owns the drawing overlay: one panel per display, the editor state shared
/// with the toolbar, and the activate/deactivate lifecycle.
final class OverlayController {
    let state = EditorState()
    private(set) var isActive = false

    private var canvases: [CGDirectDisplayID: DisplayCanvas] = [:]
    private var toolbar: ToolbarPanel?
    private var previousApplication: NSRunningApplication?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    func activate() {
        guard !isActive, !NSScreen.screens.isEmpty else { return }
        isActive = true

        // The drawing layer has to be the thing receiving clicks and keys. As an
        // accessory app Stare shows no Dock icon and no window, so activating it
        // is invisible; the app underneath gets focus back on exit.
        rememberFrontmostApplication()
        NSApp.activate()

        buildCanvases()
        for canvas in canvases.values {
            canvas.panel.orderFrontRegardless()
            canvas.panel.makeFirstResponder(canvas.view)
            canvas.view.showIntroHint()
        }
        canvasUnderPointer()?.panel.makeKey()
        showToolbar()
        NSLog("Stare: drawing on %d display(s)", canvases.count)
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        for canvas in canvases.values { canvas.panel.orderOut(nil) }
        hideToolbar()
        clearAll()
        tearDownCanvases()
        restoreFrontmostApplication()
        NSLog("Stare: left drawing mode")
    }

    private func rememberFrontmostApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        previousApplication = application
    }

    private func restoreFrontmostApplication() {
        defer { previousApplication = nil }
        previousApplication?.activate()
    }

    func clearAll() {
        for canvas in canvases.values { canvas.clear() }
    }

    func undoOnPointerDisplay() {
        canvasUnderPointer()?.undo()
    }

    // MARK: - Canvases

    @objc private func screenParametersChanged() {
        guard isActive else { return }
        tearDownCanvases()
        buildCanvases()
        for canvas in canvases.values {
            canvas.panel.orderFrontRegardless()
            canvas.panel.makeFirstResponder(canvas.view)
        }
        canvasUnderPointer()?.panel.makeKey()
    }

    private func buildCanvases() {
        for screen in NSScreen.screens {
            guard let canvas = DisplayCanvas(
                screen: screen,
                state: state,
                onEscape: { [weak self] in self?.deactivate() }
            ) else { continue }
            canvases[canvas.displayID] = canvas
        }
    }

    private func tearDownCanvases() {
        canvases.removeAll()
    }

    private func canvasUnderPointer() -> DisplayCanvas? {
        let location = NSEvent.mouseLocation
        if let canvas = canvases.values.first(where: { $0.panel.frame.contains(location) }) {
            return canvas
        }
        return canvases.values.first
    }

    // MARK: - Toolbar

    private func showToolbar() {
        let toolbar = toolbar ?? ToolbarPanel(
            state: state,
            onUndo: { [weak self] in self?.undoOnPointerDisplay() },
            onClear: { [weak self] in self?.clearAll() },
            onDone: { [weak self] in self?.deactivate() }
        )
        self.toolbar = toolbar
        toolbar.positionNearPointerDisplay()
        toolbar.orderFrontRegardless()
    }

    private func hideToolbar() {
        toolbar?.orderOut(nil)
    }
}

/// One display's overlay panel and its marks.
final class DisplayCanvas {
    let displayID: CGDirectDisplayID
    let panel: OverlayPanel
    let view: OverlayView

    init?(screen: NSScreen, state: EditorState, onEscape: @escaping () -> Void) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }

        displayID = CGDirectDisplayID(number.uint32Value)
        panel = OverlayPanel(screen: screen)
        view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), state: state, onEscape: onEscape)
        panel.contentView = view
    }

    var isEmpty: Bool { view.isEmpty }

    func clear() { view.clear() }
    func undo() { view.undo() }
}
