import AppKit
import Combine
import StareCore

/// Owns the drawing overlay: one panel per display, the editor state shared
/// with the toolbar, and the activate/deactivate lifecycle.
final class OverlayController {
    let state = EditorState()
    private(set) var isActive = false
    /// Pinned drawing: the marks stay on screen and every click goes to the app
    /// underneath, so the user can keep working while the drawing stays visible.
    private(set) var isPinned = false
    /// Read by the self test: drawing layers that still take clicks.
    var interactiveCanvasCount: Int {
        canvases.values.filter { !$0.panel.ignoresMouseEvents }.count
    }

    private var canvases: [CGDirectDisplayID: DisplayCanvas] = [:]
    /// Whiteboard mode (T6): one opaque board canvas per display, with the
    /// pages kept per display for the whole app session.
    private(set) var isBoardActive = false
    private var boardCanvases: [CGDirectDisplayID: DisplayCanvas] = [:]
    private var boards: [CGDirectDisplayID: WhiteboardPages] = [:]
    /// Global undo order across displays: Command-Z undoes the last mark on
    /// whichever display it was drawn, not only on the one under the pointer.
    private var commitOrder: [(displayID: CGDirectDisplayID, strokeID: UUID)] = []
    /// Undone marks waiting for Shift-Command-Z, newest last, across displays.
    private var redoOrder: [(displayID: CGDirectDisplayID, strokeID: UUID)] = []
    private var toolbar: ToolbarPanel?
    private var previousApplication: NSRunningApplication?
    private let captureService: ScreenCapturing
    /// Live screen frames for blur marks (T5/S3). Captures run only while the
    /// overlay is active and at least one display has a visible blur mark.
    private let liveFrames: LiveFrameSource
    private let cards = CaptureCardController()
    private let editor = CaptureEditorController()
    private var cancellables: Set<AnyCancellable> = []
    private var keyMonitor: Any?
    private var pointerTimer: Timer?
    private(set) var isPointerActive = false
    /// Click pulse of the pointer highlight, shared by every display. The
    /// timer below detects click edges and drives the pulse from there.
    private var pointerPulse = PointerPulse()
    /// Button state from the previous timer tick, for click-edge detection.
    private var pointerButtonWasDown = false

    init(
        captureService: ScreenCapturing = CaptureService(),
        liveFrames: LiveFrameSource = LiveFrameSource()
    ) {
        self.captureService = captureService
        self.liveFrames = liveFrames
        wireEditor()
        // Interest is asked from the canvases, so it is whatever the sessions
        // actually hold: only capture while the overlay is active and at least
        // one display has a visible blur mark.
        liveFrames.displaysNeedingFrames = { [weak self] in
            guard let self, self.isActive else { return [] }
            return self.canvases.values
                .filter { $0.view.hasLiveBlurMarks }
                .map { $0.displayID }
        }
        liveFrames.onFrame = { [weak self] displayID in
            guard let self, self.isActive, let canvas = self.canvases[displayID] else { return }
            canvas.view.invalidateLiveBlurMarks()
        }
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
                if event.modifierFlags.contains(.shift) {
                    self.redo()
                } else {
                    self.undo()
                }
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

    private func wireEditor() {
        // The editor is a normal window: opening it while a layer is still
        // armed would leave it above, eating every click.
        cards.onOpen = { [weak self] image in
            guard let self else { return }
            if self.isBoardActive {
                self.closeBoard(restoringFocus: false)
            } else {
                self.deactivate(restoringFocus: false)
            }
            self.editor.open(image: image)
        }
    }

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    /// Leaves the marks on screen and stops taking input, so the next click lands
    /// in the app underneath. Nothing else about the session changes, so the
    /// drawing is still there to continue when it is unpinned.
    func togglePin() {
        if isPinned { unpin() } else { pin() }
    }

    func pin() {
        guard isActive, !isPinned else {
            Diag.log("pin ignored active=\(isActive)")
            return
        }
        isPinned = true
        for canvas in canvases.values {
            canvas.panel.ignoresMouseEvents = true
        }
        // A pinned toolbar would still swallow clicks in its corner, and its
        // buttons cannot be used anyway while the overlay is click-through.
        hideToolbar()
        Diag.log("pin on displays=\(canvases.count)")
    }

    func unpin() {
        guard isPinned else { return }
        isPinned = false
        for canvas in canvases.values {
            canvas.panel.ignoresMouseEvents = false
            canvas.view.syncPreferences()
            canvas.panel.makeFirstResponder(canvas.view)
            canvas.view.needsDisplay = true
        }
        showToolbar()
        canvasUnderPointer()?.panel.makeKey()
        Diag.log("pin off")
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
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            // Click pulse: the mouse button is polled through the combined
            // session event source, which reports button state without any
            // permission — no Accessibility, no Input Monitoring, no prompt —
            // so pointer mode stays permission-free like the rest of the app.
            // The down edge of a click restarts the pulse.
            let isDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
            if isDown, !self.pointerButtonWasDown {
                self.pointerPulse.start(at: now)
            }
            self.pointerButtonWasDown = isDown
            let pulseScale = self.pointerPulse.scale(at: now)
            for canvas in self.canvases.values {
                canvas.view.followPointerFromScreen(pulseScale: pulseScale)
            }
        }
    }

