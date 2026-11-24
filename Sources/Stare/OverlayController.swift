import AppKit
import Combine
import StareCore

/// One entry of the global history. A `mark` is a single mark that was added
/// or transformed on one display; a `clear` is a display's whole layer erased
/// in one step (the Escape clear, T4/S5) — one undo step, not one per mark.
private enum HistoryEntry {
    case mark(displayID: CGDirectDisplayID, strokeID: UUID)
    /// `page` is the index of the whiteboard page the clear happened on — how
    /// the entry remembers its page (T4/S5). nil on the plain overlay, which
    /// has no pages: there the entry routes to the display's own session.
    /// The index is kept in step with structural page changes by the
    /// controller's remap (see `remappingPage`), so it still names the same
    /// page after pages are deleted or reordered.
    case clear(displayID: CGDirectDisplayID, page: Int?)
    /// A group move (T6b/S8): every mark of one display's multi-selection
    /// moved together in one drag — ONE undo step, never one per mark, the
    /// same batch routing the clear entry keeps. `page` works exactly like
    /// the clear entry's: the page the move happened on, nil on the overlay.
    case batchMove(displayID: CGDirectDisplayID, page: Int?)

    /// The display the entry routes to.
    var owningDisplayID: CGDirectDisplayID {
        switch self {
        case let .mark(displayID, _): return displayID
        case let .clear(displayID, _): return displayID
        case let .batchMove(displayID, _): return displayID
        }
    }

    /// Follows a structural page change of one display: this display's
    /// page-carrying entries take the page's new index, and an entry whose
    /// page no longer exists — the page was deleted (⌘⌫) — leaves the history
    /// (returns nil, which the caller's compactMap drops), so a popped entry
    /// can never land on a neighbour's slot and mutate another page. Entries
    /// of other displays and page-less overlay entries are returned unchanged.
    func remappingPage(displayID: CGDirectDisplayID, mapping: (Int) -> Int?) -> HistoryEntry? {
        switch self {
        case .mark:
            return self
        case let .clear(id, page):
            guard id == displayID else { return self }
            guard let page else { return self }
            // Staleness case this covers: the entry's page was deleted, the
            // mapping retires it — the step has nothing left to undo anywhere,
            // so it leaves the history instead of sitting beside a stale index.
            guard let moved = mapping(page) else { return nil }
            return .clear(displayID: id, page: moved)
        case let .batchMove(id, page):
            guard id == displayID else { return self }
            guard let page else { return self }
            // Same staleness case as the clear above: the move's page was
            // deleted, the entry leaves.
            guard let moved = mapping(page) else { return nil }
            return .batchMove(displayID: id, page: moved)
        }
    }

    /// Whether this entry was wiped out of the owning display's session by a
    /// hard clear of the page the clear ran on: marks with these ids are gone
    /// with no journal trail and that page's journal itself was emptied, so
    /// both kinds are unroutable and leave the history. A hard clear in board
    /// mode only wipes the page it ran on (the presented one, `page`), so only
    /// the entries naming that page die — another page's clear keeps its undo
    /// step. A batch entry dies with its page's journal the same way a clear
    /// entry does. On the plain overlay (nil page) every entry names the one
    /// session, so every page-carrying entry of the display dies as before.
    func isWipedByHardClear(displayID: CGDirectDisplayID, clearedIDs: Set<UUID>, onPage page: Int?) -> Bool {
        switch self {
        case let .mark(id, strokeID): return id == displayID && clearedIDs.contains(strokeID)
        case let .clear(id, entryPage): return id == displayID && entryPage == page
        case let .batchMove(id, entryPage): return id == displayID && entryPage == page
        }
    }

    /// Whether this entry names one of the marks removed by an erase or a
    /// per-mark delete — the session op it named is stale where it sits.
    /// Clear and batch-move entries are never touched here: the batch each
    /// names holds the marks' snapshots inside the display's journal, and
    /// the session op skips a member gone by hand — so the entry keeps its
    /// routing.
    func namesErasedMark(displayID: CGDirectDisplayID, erasedIDs: Set<UUID>) -> Bool {
        guard case let .mark(id, strokeID) = self, id == displayID else { return false }
        return erasedIDs.contains(strokeID)
    }
}

/// Owns the drawing overlay: one panel per display, the editor state shared
/// with the toolbar, and the activate/deactivate lifecycle.
final class OverlayController {
    let state: EditorState
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
    /// Global history across displays, in real order: draws, cursor transforms
    /// and layer clears interleave exactly as they happened, newest last, so
    /// Command-Z replays the session backwards no matter which display each
    /// change happened on. Each entry routes to the owning view's session,
    /// which decides whether it removes a mark, restores geometry or brings a
    /// cleared batch back.
    private var historyOrder: [HistoryEntry] = []
    /// Undone entries waiting for Shift-Command-Z, newest last, across displays.
    private var redoOrder: [HistoryEntry] = []

    /// The page each board-committed mark was drawn on, kept parallel to the
    /// mark entries the controller maintains in its own history (one record
    /// per mark entry, dropped wherever the entry is retired). A page delete
    /// and a hard clear have to retire the mark entries naming that page even
    /// when the marks are no longer live — already inside the page's cleared
    /// journal batch, which neither a live-stroke snapshot nor an id check on
    /// the present session can see (T4/S5). Overlay marks record nothing:
    /// the drawing overlay has no pages, and its hard clear empties the whole
    /// history anyway.
    private struct MarkLocation: Hashable {
        let displayID: CGDirectDisplayID
        let strokeID: UUID
    }
    private var pageOfMark: [MarkLocation: Int] = [:]

    /// Whether this mark entry names one of `strokeIDs` of `displayID` — the
    /// retire rule the page deletion and the hard clear apply to the mark
    /// side of the history.
    private func namesMark(_ entry: HistoryEntry, ofDisplay displayID: CGDirectDisplayID, in strokeIDs: Set<UUID>) -> Bool {
        guard case let .mark(id, strokeID) = entry, id == displayID else { return false }
        return strokeIDs.contains(strokeID)
    }

