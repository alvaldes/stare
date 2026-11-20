import AppKit
import Combine
import StareCore

/// Owns the drawing overlay: one panel per display, the editor state shared
/// with the toolbar, and the activate/deactivate lifecycle.
final class OverlayController {
    let state = EditorState()
    private(set) var isActive = false

    private var canvases: [CGDirectDisplayID: DisplayCanvas] = [:]
    /// Global undo order across displays: Command-Z undoes the last mark on
    /// whichever display it was drawn, not only on the one under the pointer.
    private var commitOrder: [(displayID: CGDirectDisplayID, strokeID: UUID)] = []
    private var toolbar: ToolbarPanel?
    private var previousApplication: NSRunningApplication?
    private let captureService: ScreenCapturing
    private let cards = CaptureCardController()
    private var cancellables: Set<AnyCancellable> = []
    private var keyMonitor: Any?
    private var pointerTimer: Timer?
    private(set) var isPointerActive = false

    init(captureService: ScreenCapturing = CaptureService()) {
        self.captureService = captureService
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        // The armed frame and the numbered badges follow the current ink, so a
        // change has to repaint even when nothing else moved.
        for publisher in [state.$ink.map { _ in () }.eraseToAnyPublisher(),
                          state.$tool.map { _ in () }.eraseToAnyPublisher(),
                          state.$showArmedFrame.map { _ in () }.eraseToAnyPublisher(),
                          state.$laserLifetime.map { _ in () }.eraseToAnyPublisher(),
                          state.$pointerSize.map { _ in () }.eraseToAnyPublisher(),
                          state.$pointerShape.map { _ in () }.eraseToAnyPublisher(),
                          state.$pointerGlow.map { _ in () }.eraseToAnyPublisher(),
                          state.$pointerFadeWhenIdle.map { _ in () }.eraseToAnyPublisher()] {
            publisher.sink { [weak self] in self?.repaintCanvases() }.store(in: &cancellables)
        }
    }

    private func repaintCanvases() {
        for canvas in canvases.values {
            canvas.view.finishPendingTextEditing()
            canvas.view.syncPreferences()
            canvas.view.syncPointerFromScreen()
            canvas.view.needsDisplay = true
        }
    }

    /// Command-Z must work from any display, whichever window is key, so it is
    /// intercepted before it is dispatched.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "z" {
                self.undo()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    /// Presentation mode: a click-through layer that follows the pointer so the
    /// audience sees where the user is while they keep working in another app.
    func togglePointer() {
        if isPointerActive { stopPointerMode() } else { startPointerMode() }
    }

    private func startPointerMode() {
        guard !isPointerActive, !isActive, !NSScreen.screens.isEmpty else { return }
        isPointerActive = true
        state.pointerActive = true

        buildCanvases()
        for canvas in canvases.values {
            canvas.view.showsOnlyPointer = true
            canvas.panel.ignoresMouseEvents = true
            canvas.panel.orderFrontRegardless()
            canvas.panel.level = .screenSaver
        }
        canvasUnderPointer()?.view.followPointerFromScreen()
        // Pointer mode is for working in other apps: leave the system cursor
        // alone instead of inheriting the drawing crosshair.
        NSCursor.arrow.set()
        startPointerTimer()
        Diag.log("pointer mode on displays=\(canvases.count)")
    }

    private func stopPointerMode() {
        guard isPointerActive else { return }
        isPointerActive = false
        state.pointerActive = false
        stopPointerTimer()
        tearDownCanvases()
        Diag.log("pointer mode off")
    }