    private func stopPointerTimer() {
        pointerTimer?.invalidate()
        pointerTimer = nil
    }

    func activate() {
        guard !isActive, !NSScreen.screens.isEmpty else { return }
        if isBoardActive { closeBoard() }
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

    /// `restoringFocus` is false when something of ours takes over: handing focus
    /// back to the previous app would race with our own window and bury it.
    func deactivate(restoringFocus: Bool = true) {
        guard isActive else { return }
        isActive = false
        isPinned = false

        for canvas in canvases.values { canvas.panel.orderOut(nil) }
        hideToolbar()
        clearAll()
        tearDownCanvases()
        liveFrames.stop()
        removeKeyMonitor()
        if restoringFocus { restoreFrontmostApplication() }
        NSCursor.arrow.set()
        Diag.log("deactivate")
    }

    // MARK: - Whiteboard

    func toggleBoard() {
        if isBoardActive { closeBoard() } else { openBoard() }
    }

    /// T6: an opaque board that covers the screen. Opening it needs no Screen
    /// Recording permission; it replaces the drawing overlay, clearing the
    /// marks the same way leaving drawing mode always has (esc = clear and
    /// leave). The pages stay in memory for the whole session.
    private func openBoard() {
        guard !isBoardActive, !NSScreen.screens.isEmpty else { return }
        if isActive { deactivate() }
        if isPointerActive { stopPointerMode() }
        isBoardActive = true

        rememberFrontmostApplication()
        NSApp.activate(ignoringOtherApps: true)

        buildBoardCanvases()
        for canvas in boardCanvases.values {
            canvas.view.syncPreferences()
            canvas.panel.orderFrontRegardless()
            canvas.panel.makeFirstResponder(canvas.view)
            canvas.view.showIntroHint()
        }
        boardCanvasUnderPointer()?.panel.makeKey()
        syncBoardIndicator()
        NSCursor.crosshair.set()
        showToolbar()
        installKeyMonitor()
        Diag.log("board open displays=\(boardCanvases.count)")

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isBoardActive else { return }
            for canvas in self.boardCanvases.values { canvas.panel.orderFrontRegardless() }
            self.toolbar?.orderFrontRegardless()
            self.boardCanvasUnderPointer()?.panel.makeKey()
        }
    }