    /// Retires the mark entries of one display's page: the page's journal was
    /// emptied (hard clear), so every entry naming a mark ever committed
    /// there is dead and its record is dropped with it. Entries of other
    /// pages — including marks that a previous clear on another page left
    /// waiting under their clear entry — stay exactly as they were. The page
    /// is never nil at these call sites (board mode always carries one).
    private func retireMarkEntries(ofDisplay displayID: CGDirectDisplayID, onPage page: Int?) {
        let retired = Set(
            pageOfMark
                .filter { $0.key.displayID == displayID && $0.value == page }
                .map(\.key.strokeID)
        )
        guard !retired.isEmpty else { return }
        for id in retired {
            pageOfMark.removeValue(forKey: MarkLocation(displayID: displayID, strokeID: id))
        }
        historyOrder.removeAll { self.namesMark($0, ofDisplay: displayID, in: retired) }
        redoOrder.removeAll { self.namesMark($0, ofDisplay: displayID, in: retired) }
    }
    private var toolbar: ToolbarPanel?
    /// The event monitor that gives the bar its cursor over its whole area
    /// (T6/S6). The bar's own per-view cursor paths cannot do it: the panel
    /// can never become key, so its cursor rectangles are never honoured, and
    /// the pointer events SwiftUI's hosting machinery tracks shadow the
    /// hosting view's own cursor-update handler everywhere but the gripper —
    /// which is why only the gripper's hand ever showed. The monitor runs in
    /// front of that dispatch: every pointer event the panel receives answers
    /// through `ToolbarGripperView.barCursor` — the hand pair over the
    /// gripper, the arrow over the rest of the bar — so the active tool's
    /// cursor never survives a hover over the bar. Installed while the bar is
    /// on screen, removed when it goes away, so nothing stale is left behind.
    private var toolbarCursorMonitor: Any?
    private var previousApplication: NSRunningApplication?
    private let captureService: ScreenCapturing
    /// The one preferences owner (T6 slice 1), kept so the capture tail can
    /// read the format/destination at capture time (T11/S6) and the board
    /// creation can read the whiteboard defaults at open time. Nil in the
    /// selftest harness paths that run detached on defaults.
    private let preferences: PreferencesModel?
    /// The boot-scoped session archive store (T10/S11): where the drawing
    /// sessions and the board pages are written at the mode exits and at
    /// termination, and read from when a mode opens. nil in the harness paths
    /// that run detached — nothing is stored there.
    private let sessionStore: BootSessionStore?
    /// Whether the session archive is active (T10/S11): the persisted switch
    /// reads through the preferences owner, and a detached harness keeps the
    /// shipped default, which is on.
    private var sessionPersistenceEnabled: Bool {
        guard let preferences else { return GeneralPreferences.standard.persistsSession }
        return MainActor.assumeIsolated { preferences.persistsSession }
    }
    /// Live screen frames for blur marks (T5/S3). Captures run only while the
    /// overlay is active and at least one display has a visible blur mark.
    private let liveFrames: LiveFrameSource
    private let cards = CaptureCardController()
    /// The pinned capture images (T4/S6): the shared coordinator every entry
    /// point floats into — the card's pin button and the global shortcuts.
    /// Deliberately outside the canvas lifecycle: a pinned image is not part
    /// of a drawing session, so neither `activate` nor `deactivate` touches
    /// it, and windows here outlive both.
    let pinnedImages = PinnedImageCoordinator.shared
    /// Assigned in init: the handoff closure captures the same instance, so
    /// the editor is created exactly once per controller.
    private let editor: CaptureEditorController
    /// The editor handoff the capture card's click and the session history's
    /// reopen share (T3): production is `CaptureEditorController.open`; tests
    /// inject a witness so the routing is verifiable without opening a window.
    private let openEditor: (CGImage, CapturePreference, RedactionStyle) -> Void
    /// The session capture history (T3/S12): every delivered capture is
    /// remembered here in memory only, and the History pane reopens entries
    /// through the same editor handoff the card uses. The shared store is the
    /// default so the pane can read what the overlay recorded (S4); detached
    /// instances keep tests off it.
    private let history: CaptureHistory
    /// The persisted capture history (T2a/S2a) and its paste-style panel.
    /// The panel's pick routes through `deliverHistoryPick`, the seam T2b
    /// extends with a whiteboard route. Internal so the tests can drive the
    /// panel's real event path and observe where its hiding sends focus.
    private let captureHistoryStore = CaptureHistoryStore()
    private(set) lazy var captureHistoryPanel = CaptureHistoryPanel(
        store: captureHistoryStore,
        onPick: { [weak self] image in self?.deliverHistoryPick(image) }
    )
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
        liveFrames: LiveFrameSource = LiveFrameSource(),
        preferences: PreferencesModel? = nil,
        sessionStore: BootSessionStore? = nil,
        history: CaptureHistory = .shared,
        editorHandoff: ((CGImage, CapturePreference) -> Void)? = nil
    ) {
        self.captureService = captureService
        self.liveFrames = liveFrames
        self.preferences = preferences
        self.sessionStore = sessionStore
        self.history = history
        let editor = CaptureEditorController()
        self.editor = editor
        self.openEditor = editorHandoff.map { handoff in
            { image, capture, _ in handoff(image, capture) }
        } ?? { editor.open(image: $0, capture: $1, redactionStyle: $2) }
        self.state = EditorState(preferences: preferences)
        wireEditor()
        // The panel's hiding hands key focus back to whatever was working
        // before it: the open board's canvas, or the app underneath.
        captureHistoryPanel.onHidden = { [weak self] in self?.captureHistoryPanelDidHide() }
        // Interest is asked from the canvases, so it is whatever the sessions
        // actually hold: only capture while the drawing overlay is active and
        // at least one display has a visible blur mark. The board never asks
        // for frames (S1): its blur diffs the board's own content.
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
                          state.$showArmedFrame.map { _ in () }.eraseToAnyPublisher(),
                          state.$laserLifetime.map { _ in () }.eraseToAnyPublisher(),
                          state.$pointerSize.map { _ in () }.eraseToAnyPublisher(),
                          state.$pointerShape.map { _ in () }.eraseToAnyPublisher(),
                          state.$pointerGlow.map { _ in () }.eraseToAnyPublisher(),
                          state.$pointerFadeWhenIdle.map { _ in () }.eraseToAnyPublisher()] {
            publisher.sink { [weak self] in self?.repaintCanvases() }.store(in: &cancellables)
        }
        // Leaving the edit cursor gives the selection up: a selection is only
        // meaningful while the cursor can act on it.
        state.$tool
            .sink { [weak self] tool in
                guard let self else { return }
                if !tool.isSelection { self.clearAllSelections() }
                self.repaintCanvases()
            }
            .store(in: &cancellables)
        // S3: the board scope is decided in Settings and takes effect while
        // the board is open — the canvases rebuild, the pages of the displays
        // that stay are kept (they live in `boards`, keyed by display). The
        // emitted value is used directly: @Published fires on willSet, so
        // `state.boardScope` still holds the old value here.
        state.$boardScope
            .dropFirst()
            .sink { [weak self] scope in
                guard let self, self.isBoardActive else { return }
                self.rebuildBoardCanvases(scope: scope)
            }
            .store(in: &cancellables)
        // S2: the border preference repaints the open board at once.
        state.$boardShowBorder.map { _ in () }.eraseToAnyPublisher()
            .sink { [weak self] in self?.repaintBoardCanvases() }
            .store(in: &cancellables)
        // S11: with the switch off nothing is stored, and anything already
        // stored is dropped, so the next launch is empty. The subscription
        // also fires once at launch, so stale data behind a switch that has
        // been off for a while never lingers.
        MainActor.assumeIsolated {
            preferences?.$persistsSession.sink { [weak self] persists in
                guard let self, !persists else { return }
                MainActor.assumeIsolated { self.sessionStore?.drop() }
            }
            .store(in: &cancellables)
        }
    }

    /// At most one mark is selected in the whole app: this drops every view's
    /// selection, used when a view selects elsewhere or the tool changes.
    private func clearAllSelections() {
        for canvas in canvases.values { canvas.view.clearSelection() }
        for canvas in boardCanvases.values { canvas.view.clearSelection() }
    }

    /// The canvases that are live right now: the drawing overlay, or the
    /// whiteboard while it replaces it. History entries always route here.
    private var activeCanvases: [CGDirectDisplayID: DisplayCanvas] {
        isBoardActive ? boardCanvases : canvases
    }

    /// The drawing layers the controller owns right now, exposed for
    /// `--selftest`: it has to drive the real views through the real
    /// ⌘Z/⇧⌘Z routing, which a StareCore unit test cannot reach.
    var selfTestViews: [OverlayView] {
        activeCanvases.values.map(\.view)
    }

    private func activeCanvasUnderPointer() -> DisplayCanvas? {
        isBoardActive ? boardCanvasUnderPointer() : canvasUnderPointer()
    }

    private func repaintCanvases() {
        for canvas in canvases.values {
            canvas.view.finishPendingTextEditing()
            canvas.view.syncPreferences()
            canvas.view.syncPointerFromScreen()
            canvas.view.needsDisplay = true
        }
    }

    /// Same repaint the drawing canvases get, for the open board: preference
    /// changes (the border, for one) reach every board display at once.
    private func repaintBoardCanvases() {
        for canvas in boardCanvases.values {
            canvas.view.finishPendingTextEditing()
            canvas.view.syncPreferences()
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

    /// The one editor handoff (T3): the capture card's click and the session
    /// history's reopen both land here. A mode still on screen gives way first
    /// — an armed layer would sit above the editor eating every click — and
    /// with no mode active both guards no-op. The composed image is opened as
    /// it arrived: never recomposed over what the session holds now.
    func openCaptureEditor(_ image: CGImage) {
        if isBoardActive {
            closeBoard(restoringFocus: false)
        } else {
            deactivate(restoringFocus: false)
        }
        openEditor(image, capturePreference(), state.redactionStyle)
    }

    private func wireEditor() {
        // The editor is a normal window: opening it while a layer is still
        // armed would leave it above, eating every click. The card's click and
        // the History pane's reopen share the handoff above.
        cards.onOpen = { [weak self] image in
            self?.openCaptureEditor(image)
        }
        history.onReopen = { [weak self] entry in
            self?.openCaptureEditor(entry.image)
        }
        // The card's pin button (T4/S6): floats the image on the screen the
        // card itself lives on, through the shared coordinator the global
        // shortcut and the menu item also use.
        cards.onPin = { [weak self] image, screen in
            self?.pinImage(image, on: screen)
        }
    }

    /// The card path's pin: floats one capture near the card it came from.
    func pinImage(_ image: CGImage, on screen: NSScreen?) {
        pinnedImages.pin(image, on: screen)
    }

    /// The global shortcut's pin (⌥⇧I): floats the session's latest capture
    /// where the user is. Nothing captured yet is a logged no-op.
    func pinLatestCapture() {
        pinnedImages.pinLatestCapture(from: history)
    }

    /// Read by tests: how many pinned images the controller currently has.
    var pinnedImageCount: Int { pinnedImages.windows.count }

    /// Read by the self test: the display a capture would target while a
    /// mode is active, and the board a fresh whiteboard opened with.
    var firstCanvasDisplayID: CGDirectDisplayID? { activeCanvases.values.first?.displayID }
    var activeBoard: WhiteboardPages? { isBoardActive ? boards.values.first : nil }

    /// Internal, for the tests: how many entries the global undo history
    /// holds, and what its page-carrying entries name, oldest first — nil for
    /// a mark or a page-less overlay entry. Lets a test observe that a page
    /// deletion takes the deleted page's entries out of the history while the
    /// surviving pages' entries stay.
    var historyEntryCount: Int { historyOrder.count }
    var historyNamedPages: [Int?] {
        historyOrder.map { entry -> Int? in
            switch entry {
            case .mark: return nil
            case .clear(_, let page): return page
            case .batchMove(_, let page): return page
            }
        }
    }

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    // MARK: Capture history (T2a/S2)

    /// Whether the capture history panel is on screen.
    var isCaptureHistoryVisible: Bool { captureHistoryPanel.isVisible }

    /// ⌥⇧I: opens and closes the capture history. An open drawing session
    /// yields to the panel — it is closed first (S2) — while the whiteboard
    /// stays: the panel floats above it and the board keeps its pages and
    /// marks.
    func toggleCaptureHistory() {
        if captureHistoryPanel.isVisible {
            captureHistoryPanel.hide()
            return
        }
        if isActive { deactivate(restoringFocus: false) }
        captureHistoryPanel.showPanel()
        Diag.log("capture history visible entries=\(captureHistoryStore.entries.count)")
    }
    /// What picking a history item does with its image (T2b/S2): while the
    /// whiteboard is open the pick pastes the capture onto the board's current
    /// page as its image layer; otherwise the clipboard, the same PNG + TIFF
    /// write the capture tail uses. The decision itself is the pure
    /// `HistoryPickDestination`, so the routing is testable without windows.
    /// While the board is open but has no view under the pick (a rebuild in
    /// flight), the pick falls back to the clipboard instead of being
    /// silently dropped. Internal for the tests, which drive it directly.
    func deliverHistoryPick(_ image: CGImage) {
        let boardView = isBoardActive ? boardCanvasUnderPointer()?.boardView : nil
        switch HistoryPickDestination.destination(isBoardActive: isBoardActive, hasBoardView: boardView != nil) {
        case .whiteboardPage:
            boardView?.pasteImage(image)
        case .clipboard:
            copy(image, to: NSPasteboard.general)
        }
    }

    /// The capture history panel hid (pick, Esc, the toggle-off): return key
    /// focus to the surface that was working before it — the open board's
    /// canvas, or the app underneath.
    private func captureHistoryPanelDidHide() {
        if isBoardActive {
            for canvas in boardCanvases.values {
                canvas.panel.makeFirstResponder(canvas.view)
            }
            boardCanvasUnderPointer()?.panel.makeKey()
        } else {
            restoreFrontmostApplication()
        }
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
        restoreDrawingSessions()
        for canvas in canvases.values {
            canvas.view.syncPreferences()
            canvas.panel.orderFrontRegardless()
            canvas.panel.makeFirstResponder(canvas.view)
            canvas.view.showIntroHint()
            // The area drag's frozen base is stocked now, not when ⇧S is
            // pressed: the capture's latency must not sit between the drag's
            // start and its base.
            canvas.view.stockAreaFrame()
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

        // S11: what is drawn survives leaving the mode, so the sessions are
        // stored before the canvases clear — the next activation restores
        // them. A failed write leaves the in-memory session untouched, and
        // the clear below still runs like every deactivation always has.
        saveSession()
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

    // MARK: - Session persistence (T10/S11)

    /// Writes the current drawing sessions and the boards' pages into the
    /// boot-scoped archive, at the mode exits (deactivate, board close) and
    /// at app termination. Cheap by contract: one JSON encode over the marks
    /// plus one store write, all on the caller thread — a failed encode or a
    /// skipped write never blocks, never crashes and leaves the in-memory
    /// session exactly as it was. With the persisted switch off nothing is
    /// stored, and anything already stored is dropped (S11).
    func saveSession() {
        guard let sessionStore else { return }
        guard sessionPersistenceEnabled else {
            sessionStore.drop()
            return
        }
        // The stored display map is carried forward, so a save taken while a
        // mode is closed (termination) never wipes a drawing an earlier mode
        // exit already stored; a canvas that exists now overwrites its own
        // display's entry, so cleared marks really are gone.
        let previous = sessionStore.load()
        var displays = previous?.displays ?? [:]
        for canvas in canvases.values {
            displays[String(canvas.displayID)] = canvas.view.session.persistedStrokes.map(\.persisted)
        }
        // The boards kept in memory are authoritative over their stored
        // entries when they exist; a display's board that was never opened
        // this run keeps whatever was stored for it.
        var storedBoards = previous?.boards ?? [:]
        for (displayID, board) in boards {
            storedBoards[String(displayID)] = board.persistedBoard()
        }
        sessionStore.save(SessionArchive(displays: displays, boards: storedBoards))
        Diag.log("session saved displays=\(displays.count) boards=\(storedBoards.count)")
    }

    /// Rebuilds the drawing canvases' sessions from the boot-scoped archive
    /// at activation time — what was there when the app closed or the mode
    /// was left is there again, marks with their geometry, ink, tool and
    /// numbering. Nothing stored, nothing restored: a fresh launch behaves
    /// fresh.
    private func restoreDrawingSessions() {
        guard sessionPersistenceEnabled, let archive = sessionStore?.load() else { return }
        for canvas in canvases.values {
            guard let stored = archive.displays[String(canvas.displayID)], !stored.isEmpty else { continue }
            let restored = DrawingSession.restored(strokes: stored.compactMap(Stroke.init(persisted:)))
            guard !restored.isEmpty else { continue }
            canvas.view.session = restored
        }
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
        // S11: the pages survive the board closing — they already stayed in
        // memory for the session, and the persisted switch keeps them across
        // app launches, stored here at the mode exit.
        saveSession()
        hideToolbar()
        // The marks stay on their pages, so the undo history cannot resurrect
        // them in a future overlay session: start the history clean — entries
        // and the page records behind the mark entries alike.
        historyOrder.removeAll()
        redoOrder.removeAll()
        pageOfMark.removeAll()
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
        // An area capture composes over the frame the drag froze (S11/T2b
        // slice A): the captured pixels are exactly what the user framed,
        // even if the screen changed while the drag ran. Whole-display and
        // window captures never see a frozen base.
        let frozenBase = area != nil ? canvas.view.frozenAreaBase : nil
        guard let composed = composedOverlayMarks(canvas, displayID: displayID, frozenBase: frozenBase) else { return }
        deliver(composed, area: area, canvas: canvas, displayID: displayID)
    }

    /// ⌥S: the front window only, with the marks over it. The pixels come from
    /// the same display capture every other path uses, so the marks land exactly
    /// where they were drawn; the window only decides what gets cropped out.
    func captureFrontWindow() {
        guard let target = WindowCaptureTarget.frontWindow() else {
            canvasUnderPointer()?.view.showHint("No window to capture · press S for the display", seconds: 3.5)
            Diag.log("window capture skipped: no eligible window")
            return
        }
        guard let canvas = canvases[target.displayID] else {
            Diag.log("window capture skipped: no canvas for display \(target.displayID)")
            return
        }
        guard let composed = composedOverlayMarks(canvas, displayID: target.displayID) else { return }

        // Same scale `deliver` uses for an area: the image's pixels against the
        // panel's points. A window that hangs off the display clips instead of
        // failing, and no overlap at all is a miss we say out loud.
        let scale = CGFloat(composed.width) / max(canvas.panel.frame.width, 1)
        let crop = WindowCaptureGeometry.cropRect(
            windowBounds: target.bounds,
            displayBounds: CGDisplayBounds(target.displayID),
            scale: scale,
            imageSize: CGSize(width: composed.width, height: composed.height)
        )
        guard !crop.isEmpty, let result = composed.cropping(to: crop) else {
            canvas.view.showHint("That window isn't on this display", seconds: 3.5)
            Diag.log("window capture skipped: empty crop")
            return
        }
        Diag.log("window capture window=\(target.windowID) crop=\(crop)")
        deliver(result, area: nil, canvas: canvas, displayID: target.displayID)
    }

    /// Captures one full frame of the display for a running area drag or to
    /// stock the drag's next base (S11/T2b slice A). Off the main thread, so
    /// the drag's first updates never wait for the capture; a frame that lands
    /// after its drag ended is stale and dropped by the view's lifecycle. The
    /// same own-windows-excluded one-shot capture every other capture path
    /// uses, so the frozen base is Stare's capture of the display, never the
    /// overlay's own pixels.
    private enum AreaFrameLanding {
        /// A drag in flight asked for its own frame (the fallback when no
        /// stocked frame exists); it lands through the drag's token lifecycle.
        case drag
        /// The pre-armed base: captured at activation and refreshed after each
        /// area capture, so ⇧S freezes on a frame that already exists.
        case stock
    }

    private func captureAreaFreezeFrame(
        displayID: CGDirectDisplayID,
        landing: AreaFrameLanding
    ) {
        guard let canvas = canvases[displayID] else { return }
        let captureService = self.captureService
        Task.detached(priority: .userInitiated) {
            let image = try? captureService.captureDisplay(displayID)
            DispatchQueue.main.async {
                switch landing {
                case .drag: canvas.view.landAreaFrame(image)
                case .stock: canvas.view.landStockFrame(image)
                }
            }
        }
    }

    /// The permission gate, the display's pixels and the marks composited on top:
    /// shared by the whole-display, area and window captures, so all three can
    /// only differ in what they crop afterwards. Nil after saying why. An area
    /// capture passes the drag's frozen base, so the composed pixels are the
    /// frame the user framed; every other caller captures fresh.
    private func composedOverlayMarks(
        _ canvas: DisplayCanvas,
        displayID: CGDirectDisplayID,
        frozenBase: CGImage? = nil
    ) -> CGImage? {
        // Never interrupt a session with a system prompt: the permission is asked
        // for when the app starts, and here we only say what is missing.
        guard captureService.hasPermission else {
            canvas.view.showHint("Screen Recording permission needed · System Settings → Privacy", seconds: 3.5)
            Diag.log("capture skipped: no permission")
            return nil
        }

        do {
            let base = try frozenBase ?? captureService.captureDisplay(displayID)
            let scale = CGFloat(base.width) / max(canvas.panel.frame.width, 1)

            guard let composed = MarkCompositor.composite(
                marks: canvas.view.session.strokes,
                over: base,
                scale: scale
            ) else {
                Diag.log("capture failed: composition returned nil")
                return nil
            }
            return composed
        } catch CaptureError.permissionDenied {
            canvas.view.showHint("Screen Recording permission needed · System Settings → Privacy", seconds: 3.5)
            Diag.log("capture denied by the system")
            return nil
        } catch {
            Diag.log("capture failed: \(error)")
            return nil
        }
    }

    /// Whiteboard capture: marks over a solid image of the page's background
    /// colour at the display's pixel size — never transparent, never a bare
    /// background-coloured image with nothing drawn.
    ///
    /// S1: a blur mark here diffs the board's own content — the page colour
    /// and the marks painted before it — so `diffusesContent` is on and no
    /// live frame is involved: the board never needs Screen Recording for its
    /// blur, and the desktop behind the board never shows through a patch.
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
            height: Int(pixelSize.height),
            isDark: boardView.isDarkAppearance
        ) else {
            Diag.log("board capture failed: background base image")
            return
        }
        // The page's image layer (T2b/S2) is part of everything the board
        // shows: composited into the base beneath the marks, at exactly the
        // pixels the view shows it at — the same page transform and scale the
        // marks move by below.
        let withImage = boardView.board.currentPage.image?.composited(
            over: base,
            transform: boardView.board.currentPage.transform,
            scale: scale
        ) ?? base
        guard let composed = MarkCompositor.composite(
            marks: canvas.view.session.strokes,
            over: withImage,
            scale: scale,
            diffusesContent: true,
            // The marks are stored in page space; the capture copies what the
            // board shows — the same pan and the same zoom (T5/S5), so the
            // page transform moves them into view space.
            offset: boardView.board.currentPage.offset,
            zoom: boardView.board.currentPage.zoom
        ) else {
            Diag.log("board capture failed: composition returned nil")
            return
        }
        deliver(composed, area: area, canvas: canvas, displayID: displayID)
    }

    /// The shared capture tail: crop to the requested area, then put the
    /// result where the persisted capture preference says (T11/S6). The
    /// clipboard destination keeps today's behaviour exactly — PNG and TIFF
    /// on the pasteboard — and a folder destination writes the file named by
    /// `CapturePreference.fileName(at:)` in the chosen format, saying where
    /// it went in the in-overlay pill; if the write fails the capture falls
    /// back to the clipboard instead of being lost.
    private func deliver(_ composed: CGImage, area: CGRect?, canvas: DisplayCanvas, displayID: CGDirectDisplayID) {
        let scale = CGFloat(composed.width) / max(canvas.panel.frame.width, 1)
        let result: CGImage
        if let area {
            let pixelRect = CoordinateMapping.toPixels(area, scale: scale).integral
            result = composed.cropping(to: pixelRect) ?? composed
        } else {
            result = composed
        }

        let preference = capturePreference()
        // One instant for the name and the pill, so they always agree.
        let date = Date()
        // The history holds what the user actually got (T2a): every finished
        // capture funnels through here, whatever destination the preference
        // chose. A store write failure never breaks the capture — the store
        // keeps it in memory for the session and logs.
        captureHistoryStore.add(result, date: date)
        if case .folder = preference.destination, preference.destination.isUsablePath {
            // {app} must name what was captured, never Stare itself: during a capture from
            // the whiteboard or straight after the overlay opens, Stare can be the
            // frontmost application, and a file named after the tool is a silent lie.
            let frontmost = NSWorkspace.shared.frontmostApplication
            let appName = CaptureAppIdentity.appName(
                frontmostName: frontmost?.localizedName,
                frontmostProcessIdentifier: frontmost?.processIdentifier
            )
            let displayName: String? = screen(for: canvas.displayID)?.localizedName
            if let url = CaptureFile.write(
                result, preference: preference, date: date, scale: scale,
                app: appName, displayName: displayName
            ) {
                canvas.view.showHint("Capture saved to \(url.lastPathComponent)", seconds: 3)
                Diag.log("capture saved \(result.width)x\(result.height) marks=\(canvas.view.session.strokes.count) file=\(url.lastPathComponent)")
            } else {
                copy(result, to: NSPasteboard.general)
                canvas.view.showHint("Capture couldn't be saved; copied it to the clipboard", seconds: 3.5)
                Diag.log("capture file write failed; pasted \(result.width)x\(result.height) marks=\(canvas.view.session.strokes.count)")
            }
        } else {
            copy(result, to: NSPasteboard.general)
            canvas.view.showHint("Capture copied to the clipboard", seconds: 2.2)
            Diag.log("capture copied \(result.width)x\(result.height) marks=\(canvas.view.session.strokes.count)")
        }
        // The session history (T3/S12): the composed capture as delivered —
        // the image the card shows and would open in the editor — is what
        // the History pane remembers and reopens.
        history.record(result, at: date)
        cards.show(result, on: screen(for: displayID))
    }

    /// Today's pasteboard write, extracted unchanged: both types, because
    /// some apps take PNG and others only TIFF.
    private func copy(_ image: CGImage, to pasteboard: NSPasteboard) {
        let representation = NSBitmapImageRep(cgImage: image)
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        if let png = representation.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = representation.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    /// The persisted capture preference, read at capture time so a change in
    /// Settings applies to the very next capture. The controller runs on the
    /// main thread only, like every capture-path caller.
    private func capturePreference() -> CapturePreference {
        guard let preferences else { return .standard }
        return MainActor.assumeIsolated { preferences.capture }
    }

    /// The persisted whiteboard defaults, read at board-open time (T11/S6).
    private func whiteboardDefaults() -> WhiteboardDefaults {
        guard let preferences else { return .standard }
        return MainActor.assumeIsolated { preferences.whiteboard }
    }

    /// Whether the app is currently in dark appearance (T13/S8), read through
    /// `NSApp.effectiveAppearance` and `bestMatch`. The fallback is light: when
    /// the current appearance best-matches neither (aqua, darkAqua) the board
    /// stays white — the same default the white choice implies.
    private func isDarkAppearance() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
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
                // A hard clear only wipes the presented page's session, so
                // only the entries naming that page die (the staleness case
                // the page predicate covers); the other pages' undo steps
                // stay live. The mark side retires the page's own entries
                // through the page record, which reaches the marks that a
                // clear already folded into the same page's journal.
                let clearedPage = canvas.view.historyPage
                let ids = Set(canvas.view.session.strokes.map(\.id))
                historyOrder.removeAll {
                    $0.isWipedByHardClear(displayID: canvas.displayID, clearedIDs: ids, onPage: clearedPage)
                }
                redoOrder.removeAll {
                    $0.isWipedByHardClear(displayID: canvas.displayID, clearedIDs: ids, onPage: clearedPage)
                }
                retireMarkEntries(ofDisplay: canvas.displayID, onPage: clearedPage)
                canvas.clear()
            }
            return
        }
        for canvas in canvases.values { canvas.clear() }
        historyOrder.removeAll()
        redoOrder.removeAll()
        pageOfMark.removeAll()
        liveFrames.stop()
    }

    /// Command-Z: first the mark being dragged, then the newest entry in the
    /// global history — a draw, a transform, or a layer clear on whichever
    /// display it happened. The owning view's session agrees before it acts,
    /// so a popped entry can never undo a different change than the one it
    /// names.
    func undo() {
        let canvases = activeCanvases
        if let canvas = activeCanvasUnderPointer(), canvas.discardActiveMark() { return }
        while let last = historyOrder.popLast() {
            if let canvas = canvases[last.owningDisplayID], canvas.undo(entry: last) {
                redoOrder.append(last)
                Diag.log("undo display=\(last.owningDisplayID) remaining=\(historyOrder.count)")
                return
            }
        }
        Diag.log("undo empty")
    }

    /// Shift-Command-Z: puts back the newest undone change, on the display it
    /// came from — a removed mark, a transform, or the cleared batch.
    func redo() {
        let canvases = activeCanvases
        while let last = redoOrder.popLast() {
            if let canvas = canvases[last.owningDisplayID], canvas.redo(entry: last) {
                historyOrder.append(last)
                Diag.log("redo display=\(last.owningDisplayID) remaining=\(redoOrder.count)")
                return
            }
        }
        Diag.log("redo empty")
    }

    // MARK: - Canvases

    @objc private func screenParametersChanged() {
        guard isActive || isBoardActive else { return }
        if isBoardActive {
            rebuildBoardCanvases()
            return
        }
        tearDownCanvases()
        buildCanvases()
        for canvas in canvases.values {
            canvas.panel.orderFrontRegardless()
            canvas.panel.makeFirstResponder(canvas.view)
            canvas.view.stockAreaFrame()
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
        if state.overlayScopeValue == .active, let active = screenUnderPointer() {
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
            wireHistoryAndSelection(canvas.view, displayID: displayID)
            canvas.view.onCaptureRequest = { [weak self] area in
                self?.capture(displayID: displayID, area: area)
            }
            canvas.view.onCaptureWindowRequest = { [weak self] in
                self?.captureFrontWindow()
            }
            // The live blur path: the view reads its display's latest frame and
            // reports blur interest changes so the frame source starts and
            // stops its timer on its own.
            canvas.view.displayID = displayID
            canvas.view.liveFrameSource = liveFrames
            canvas.view.onBlurMarksChanged = { [weak self] in self?.liveFrames.wake() }
            // The area drag's frozen frame (S11/T2b slice A): the drag asks
            // for one capture of this display only when no stocked frame
            // exists. Board canvases never get this wiring — the freeze is
            // out of the whiteboard's scope (S11), so a board drag stays
            // pending and paints nothing, exactly as before.
            canvas.view.onAreaSelectionFrame = { [weak self] in
                self?.captureAreaFreezeFrame(displayID: displayID, landing: .drag)
            }
            // The source of the stocked frame (S11/T2b follow-up): captured
            // when the canvas is built and again after each capture, so the
            // frame exists before ⇧S is ever pressed. Board canvases stock
            // nothing either.
            canvas.view.onAreaSelectionStockFrame = { [weak self] in
                self?.captureAreaFreezeFrame(displayID: displayID, landing: .stock)
            }
            canvases[displayID] = canvas
        }
    }

    /// One wiring for the global history and the single-selection rule, shared
    /// by the overlay and the board canvases: both draw marks, both transform
    /// them, and both report against the same cross-display history.
    private func wireHistoryAndSelection(_ view: OverlayView, displayID: CGDirectDisplayID) {
        view.onCommit = { [weak self] stroke in
            guard let self else { return }
            // Board marks record the page they were committed on. The record
            // is what lets a page deletion (or a hard clear) retire the
            // entry even when the mark is no longer live — already inside
            // the page's cleared journal batch, where no live snapshot
            // can see it. Overlay marks record nothing (there are no pages).
            if let page = view.historyPage {
                self.pageOfMark[MarkLocation(displayID: displayID, strokeID: stroke.id)] = page
            }
            historyOrder.append(.mark(displayID: displayID, strokeID: stroke.id))
            redoOrder.removeAll()
        }
        view.onTransform = { [weak self] stroke in
            guard let self else { return }
            // A transform is a history entry like a draw, in real order; the
            // session forked its own redo journal, so the global one forks too.
            // The entry carries the page the move happened on (nil on the
            // overlay), so the undo reaches that page's journal.
            if let page = view.historyPage {
                self.pageOfMark[MarkLocation(displayID: displayID, strokeID: stroke.id)] = page
            }
            historyOrder.append(.mark(displayID: displayID, strokeID: stroke.id))
            redoOrder.removeAll()
        }
        view.onBatchTransform = { [weak self, weak view] strokes in
            guard let self, let view else { return }
            // The group move (T6b/S8) is ONE global-history entry: ⌘Z pops it
            // and the owning view's batch journal restores every mark, ⇧⌘Z
            // moves them all again. The session forked its redo journal too.
            // The entry carries the page the move happened on (nil on the
            // overlay), so the undo reaches that page's journal.
            historyOrder.append(.batchMove(displayID: displayID, page: view.historyPage))
            redoOrder.removeAll()
        }
        view.onDelete = { [weak self] id in
            guard let self else { return }
            // Deleting is its own undo: the mark's entries leave the history
            // and it waits for redo, exactly like a Command-Z left it.
            historyOrder.removeAll { $0.namesErasedMark(displayID: displayID, erasedIDs: [id]) }
            redoOrder.removeAll { $0.namesErasedMark(displayID: displayID, erasedIDs: [id]) }
            redoOrder.append(.mark(displayID: displayID, strokeID: id))
            // The mark's page record goes with the retired entries (the redo
            // entry besides is a re-add the redo journal answers by id).
            self.pageOfMark.removeValue(forKey: MarkLocation(displayID: displayID, strokeID: id))
        }
        view.onClearMarks = { [weak self, weak view] in
            guard let self, let view else { return }
            // Escape with nothing selected (T4/S5): this display's marks (the
            // current whiteboard page in board mode) are cleared and drawing
            // keeps going there, and the clear enters the global history as
            // ONE undoable step — Command-Z restores everything it removed,
            // Shift-Command-Z clears it again. A clear is an edit like the
            // eraser, so the redo history forks; an empty layer is a no-op
            // that adds no history step.
            guard view.clearForUndo() else { return }
            // The entry carries the page the clear happened on (the view's
            // current page, nil on the plain overlay), so the popped entry
            // reaches that page's session whatever page is presented then.
            historyOrder.append(.clear(displayID: displayID, page: view.historyPage))
            redoOrder.removeAll()
        }
        view.onErase = { [weak self] ids in
            guard let self else { return }
            let erased = Set(ids)
            historyOrder.removeAll { $0.namesErasedMark(displayID: displayID, erasedIDs: erased) }
            redoOrder.removeAll { $0.namesErasedMark(displayID: displayID, erasedIDs: erased) }
            // The erased marks' page records go with their retired entries.
            for id in erased {
                self.pageOfMark.removeValue(forKey: MarkLocation(displayID: displayID, strokeID: id))
            }
        }
        view.onUndo = { [weak self] in self?.undo() }
        view.onRedo = { [weak self] in self?.redo() }
        view.onSelectionChanged = { [weak self] id in
            guard let self else { return }
            // One selection per app: every other display gives its own up.
            for canvas in self.activeCanvases.values where canvas.displayID != displayID {
                canvas.view.clearSelection()
            }
        }
    }

    private func tearDownCanvases() {
        for canvas in canvases.values { canvas.panel.orderOut(nil) }
        canvases.removeAll()
        liveFrames.stop()
    }

    /// Orders out every board canvas and builds the set again from scratch.
    /// The scope preference and display-parameter changes both land here.
    /// `scope` overrides the stored preference — Combine delivers the new
    /// value on willSet, before the property itself has changed. The pages
    /// live in `boards`, keyed by display and shared by identity, so a
    /// rebuild never loses the marks of the displays that stay — and a
    /// display that leaves the scope keeps its pages in memory for the
    /// session (the same rule closing the board follows); nothing is drawn
    /// away.
    private func rebuildBoardCanvases(scope: String? = nil) {
        for canvas in boardCanvases.values { canvas.panel.orderOut(nil) }
        boardCanvases.removeAll()
        buildBoardCanvases(scope: scope)
        for canvas in boardCanvases.values {
            canvas.view.syncPreferences()
            canvas.panel.orderFrontRegardless()
            canvas.panel.makeFirstResponder(canvas.view)
        }
        boardCanvasUnderPointer()?.panel.makeKey()
        syncBoardIndicator()
        Diag.log("board rebuild displays=\(boardCanvases.count) scope=\(scope ?? state.boardScope)")
    }

    // MARK: - Board canvases

    private func board(for displayID: CGDirectDisplayID) -> WhiteboardPages {
        if let existing = boards[displayID] { return existing }
        // A fresh board starts from the persisted whiteboard defaults: the
        // background is the user's, and the extra pages are created the same way
        // the toolbar's › does, so each one inherits that background.
        // The System choice (T13/S8) is resolved at board-open time, from the
        // app's effective appearance; the board is cached per display until it
        // closes, so a system theme change later never repaints an already open
        // board — it applies to the next board. The scope and the border live
        // in the same blob's defaults and are read while the board is open.
        let defaults = whiteboardDefaults()
        let background = defaults.resolvedBackground(isDarkAppearance: isDarkAppearance())
        // S11: the pages the app stored for this display earlier in the boot
        // rebuild exactly as they were — marks, backgrounds, pan, zoom and the
        // presented page. Only a board that is not already in memory restores;
        // a live board keeps being authoritative.
        let stored: PersistedBoard? = sessionPersistenceEnabled
            ? sessionStore?.load()?.boards[String(displayID)]
            : nil
        let fresh = stored.flatMap { WhiteboardPages(restoring: $0, fallbackBackground: background) }
            ?? WhiteboardPages(background: background)
        if stored == nil {
            for _ in 1..<max(defaults.pagesOnOpen, 1) {
                _ = fresh.selectNext()
            }
        }
        boards[displayID] = fresh
        return fresh
    }

    /// `scope` overrides the stored preference for this build only; nil means
    /// "read the preference", which is what opening the board does.
    private func buildBoardCanvases(scope: String? = nil) {
        // S3: the board scope is its own preference — every display, or only
        // the one under the pointer, the same rule the drawing overlay uses.
        let effectiveScope = scope ?? state.boardScope
        let screens: [NSScreen]
        if effectiveScope == "active", let active = screenUnderPointer() {
            screens = [active]
        } else {
            screens = NSScreen.screens
        }
        for screen in screens {
            guard let displayID = DisplayCanvas.displayID(of: screen),
                  let canvas = DisplayCanvas(
                    screen: screen,
                    state: state,
                    onEscape: { [weak self] in self?.closeBoard() },
                    board: board(for: displayID)
                  ) else { continue }

            wireHistoryAndSelection(canvas.view, displayID: displayID)
            canvas.view.onCaptureRequest = { [weak self] area in
                self?.capture(displayID: displayID, area: area)
            }
            // S1: nothing on the board asks for frames or Screen Recording —
            // a board canvas never gets a live frame source or a display id;
            // its blur diffs the board's own content.
            canvas.boardView?.onPageChanged = { [weak self] in
                self?.syncBoardIndicator(for: displayID)
            }
            // Structural page changes (⌘⌫ delete, ⌥← ⌥→ reorder) also feed
            // the global history: page-carrying entries follow their pages
            // instead of sliding onto a neighbour's index.
            canvas.boardView?.onPageStructureChanged = { [weak self] mapping in
                self?.remapHistoryPages(displayID: displayID, mapping: mapping)
            }
            boardCanvases[displayID] = canvas
        }
    }

    /// Keeps one display's entries on the pages they name through a
    /// structural page change (⌘⌫ delete, ⌥← ⌥→ reorder): the surviving
    /// page-carrying entries follow their pages, and everything that named
    /// the deleted page leaves the history safely — undo and redo skip it
    /// instead of landing on another page's slot (T4/S5, T6b/S8). The page's
    /// mark entries leave with it too: the page record knows the page each
    /// mark entry came from, so the marks that live on only inside the
    /// page's cleared journal batch — invisible to a live-stroke snapshot —
    /// are retired the same way their clear entry is; never pruned before,
    /// they would linger until a pop loop wasted a step refusing each one.
    private func remapHistoryPages(displayID: CGDirectDisplayID, mapping: (Int) -> Int?) {
        historyOrder = historyOrder.compactMap {
            $0.remappingPage(displayID: displayID, mapping: mapping)
        }
        redoOrder = redoOrder.compactMap {
            $0.remappingPage(displayID: displayID, mapping: mapping)
        }
        // The record follows the same mapping: pages that survive slide with
        // it, and the ids whose page vanished name the deleted page — those
        // entries retire with the page, in either order.
        var deletedIDs = Set<UUID>()
        var remapped: [MarkLocation: Int] = [:]
        for (location, page) in pageOfMark {
            if location.displayID != displayID {
                remapped[location] = page
            } else if let moved = mapping(page) {
                remapped[location] = moved
            } else {
                deletedIDs.insert(location.strokeID)
            }
        }
        pageOfMark = remapped
        guard !deletedIDs.isEmpty else { return }
        historyOrder.removeAll { self.namesMark($0, ofDisplay: displayID, in: deletedIDs) }
        redoOrder.removeAll { self.namesMark($0, ofDisplay: displayID, in: deletedIDs) }
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

    // MARK: - Board page actions (T12/S9)

    /// The current page and total of the display the pointer is on, nil when
    /// the board is closed. The menu and the toolbar read this to enable and
    /// disable the page actions.
    var boardPageState: (current: Int, total: Int)? {
        guard isBoardActive,
              let view = boardCanvasUnderPointer()?.boardView else { return nil }
        return (current: view.board.currentIndex + 1, total: view.board.count)
    }

    /// ⌘⌫ — deletes the current page on the display the pointer is on. Refused
    /// while one page remains, so the board never goes empty.
    func deleteBoardPage() {
        boardCanvasUnderPointer()?.boardView?.deleteCurrentPage()
    }

    /// ⌥← — moves the current page one slot to the left.
    func moveBoardPageLeft() {
        boardCanvasUnderPointer()?.boardView?.moveCurrentPageLeft()
    }

    /// ⌥→ — moves the current page one slot to the right.
    func moveBoardPageRight() {
        boardCanvasUnderPointer()?.boardView?.moveCurrentPageRight()
    }

    /// ⌘0 — resets the current page's pan and zoom together (T5/S5).
    func resetBoardPan() {
        boardCanvasUnderPointer()?.boardView?.resetPageView()
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
        // Same page-scoped purge as `clearAll`'s board branch: only the
        // presented page's entries die, the other pages keep their steps.
        let clearedPage = canvas.view.historyPage
        let ids = Set(canvas.view.session.strokes.map(\.id))
        historyOrder.removeAll {
            $0.isWipedByHardClear(displayID: canvas.displayID, clearedIDs: ids, onPage: clearedPage)
        }
        redoOrder.removeAll {
            $0.isWipedByHardClear(displayID: canvas.displayID, clearedIDs: ids, onPage: clearedPage)
        }
        retireMarkEntries(ofDisplay: canvas.displayID, onPage: clearedPage)
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
                },
                // The board bar alone carries the delete affordance; the
                // drawing bar is built without it (nil hides the button).
                onDeletePage: { [weak self] in
                    self?.boardCanvasUnderPointer()?.boardView?.deleteCurrentPage()
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
        toolbar.positionNearPointerDisplay(placement: state.palettePlacementValue)
        toolbar.orderFrontRegardless()
        // The bar's cursor monitor needs the move events the panel receives;
        // panels do not accept them by default (the overlay window opts in
        // itself for the same reason).
        toolbar.acceptsMouseMovedEvents = true
        installToolbarCursorMonitor()
    }

    /// Watches the pointer while the bar is on screen (T6/S6): every move,
    /// entry or cursor-update the panel receives re-answers the bar's cursor
    /// through `ToolbarGripperView.barCursor` — the hand pair over the
    /// gripper, the arrow over the rest of the bar, the tool cursor untouched
    /// everywhere off the bar. Re-answering on every event (not only on rect
    /// crossings) is what keeps a hover over the bar from ever showing the
    /// active tool's drawing cursor.
    private func installToolbarCursorMonitor() {
        guard toolbarCursorMonitor == nil else { return }
        toolbarCursorMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .mouseEntered, .cursorUpdate]
        ) { [weak self] event in
            guard let self, let toolbar = self.toolbar, event.window === toolbar else { return event }
            ToolbarGripperView.barCursor(at: event.locationInWindow, in: toolbar).set()
            return event
        }
    }

    /// Stops watching when the bar goes away (T6/S6): the monitor must not
    /// outlive the panel, and whatever sits under the bar re-asserts its own
    /// cursor on its first pointer event — the same hand-off the gripper's
    /// abandoned drag uses.
    private func removeToolbarCursorMonitor() {
        if let monitor = toolbarCursorMonitor { NSEvent.removeMonitor(monitor) }
        toolbarCursorMonitor = nil
    }

    private var toolbarMode: String?

    private func hideToolbar() {
        removeToolbarCursorMonitor()
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
    func redoMark(id: UUID) -> Bool { view.redoMark(id: id) }
    func undoMark(id: UUID) -> Bool { view.undoMark(id: id) }

    /// Routes one global-history entry against this display's session: a
    /// single mark (draw or transform), the batch the Escape clear took
    /// away (T4/S5), or the batch a group move transformed (T6b/S8). An
    /// entry that carries a page routes to that page's session (see
    /// WhiteboardView's `onPage` variants) — never to the presented page.
    /// A false return leaves the entry to the controller's pop loop, which
    /// skips it safely; that is the routing for every staleness case:
    /// - an entry whose page index the board no longer has (the board was
    ///   rebuilt with different pages, or a page was deleted without the
    ///   controller's remap, which cannot happen through the view's own ops),
    /// - an entry whose page the remap mapped away (page deleted, ⌘⌫),
    /// - an entry whose page the controller's hard clear already purged
    ///   (`isWipedByHardClear`) — those never reach here at all,
    /// - an entry whose named op is no longer the page journal's newest live
    ///   one — the session's own guard refuses it.
    fileprivate func undo(entry: HistoryEntry) -> Bool {
        switch entry {
        case let .mark(_, id): return undoMark(id: id)
        case let .clear(_, page):
            guard let page, let boardView = whiteboardView(forPage: page) else { return view.undoClearedMarks() }
            return boardView.undoClearedMarks(onPage: page)
        case let .batchMove(_, page):
            guard let page, let boardView = whiteboardView(forPage: page) else { return view.undoBatchMove() }
            return boardView.undoBatchMove(onPage: page)
        }
    }

    fileprivate func redo(entry: HistoryEntry) -> Bool {
        switch entry {
        case let .mark(_, id): return redoMark(id: id)
        case let .clear(_, page):
            guard let page, let boardView = whiteboardView(forPage: page) else { return view.redoClearedMarks() }
            return boardView.redoClearedMarks(onPage: page)
        case let .batchMove(_, page):
            guard let page, let boardView = whiteboardView(forPage: page) else { return view.redoBatchMove() }
            return boardView.redoBatchMove(onPage: page)
        }
    }

    /// The whiteboard view a page-carrying entry routes through, or nil:
    /// nil when this canvas is not a whiteboard — the plain overlay's
    /// entries carry no page, and both cases act on the view's own session
    /// exactly as they always have.
    fileprivate func whiteboardView(forPage page: Int?) -> WhiteboardView? {
        view as? WhiteboardView
    }
}