    private func startPointerTimer() {
        guard pointerTimer == nil else { return }
        // NSEvent.mouseLocation needs no permission, unlike a global event tap.
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            for canvas in self.canvases.values { canvas.view.followPointerFromScreen() }
        }
    }

    private func stopPointerTimer() {
        pointerTimer?.invalidate()
        pointerTimer = nil
    }

    func activate() {
        guard !isActive, !NSScreen.screens.isEmpty else { return }
        if isPointerActive { stopPointerMode() }
        isActive = true

        // The drawing layer has to be the thing receiving clicks and keys. As an
        // accessory app Stare shows no Dock icon and no window, so activating it
        // is invisible; the app underneath gets focus back on exit.
        rememberFrontmostApplication()
        NSApp.activate(ignoringOtherApps: true)

        buildCanvases()
        for canvas in canvases.values {
            canvas.view.syncPreferences()
            canvas.panel.orderFrontRegardless()
            canvas.panel.makeFirstResponder(canvas.view)
            canvas.view.showIntroHint()
        }
        canvasUnderPointer()?.panel.makeKey()
        NSCursor.crosshair.set()
        showToolbar()
        installKeyMonitor()
        Diag.log("activate displays=\(canvases.count) active=\(NSApp.isActive)")

        // Activation is asynchronous: re-assert once it settles so the panels
        // are ordered in front of the now-active app.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive else { return }
            Diag.log("activate settled active=\(NSApp.isActive) key=\(NSApp.keyWindow != nil)")
            for canvas in self.canvases.values { canvas.panel.orderFrontRegardless() }
            self.toolbar?.orderFrontRegardless()
            self.canvasUnderPointer()?.panel.makeKey()
            NSCursor.crosshair.set()
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        for canvas in canvases.values { canvas.panel.orderOut(nil) }
        hideToolbar()
        clearAll()
        tearDownCanvases()
        removeKeyMonitor()
        restoreFrontmostApplication()
        NSCursor.arrow.set()
        Diag.log("deactivate")
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

    /// Capture, recompose the marks at pixel resolution, and put the result on
    /// the pasteboard. Nothing of Stare's interface ends up in the image: the
    /// capture filter excludes our own windows and the marks are redrawn.
    func capture(displayID: CGDirectDisplayID, area: CGRect?) {
        guard let canvas = canvases[displayID] else { return }

        // Never interrupt a session with a system prompt: the permission is asked
        // for when the app starts, and here we only say what is missing.
        guard captureService.hasPermission else {
            canvas.view.showHint("Screen Recording permission needed · System Settings → Privacy", seconds: 3.5)
            Diag.log("capture skipped: no permission")
            return
        }

        do {
            let base = try captureService.captureDisplay(displayID)
            let scale = CGFloat(base.width) / max(canvas.panel.frame.width, 1)

            guard let composed = MarkCompositor.composite(
                marks: canvas.view.session.strokes,
                over: base,
                scale: scale
            ) else {
                Diag.log("capture failed: composition returned nil")
                return
            }

            let result: CGImage
            if let area {
                let pixelRect = CoordinateMapping.toPixels(area, scale: scale).integral
                result = composed.cropping(to: pixelRect) ?? composed
            } else {
                result = composed
            }

            let representation = NSBitmapImageRep(cgImage: result)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            // Both types: some apps take PNG, others only TIFF.
            pasteboard.declareTypes([.png, .tiff], owner: nil)
            if let png = representation.representation(using: .png, properties: [:]) {
                pasteboard.setData(png, forType: .png)
            }
            if let tiff = representation.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
            Diag.log("capture copied \(result.width)x\(result.height) marks=\(canvas.view.session.strokes.count)")
            cards.show(result, on: screen(for: displayID))
        } catch CaptureError.permissionDenied {
            canvas.view.showHint("Screen Recording permission needed · System Settings → Privacy", seconds: 3.5)
            Diag.log("capture denied by the system")
        } catch {
            Diag.log("capture failed: \(error)")
        }
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[key] as? NSNumber else { return false }
            return CGDirectDisplayID(number.uint32Value) == displayID
        }
    }

    func clearAll() {
        for canvas in canvases.values { canvas.clear() }
        commitOrder.removeAll()
    }

    /// Command-Z: first the mark being dragged, then the most recent committed
    /// mark on any display.
    func undo() {
        if let canvas = canvasUnderPointer(), canvas.discardActiveMark() { return }
        while let last = commitOrder.popLast() {
            if let canvas = canvases[last.displayID], canvas.removeMark(id: last.strokeID) {
                Diag.log("undo display=\(last.displayID) remaining=\(commitOrder.count)")
                return
            }
        }
        Diag.log("undo empty")
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

    /// Windows no longer join every Space, so a Space switch is what brings the
    /// drawing layer back over the new Space.
    @objc private func activeSpaceChanged() {
        guard isActive else { return }
        for canvas in canvases.values { canvas.panel.orderFrontRegardless() }
        toolbar?.orderFrontRegardless()
        canvasUnderPointer()?.panel.makeKey()
        NSCursor.crosshair.set()
    }

    private func buildCanvases() {
        for screen in NSScreen.screens {
            guard let canvas = DisplayCanvas(
                screen: screen,
                state: state,
                onEscape: { [weak self] in self?.deactivate() }
            ) else { continue }

            let displayID = canvas.displayID
            canvas.view.onCommit = { [weak self] stroke in
                self?.commitOrder.append((displayID, stroke.id))
            }
            canvas.view.onUndo = { [weak self] in self?.undo() }
            canvas.view.onCaptureRequest = { [weak self] area in
                self?.capture(displayID: displayID, area: area)
            }
            canvas.view.onErase = { [weak self] ids in
                guard let self else { return }
                let erased = Set(ids)
                self.commitOrder.removeAll { erased.contains($0.strokeID) }
            }
            canvases[displayID] = canvas
        }
    }

    private func tearDownCanvases() {
        for canvas in canvases.values { canvas.panel.orderOut(nil) }
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
            onUndo: { [weak self] in self?.undo() },
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
    let panel: OverlayWindow
    let view: OverlayView

    init?(screen: NSScreen, state: EditorState, onEscape: @escaping () -> Void) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }

        displayID = CGDirectDisplayID(number.uint32Value)
        panel = OverlayWindow(screen: screen)
        view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), state: state, onEscape: onEscape)
        panel.contentView = view
    }

    var isEmpty: Bool { view.isEmpty }

    func clear() { view.clear() }
    func discardActiveMark() -> Bool { view.discardActiveMark() }
    func removeMark(id: UUID) -> Bool { view.removeMark(id: id) }
}