    /// Closing the board returns to the previous behaviour: the transparent
    /// overlay behaves exactly as it did before this feature. Pages stay in
    /// memory for the session and are not persisted to disk.
    private func closeBoard(restoringFocus: Bool = true) {
        guard isBoardActive else { return }
        isBoardActive = false
        state.whiteboardPage = nil
        for canvas in boardCanvases.values {
            canvas.boardView?.storeBoardState()
            canvas.panel.orderOut(nil)
        }
        boardCanvases.removeAll()
        hideToolbar()
        // The marks stay on their pages, so the undo history cannot resurrect
        // them in a future overlay session: start the history clean.
        commitOrder.removeAll()
        redoOrder.removeAll()
        liveFrames.stop()
        removeKeyMonitor()
        if restoringFocus { restoreFrontmostApplication() }
        NSCursor.arrow.set()
        Diag.log("board close pages kept=\(boards.count)")
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
    /// While the whiteboard is open the base is the page's own solid background
    /// at display pixel size — the desktop is hidden behind the board, the
    /// result must never be transparent or black by accident, and no Screen
    /// Recording permission is needed.
    func capture(displayID: CGDirectDisplayID, area: CGRect?) {
        if isBoardActive, let canvas = boardCanvases[displayID] {
            captureBoardMarks(canvas, displayID: displayID, area: area)
            return
        }

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

            deliver(composed, area: area, canvas: canvas, displayID: displayID)
        } catch CaptureError.permissionDenied {
            canvas.view.showHint("Screen Recording permission needed · System Settings → Privacy", seconds: 3.5)
            Diag.log("capture denied by the system")
        } catch {
            Diag.log("capture failed: \(error)")
        }
    }

    /// Whiteboard capture: marks over a solid image of the page's background
    /// colour at the display's pixel size.
    private func captureBoardMarks(_ canvas: DisplayCanvas, displayID: CGDirectDisplayID, area: CGRect?) {
        guard let boardView = canvas.boardView else { return }
        let frameSize = canvas.panel.frame.size
        var pixelSize = frameSize
        // Retina captures need the pixel mode, not `CGDisplayPixelsWide`.
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            pixelSize = CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        }
        let scale = pixelSize.width / max(frameSize.width, 1)

