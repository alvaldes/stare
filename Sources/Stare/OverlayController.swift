import AppKit
import StareCore

/// Owns the drawing overlay: one panel per display, the editor state shared
/// with the toolbar, and the activate/deactivate lifecycle.
final class OverlayController {
    let state = EditorState()
    private(set) var isActive = false

    private var canvases: [CGDirectDisplayID: DisplayCanvas] = [:]
    private var toolbar: ToolbarPanel?

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

        buildCanvases()
        for canvas in canvases.values {
            canvas.panel.orderFrontRegardless()
        }
        // Only one window can be key; the pointer picks which display gets the
        // tool shortcuts.
        canvasUnderPointer()?.panel.makeKey()
        showToolbar()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        for canvas in canvases.values { canvas.panel.orderOut(nil) }
        hideToolbar()
        clearAll()
        tearDownCanvases()
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
        for canvas in canvases.values { canvas.panel.orderFrontRegardless() }
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