        guard let base = boardView.board.currentPage.background.captureBase(
            width: Int(pixelSize.width),
            height: Int(pixelSize.height)
        ) else {
            Diag.log("board capture failed: background base image")
            return
        }
        guard let composed = MarkCompositor.composite(
            marks: canvas.view.session.strokes,
            over: base,
            scale: scale
        ) else {
            Diag.log("board capture failed: composition returned nil")
            return
        }
        deliver(composed, area: area, canvas: canvas, displayID: displayID)
    }

    /// The shared capture tail: crop to the requested area, copy to the
    /// pasteboard, and put the corner card up.
    private func deliver(_ composed: CGImage, area: CGRect?, canvas: DisplayCanvas, displayID: CGDirectDisplayID) {
        let scale = CGFloat(composed.width) / max(canvas.panel.frame.width, 1)
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
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[key] as? NSNumber else { return false }
            return CGDirectDisplayID(number.uint32Value) == displayID
        }
    }

    func clearAll() {
        if isBoardActive {
            for canvas in boardCanvases.values {
                let ids = Set(canvas.view.session.strokes.map(\.id))
                commitOrder.removeAll { ids.contains($0.strokeID) }
                redoOrder.removeAll { ids.contains($0.strokeID) }
                canvas.clear()
            }
            return
        }
        for canvas in canvases.values { canvas.clear() }
        commitOrder.removeAll()
        redoOrder.removeAll()
        liveFrames.stop()
    }

    /// Command-Z: first the mark being dragged, then the most recent committed
    /// mark on any display.
    func undo() {
        if let canvas = canvasUnderPointer(), canvas.discardActiveMark() { return }
        while let last = commitOrder.popLast() {
            if let canvas = canvases[last.displayID], canvas.removeMark(id: last.strokeID) {
                redoOrder.append(last)
                Diag.log("undo display=\(last.displayID) remaining=\(commitOrder.count)")
                return
            }
        }
        Diag.log("undo empty")
    }

    /// Shift-Command-Z: puts back the mark undoed last, on the display it came from.
    func redo() {
        while let last = redoOrder.popLast() {
            if let canvas = canvases[last.displayID], canvas.redoMark(id: last.strokeID) {
                commitOrder.append(last)
                Diag.log("redo display=\(last.displayID) remaining=\(redoOrder.count)")
                return
            }
        }
        Diag.log("redo empty")
    }

    // MARK: - Canvases

    @objc private func screenParametersChanged() {
        guard isActive || isBoardActive else { return }
        if isBoardActive {
            for canvas in boardCanvases.values { canvas.panel.orderOut(nil) }
            boardCanvases.removeAll()
            buildBoardCanvases()
            for canvas in boardCanvases.values {
                canvas.panel.orderFrontRegardless()
                canvas.panel.makeFirstResponder(canvas.view)
            }
            boardCanvasUnderPointer()?.panel.makeKey()
            return
        }
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
        guard isActive || isBoardActive else { return }
        for canvas in (isBoardActive ? boardCanvases : canvases).values {
            canvas.panel.orderFrontRegardless()
        }
        toolbar?.orderFrontRegardless()
        (isBoardActive ? boardCanvasUnderPointer() : canvasUnderPointer())?.panel.makeKey()
        NSCursor.crosshair.set()
    }

    private func buildCanvases() {
        // "active" limits drawing to the display the pointer is on when the
        // session starts; "all" is the documented default.
        let screens: [NSScreen]
        if state.overlayScope == "active", let active = screenUnderPointer() {
            screens = [active]
        } else {
            screens = NSScreen.screens
        }

        for screen in screens {
            guard let canvas = DisplayCanvas(
                screen: screen,
                state: state,
                onEscape: { [weak self] in self?.deactivate() }
            ) else { continue }

            let displayID = canvas.displayID
            canvas.view.onCommit = { [weak self] stroke in
                guard let self else { return }
                commitOrder.append((displayID, stroke.id))
                redoOrder.removeAll()
            }
            canvas.view.onUndo = { [weak self] in self?.undo() }
            canvas.view.onRedo = { [weak self] in self?.redo() }
            canvas.view.onCaptureRequest = { [weak self] area in
                self?.capture(displayID: displayID, area: area)
            }
            canvas.view.onErase = { [weak self] ids in
                guard let self else { return }
                let erased = Set(ids)
                self.commitOrder.removeAll { erased.contains($0.strokeID) }
                self.redoOrder.removeAll { erased.contains($0.strokeID) }
            }
            // The live blur path: the view reads its display's latest frame and
            // reports blur interest changes so the frame source starts and
            // stops its timer on its own.
            canvas.view.displayID = displayID
            canvas.view.liveFrameSource = liveFrames
            canvas.view.onBlurMarksChanged = { [weak self] in self?.liveFrames.wake() }
            canvases[displayID] = canvas
        }
    }

    private func tearDownCanvases() {
        for canvas in canvases.values { canvas.panel.orderOut(nil) }
        canvases.removeAll()
        liveFrames.stop()
    }

    // MARK: - Board canvases

    private func board(for displayID: CGDirectDisplayID) -> WhiteboardPages {
        if let existing = boards[displayID] { return existing }
        let fresh = WhiteboardPages()
        boards[displayID] = fresh
        return fresh
    }

    private func buildBoardCanvases() {
        for screen in NSScreen.screens {
            guard let displayID = DisplayCanvas.displayID(of: screen),
                  let canvas = DisplayCanvas(
                    screen: screen,
                    state: state,
                    onEscape: { [weak self] in self?.closeBoard() },
                    board: board(for: displayID)
                  ) else { continue }

            canvas.view.onCommit = { [weak self] stroke in
                guard let self else { return }
                commitOrder.append((displayID, stroke.id))
                redoOrder.removeAll()
            }
            canvas.view.onUndo = { [weak self] in self?.undo() }
            canvas.view.onRedo = { [weak self] in self?.redo() }
            canvas.view.onCaptureRequest = { [weak self] area in
                self?.capture(displayID: displayID, area: area)
            }
            canvas.view.onErase = { [weak self] ids in
                guard let self else { return }
                let erased = Set(ids)
                self.commitOrder.removeAll { erased.contains($0.strokeID) }
                self.redoOrder.removeAll { erased.contains($0.strokeID) }
            }
            canvas.view.onBlurMarksChanged = nil
            // The board covers the screen, so a blur mark cannot show the
            // desktop: no live frames are fed here and the neutral fallback
            // shows where the mark is.
            canvas.boardView?.onPageChanged = { [weak self] in
                self?.syncBoardIndicator(for: displayID)
            }
            boardCanvases[displayID] = canvas
        }
    }

    /// The toolbar's ‹ › indicator follows the display the pointer is on, since
    /// each display has its own pages.
    private func syncBoardIndicator(for displayID: CGDirectDisplayID? = nil) {
        let id = displayID ?? boardCanvasUnderPointer()?.displayID ?? boardCanvases.keys.first
        guard let id, let board = boards[id] else {
            state.whiteboardPage = nil
            return
        }
        state.whiteboardPage = (current: board.currentIndex + 1, total: board.count)
    }

    private func boardCanvasUnderPointer() -> DisplayCanvas? {
        let location = NSEvent.mouseLocation
        if let canvas = boardCanvases.values.first(where: { $0.panel.frame.contains(location) }) {
            return canvas
        }
        return boardCanvases.values.first
    }

    /// The toolbar's clear only erases the page under the pointer: the other
    /// pages and their marks stay untouched.
    private func clearCurrentBoardPage() {
        guard let canvas = boardCanvasUnderPointer() else { return }
        let ids = Set(canvas.view.session.strokes.map(\.id))
        commitOrder.removeAll { ids.contains($0.strokeID) }
        redoOrder.removeAll { ids.contains($0.strokeID) }
        canvas.clear()
    }

    private func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
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
        // The board's palette carries the page controls and Done closes the
        // board, so the panel is rebuilt when the mode changes.
        let mode = isBoardActive ? "board" : "draw"
        if toolbarMode != mode {
            toolbar?.orderOut(nil)
            toolbar = nil
            toolbarMode = mode
        }
        let toolbar = toolbar ?? (isBoardActive
            ? ToolbarPanel(
                state: state,
                onUndo: { [weak self] in self?.undo() },
                onRedo: { [weak self] in self?.redo() },
                onClear: { [weak self] in self?.clearCurrentBoardPage() },
                onDone: { [weak self] in self?.closeBoard() },
                onPreviousPage: { [weak self] in
                    self?.boardCanvasUnderPointer()?.boardView?.selectPreviousPage()
                },
                onNextPage: { [weak self] in
                    self?.boardCanvasUnderPointer()?.boardView?.selectNextPage()
                }
            )
            : ToolbarPanel(
                state: state,
                onUndo: { [weak self] in self?.undo() },
                onRedo: { [weak self] in self?.redo() },
                onClear: { [weak self] in self?.clearAll() },
                onDone: { [weak self] in self?.deactivate() }
            ))
        self.toolbar = toolbar
        toolbar.positionNearPointerDisplay(placement: state.palettePlacement)
        toolbar.orderFrontRegardless()
    }

    private var toolbarMode: String?

    private func hideToolbar() {
        toolbar?.orderOut(nil)
    }
}

/// One display's overlay or whiteboard panel and its marks.
final class DisplayCanvas {
    let displayID: CGDirectDisplayID
    let panel: OverlayWindow
    let view: OverlayView

    init?(screen: NSScreen, state: EditorState, onEscape: @escaping () -> Void, board: WhiteboardPages? = nil) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }

        displayID = CGDirectDisplayID(number.uint32Value)
        panel = OverlayWindow(screen: screen, opaqueBoard: board != nil)
        view = board.map {
            WhiteboardView(frame: CGRect(origin: .zero, size: screen.frame.size), state: state, board: $0, onEscape: onEscape)
        } ?? OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), state: state, onEscape: onEscape)
        panel.contentView = view
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// The whiteboard view, nil on the plain overlay.
    var boardView: WhiteboardView? { view as? WhiteboardView }

    var isEmpty: Bool { view.isEmpty }

    func clear() { view.clear() }
    func discardActiveMark() -> Bool { view.discardActiveMark() }
    func removeMark(id: UUID) -> Bool { view.removeMark(id: id) }
    func redoMark(id: UUID) -> Bool { view.redoMark(id: id) }
}
