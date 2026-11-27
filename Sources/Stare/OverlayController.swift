import AppKit
import Combine
import ImageIO
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
    /// A board image-layer edit (L8): a paste, a move, a resize, a delete or an
    /// Escape cleared the page's image. Carries the placement BEFORE and AFTER,
    /// so undo puts back what was there (nil when the page carried nothing) and
    /// redo re-applies the edit. `page` works exactly like the other
    /// page-carrying entries. The layers share their `CGImage`: an entry holds
    /// two references, never two copies of the picture.
    case boardImage(
        displayID: CGDirectDisplayID, page: Int?, before: BoardImage?, after: BoardImage?
    )

    /// The entry's kind, for the diagnostics: which step was skipped and why the
    /// undo loop could not apply it.
    var debugKind: String {
        switch self {
        case .mark: return "mark"
        case .clear: return "clear"
        case .batchMove: return "batchMove"
        case .boardImage: return "boardImage"
        }
    }

    /// The display the entry routes to.
    var owningDisplayID: CGDirectDisplayID {
        switch self {
        case let .mark(displayID, _): return displayID
        case let .clear(displayID, _): return displayID
        case let .batchMove(displayID, _): return displayID
        case let .boardImage(displayID, _, _, _): return displayID
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
        case let .boardImage(id, page, before, after):
            guard id == displayID else { return self }
            guard let page else { return self }
            guard let moved = mapping(page) else { return nil }
            return .boardImage(displayID: id, page: moved, before: before, after: after)
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
        // The image layer is session state like the pages themselves, so the
        // board's boot archive never held it and a hard clear cannot have wiped
        // it: the entry survives with its placement intact.
        case .boardImage: return false
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

/// The {app}/{display} identity a delivered capture was resolved with (S5),
/// kept so a later editor handoff — which carries only the image — can name
/// THAT capture truthfully. Keyed by the image's object identity, and the
/// RETAINED image sits in the entry: a non-retaining key proved unsound in
/// the RED run, because a freed CGImage's address gets recycled by a later
/// allocation and the identity of one capture silently reaches for another
/// (the worker's own eviction probe caught a count that never grew past
/// four). Retaining is bounded by the cap and holds nothing the session
/// history does not already hold for the session; whatever is not here —
/// an edited variant, a capture from a previous session, an evicted one —
/// reads back as `.unknown`, and BOTH paths (the save panel's preview and
/// the file it writes) agree on the same refusal into the prefix fallback.
final class EditorIdentityLedger {
    private let limit: Int
    private var entries: [(image: CGImage, identity: CaptureEditorIdentity)] = []

    init(limit: Int) { self.limit = max(1, limit) }

    /// Registers the capture tail's ONE resolution for an image, replacing
    /// any older entry for the same image, trimming to the bound.
    func register(_ image: CGImage, identity: CaptureEditorIdentity) {
        let key = ObjectIdentifier(image)
        entries.removeAll { ObjectIdentifier($0.image) == key }
        entries.append((image, identity))
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    /// The identity a capture was resolved with, or `.unknown` — never a
    /// stale name for a capture the ledger evicted. The lookup is the
    /// object's identity: a pixel-equal but distinct capture inherits
    /// nothing, because an identical capture is a different capture.
    func identity(for image: CGImage) -> CaptureEditorIdentity {
        let key = ObjectIdentifier(image)
        return entries.reversed().first { ObjectIdentifier($0.image) == key }?.identity ?? .unknown
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
    /// The hidden tools' own window (T6), alive only while the bar asks for it.
    private var overflowPanel: ToolbarOverflowPanel?
    /// Closes the extras panel on the first interaction that is not one of its
    /// own tools: a press anywhere else in the app, a key, a scroll, or the app
    /// itself going away. Without it the panel stayed up while the bar was dragged
    /// by its gripper and the hidden tools were left floating on their own.
    private var overflowDismissMonitor: Any?
    private var appResignedObserver: (any NSObjectProtocol)?
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
    /// Re-answers the pointer while it is over a capture card (B9).
    private var cardCursorMonitor: Any?
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
    /// The fourth argument (T5/S5) is the capture's naming identity the
    /// handoff threads into the editor's save panel; the injected test
    /// witness is the old (image, capture) contract — its assertions were
    /// never about which app was captured.
    private let openEditor: (CGImage, CapturePreference, RedactionStyle, CaptureEditorIdentity, CaptureEditorSaveTarget) -> Void

    /// The {app}/{display} identity per capture kept for the editor handoff
    /// (S5): the capture tail resolves them once and registers them here, so
    /// the card's click or a history reopen names THAT capture truthfully
    /// even when the destination was the clipboard and nothing was written.
    /// Bounded and identity-keyed, the images retained — see the ledger's
    /// own doc above for why the retention is exact and capped.
    private let editorIdentities: EditorIdentityLedger
    /// How many captures' identities the editor handoff keeps (S5): recent,
    /// but a session-history-sized cap on the entries, so an old capture
    /// reopens with the refused tokens rather than a stale name.
    static let identityLedgerLimit = 16
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
    private let captureHistoryStore = CaptureHistoryStore.shared
    private(set) lazy var captureHistoryPanel = CaptureHistoryPanel(
        store: captureHistoryStore,
        // Read on every open, so the thumbnail size chosen in Settings (B1)
        // reaches the next panel instead of the one built at launch.
        thumbnailSize: { [weak self] in
            self?.preferences?.history.thumbnailSize ?? HistoryPreference.defaultThumbnailSize
        },
        onPick: { [weak self] image in self?.deliverHistoryPick(image) },
        // The context menu's Edit (S2) goes through the ONE editor handoff
        // the capture card and the session history share — a history re-open
        // from an earlier session reads as no identity, and the handoff's
        // own contract refuses the {app}/{display} tokens into the prefix
        // fallback for it.
        onEdit: { [weak self] image in self?.openCaptureEditor(image) }
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
        // The state is created before the editor handoff is wired: the
        // overlay's mirrors no longer seed the editor (S4 withdrew the
        // snapshot, L4), but the state must still exist for the overlay
        // itself.
        let editorState = EditorState(preferences: preferences)
        self.state = editorState
        let editor = CaptureEditorController()
        self.editor = editor
        self.editorIdentities = EditorIdentityLedger(limit: Self.identityLedgerLimit)
        self.openEditor = editorHandoff.map { handoff in
            { image, capture, _, _, _ in handoff(image, capture) }
        } ?? { image, capture, redactionStyle, identity, saveTarget in
            // S4: the editor's chrome is always the horizontal row at the
            // top — the read-only snapshot T1 once took of the user's bar
            // configuration is withdrawn (L4) — so the handoff carries only
            // the capture itself plus its naming identity (S5) and the Save
            // target the opening names (S2). The editor still never receives
            // the preferences model, so nothing it does can persist into the
            // saved bar.
            editor.open(
                image: image, capture: capture, redactionStyle: redactionStyle,
                app: identity.app, displayName: identity.displayName,
                saveTarget: saveTarget
            )
        }
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

    // MARK: Round four S7: the history close's focus rule

    /// Where closing the capture history hands key focus (round four S7):
    /// the fallbacks named in the spec, in its own order. An editor standing
    /// open takes the focus back (the window the user was likely headed to);
    /// with no editor the open board's canvas keeps the standing rule the
    /// picks' delivery path has always served; with neither, the FINDER is
    /// activated — never the app that happened to be frontmost before the
    /// sheet opened.
    enum HistoryFocusDestination: Equatable {
        case editor
        case boardCanvas
        case finder

        static func destination(hasOpenEditorWindow: Bool, isBoardActive: Bool) -> HistoryFocusDestination {
            if hasOpenEditorWindow { return .editor }
            if isBoardActive { return .boardCanvas }
            return .finder
        }
    }

    /// The Finder activation seam (round four S7): the history's close asks
    /// this for the third fallback. Default to the real workspace
    /// activation of the Finder app; tests inject a witness.
    var activateFinder: () -> Void = { OverlayController.activateFinderApplication() }

    /// The editor-activation seam (round four S7): how the standing editor
    /// window takes the foreground back. Default to the REAL AppKit
    /// activation — the window made key and front; the headless harness
    /// cannot answer `isKeyWindow`, so a test witnesses the route instead.
    var makeEditorKey: (CaptureEditorWindow) -> Void = { $0.makeKeyAndOrderFront(nil) }

    /// The real Finder activation: the Finder app's own `activate`, the same
    /// one-call hand-off the frontmost-restore keeps. The Finder is always
    /// running on macOS; a miss is a silent no-op, never a crash.
    static func activateFinderApplication() {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.finder" }?
            .activate(options: [])
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
                Diag.log("key monitor saw command-z shift=\(event.modifierFlags.contains(.shift))")
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
    /// it arrived: never recomposed over what the session holds now. The
    /// capture's naming identity (S5) is read from the ledger the capture
    /// tail filled at delivery — the same resolution the folder save wrote
    /// with, so the save panel this opens previews and writes the very name
    /// that capture owns; an image the ledger does not hold (a previous
    /// session's, an edited variant, an evicted one) arrives as none, and
    /// the {app}/{display} tokens refuse into the prefix fallback exactly
    /// as the contract says both paths agree on. The Save target (S2) is
    /// resolved here too: a history-sheet Edit hands over the image the
    /// store's own cache holds, so a holding entry IS what its editor's
    /// Save rewrites; a foreign image keeps the capture save.
    func openCaptureEditor(_ image: CGImage) {
        let target = captureHistoryStore.entry(for: image)
            .map { CaptureEditorSaveTarget.historyEntry($0.id) } ?? .capture
        openCaptureEditor(image, captureIdentity: editorIdentities.identity(for: image), saveTarget: target)
    }

    /// The handoff with the Save target threaded explicitly (editor
    /// -save-in-place S2): the Finder's path threads `.storedFile(url)`,
    /// the card's route threads `.capture`, and no caller guesses.
    func openCaptureEditor(_ image: CGImage, saveTarget: CaptureEditorSaveTarget) {
        openCaptureEditor(image, captureIdentity: editorIdentities.identity(for: image), saveTarget: saveTarget)
    }

    /// The handoff with the naming identity threaded (S5): the overload the
    /// image-only one dispatches through, split so a test can pin what the
    /// ledger resolves without driving a deliver. The Save target rides
    /// alongside it (S2). Internal so the tests drive the routing without
    /// opening a window.
    func openCaptureEditor(
        _ image: CGImage, captureIdentity: CaptureEditorIdentity,
        saveTarget: CaptureEditorSaveTarget = .capture
    ) {
        if isBoardActive {
            closeBoard(restoringFocus: false)
        } else {
            deactivate(restoringFocus: false)
        }
        openEditor(image, capturePreference(), state.redactionStyle, captureIdentity, saveTarget)
    }

    /// The capture tail's ONE identity registration (S5), exposed internal so
    /// the tests pin the ledger's per-image keys and its bound without
    /// driving a real deliver: the tests register the exact resolution the
    /// tail makes and read back through the same lookup the handoff makes.
    func registerCaptureIdentity(_ image: CGImage, _ identity: CaptureEditorIdentity) {
        editorIdentities.register(image, identity: identity)
    }

    /// The windows the editor stands open — the seam a Dock/open-route test
    /// reads the produced windows through (round four S6).
    var editorWindowsForTesting: [CaptureEditorWindow] { editor.windowsForTesting }

    /// The Finder's "Open With" route (round four S6): a file the system asks
    /// Stare to open becomes an editor handoff — the SAME ONE
    /// `openCaptureEditor` the capture cards and the session history share,
    /// identity resolution included (an opened file is a foreign image: an
    /// unknown naming identity, the same refusal into the prefix fallback).
    /// The decode happens here, never in the delegate, and a file that is not
    /// an image changes nothing. Returns whether a handoff ran.
    @discardableResult
    func openFileInEditor(at url: URL) -> Bool {
        let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, noCache),
            let image = CGImageSourceCreateImageAtIndex(source, 0, noCache) else {
            Diag.log("open with stare: \(url.lastPathComponent) decoded to no image")
            return false
        }
        openCaptureEditor(image, saveTarget: .storedFile(url))
        return true
    }

    /// The identity for an image, read the way the handoff reads it (S5) —
    /// internal for the tests, the same lookup production makes.
    func editorIdentity(for image: CGImage) -> CaptureEditorIdentity {
        editorIdentities.identity(for: image)
    }

    private func wireEditor() {
        // The editor's own captures come back through the same recording an
        // overlay capture goes through (L7).
        editor.onDeliver = { [weak self] composed in self?.deliverEdited(composed) }
        // editor-save-in-place S2 + the open-sheet rule: the ONE store call
        // an in-place history save makes — every editor window routes through
        // this rewrite — AND, when it succeeds, the open sheet's own re-read:
        // the store cannot tell a visible sheet, so the seam runs the panel
        // model's refresh, and the sheet shows the saved pixels and the front
        // position the changed capture took (the store moves the rewritten
        // entry to the front) the moment the save lands.
        editor.rewriteHistoryEntry = { [weak self] composed, id in
            guard let self else { return false }
            let rewrote = self.captureHistoryStore.rewrite(entryID: id, with: composed)
            if rewrote {
                // The save ran on the editor's main thread; the model is
                // main-actor isolated, the same assumed hop the app's launch
                // path owns.
                MainActor.assumeIsolated {
                    self.captureHistoryPanel.model.refresh()
                }
            }
            return rewrote
        }
        // The editor is a normal window: opening it while a layer is still
        // armed would leave it above, eating every click. The card's click and
        // the History pane's reopen share the handoff above; the card's route
        // names its Save explicitly (S2): the capture save — a folder
        // destination's write, a clipboard's Save As fallback — never the
        // history sheet's entry-rewrite.
        cards.onOpen = { [weak self] image in
            self?.openCaptureEditor(image, saveTarget: .capture)
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
        // The card's copy control (C3/S4): the capture tail's ONE pasteboard
        // write — the same `copy(_:to:)` the delivery, the history pick and
        // the write-failure fallback answer. The card carries no writer of
        // its own, so the row can never produce bytes a delivery would not.
        cards.onCopy = { [weak self] image in
            guard let self else { return }
            self.copy(image, to: self.pasteboard)
        }
        cards.onSave = { [weak self] image in
            self?.saveFromCard(image)
        }
    }

    /// The card path's pin: floats one capture near the card it came from.
    func pinImage(_ image: CGImage, on screen: NSScreen?) {
        pinnedImages.pin(image, on: screen)
    }

    /// The card's save control (C3/S4): the capture tail's OWN file path —
    /// `CaptureFile.write` into the persisted capture destination, read at
    /// action time like the delivery path reads it. Its failure rule is the
    /// one `deliver` applies: nothing writable, the capture lands on the
    /// clipboard instead of being lost — which is exactly the clipboard
    /// destination's own behaviour too. The write is NOT a new capture: the
    /// card never re-commits (S2), so neither history sees another entry —
    /// the one this capture earned was written at delivery. Internal so the
    /// tests drive the real routing.
    func saveFromCard(_ image: CGImage) {
        let date = Date()
        if let url = CaptureFile.write(image, preference: capturePreference(), date: date) {
            Diag.log("card saved \(url.lastPathComponent)")
            return
        }
        copy(image, to: pasteboard)
        Diag.log("card save not writable; copied \(image.width)x\(image.height)")
    }

    /// The card stack, so the tests can drive the cards the capture tail
    /// feeds into and reach the card's corner controls through the wiring
    /// this controller installed (C3/S4). Detached tests close what they open.
    var captureCardsForTesting: CaptureCardController { cards }

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
            case .boardImage(_, let page, _, _): return page
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
        // The panel is a non-activating window: it can be key inside Stare and
        // still receive nothing while another app is frontmost, so the arrows,
        // Return and Esc would die and Return would land in the app underneath
        // and paste its stale clipboard. Activating here is what makes the
        // keyboard work at all; the hide hook hands the foreground back.
        rememberFrontmostApplication()
        NSApp.activate(ignoringOtherApps: true)
        captureHistoryPanel.showPanel()
        Diag.log("capture history visible entries=\(captureHistoryStore.entries.count) active=\(NSApp.isActive)")
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
            copy(image, to: pasteboard)
        }
    }

    /// The editor's capture tail (L7): a composed variant the user copies or
    /// saves is a new capture like any other, so it lands in both histories the
    /// way `deliver` puts one there — the on-disk store and the session list.
    /// No canvas, no display and no destination preference are involved: the
    /// editor's own save panel already wrote the file the user chose, and the
    /// card stays away so the editor in front is not covered by its own copy.
    func deliverEdited(_ composed: CGImage) {
        let date = Date()
        captureHistoryStore.add(composed, date: date)
        history.record(composed, at: date)
        Diag.log("editor delivered \(composed.width)x\(composed.height)")
    }

    /// The capture history panel hid (pick, Esc, the toggle-off): hand key
    /// focus where it belongs (round four S7) — to the editor window when one
    /// stands open (a REAL activation, the editor made key — e.g. the Edit
    /// action from the sheet's own context menu), else to the open board's
    /// canvas (the standing rule the picks' delivery keeps), else to the
    /// FINDER (a real activation) — never to whatever app happened to be
    /// frontmost before the sheet opened.
    private func captureHistoryPanelDidHide() {
        switch HistoryFocusDestination.destination(
            hasOpenEditorWindow: editor.hasOpenWindow, isBoardActive: isBoardActive
        ) {
        case .editor:
            guard let window = editor.frontmostWindow else { return }
            makeEditorKey(window)
        case .boardCanvas:
            for canvas in boardCanvases.values {
                canvas.panel.makeFirstResponder(canvas.view)
            }
            boardCanvasUnderPointer()?.panel.makeKey()
        case .finder:
            activateFinder()
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
        installCardCursorMonitor()
        Diag.log("activate displays=\(canvases.count) active=\(NSApp.isActive)")

        // Ordering the panels and taking the keyboard are asynchronous: a mode
        // cycle can lose that race (the log shows `active=false key=false`), and
        // an inactive app never sees ⌘Z — this controller routes undo from a
        // LOCAL monitor, which only receives our own events. That was the
        // "undo stops working after closing and opening a mode" report.
        for canvas in canvases.values { canvas.panel.orderFrontRegardless() }
        toolbar?.orderFrontRegardless()
        NSCursor.crosshair.set()
        assertActivation()
    }

    /// S7 (round three): whether one of the app's own screen-holding overlay
    /// surfaces is up — drawing, the board, or the pointer highlight. Opening
    /// Settings while one holds the screen needs the window lifted above the
    /// app's own levels, or it opens behind the `.screenSaver` panels and the
    /// ⌘, that opened it looks like a keystroke that did nothing; this is the
    /// one question the open path asks, so a caller never couples to which
    /// flags make a mode a mode.
    var isAnyOverlaySurfaceActive: Bool {
        isActive || isBoardActive || isPointerActive
    }

    /// Makes Stare the active app with its mode's panel key, retrying while the
    /// system settles. One `async` hop is not enough: after a mode cycle the
    /// activation loses to the app that was handed focus back, and it stays lost.
    private func assertActivation(attempt: Int = 0) {
        guard isActive || isBoardActive else { return }
        NSApp.activate(ignoringOtherApps: true)
        let canvas = isBoardActive ? boardCanvasUnderPointer() : canvasUnderPointer()
        canvas?.panel.orderFrontRegardless()
        canvas?.panel.makeKeyAndOrderFront(nil)
        if let canvas { canvas.panel.makeFirstResponder(canvas.view) }
        let active = NSApp.isActive
        let key = canvas?.panel.isKeyWindow == true
        if active && key {
            Diag.log("activation settled attempt=\(attempt) active=true key=true")
            return
        }
        guard attempt < 10 else {
            Diag.log("activation gave up attempt=\(attempt) active=\(active) key=\(key)")
            return
        }
        requeueActivationRetry(attempt: attempt + 1)
    }

    /// The retry's queued turn is a stored, cancellable work item, not an
    /// anonymous `asyncAfter` closure. This is the gate that keeps the queued
    /// `NSApp.activate` / `makeKeyAndOrderFront` re-asserts from firing into
    /// whatever runs after the mode's owner is gone — a pump can fire a queued
    /// turn after the test (or the caller) tore the mode down, and an open
    /// closure would run blind work that re-activates a dead state into the
    /// next window that measures itself. Two layers:
    /// 1. the owner's exits (`deactivate`, `closeBoard`) cancel the item, so a
    /// cancelled turn never runs at all, even while the controller itself is
    /// still alive (a test's property may retain it past the mode's exit);
    /// 2. the attempt body's own mode guard (`isActive || isBoardActive`)
    /// answers nothing once the mode flags are down, for any turn that does
    /// slip through.
    private var activationRetry: DispatchWorkItem?

    private func requeueActivationRetry(attempt: Int) {
        activationRetry?.cancel()
        let retry = DispatchWorkItem { [weak self] in
            self?.assertActivation(attempt: attempt)
        }
        activationRetry = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: retry)
    }

    /// Cancels the queued retry turn. Every exit of the owning mode calls this,
    /// so nothing queued re-activates after the mode left the screen.
    private func cancelActivationRetry() {
        activationRetry?.cancel()
        activationRetry = nil
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
        removeCardCursorMonitor()
        if restoringFocus { restoreFrontmostApplication() }
        NSCursor.arrow.set()
        cancelActivationRetry()
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
            let restored = DrawingSession.restoredUndoable(strokes: stored.compactMap(Stroke.init(persisted:)))
            guard !restored.isEmpty else { continue }
            canvas.view.session = restored
            // The marks came back; their undo steps come back with them, so ⌘Z
            // after a mode cycle removes what the user is looking at instead of
            // finding an empty history (the log showed `entries=2 / undo empty`:
            // the steps that existed named work the restored session no longer
            // held).
            for stroke in restored.strokes {
                historyOrder.append(.mark(displayID: canvas.displayID, strokeID: stroke.id))
            }
            Diag.log("sessions restored display=\(canvas.displayID) strokes=\(restored.strokes.count)")
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
        // NOT `deactivate()`: its default restores focus to the app the user came
        // from, and that activation can land AFTER the `NSApp.activate` below —
        // Stare ends up in the background with its panel non-key, so ⌘Z (which
        // this controller routes from a local monitor and therefore needs our app
        // to be the active one) never arrives. Switching modes is not leaving to
        // another app.
        if isActive { deactivate(restoringFocus: false) }
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
        Diag.log("board open active=\(NSApp.isActive) key=\(boardCanvasUnderPointer()?.panel.isKeyWindow == true) canvases=\(boardCanvases.count)")
        syncBoardIndicator()
        NSCursor.crosshair.set()
        showToolbar()
        installKeyMonitor()
        installCardCursorMonitor()
        Diag.log("board open displays=\(boardCanvases.count)")

        assertActivation()
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
        // The history is KEPT (L35): the pages and the marks survive the board
        // closing, and they come back with their ids, so their undo steps still
        // apply. Clearing here left the owner looking at a stroke on screen with
        // nothing to undo — `entries=0` in the log right after returning.
        liveFrames.stop()
        removeKeyMonitor()
        removeCardCursorMonitor()
        if restoringFocus { restoreFrontmostApplication() }
        NSCursor.arrow.set()
        cancelActivationRetry()
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
    /// back to the clipboard instead of being lost (S5: the name and the
    /// editor handoff both take the identity resolved below, one place).
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
        // The naming identity, resolved ONCE for every destination (S5): the
        // folder save's {app}/{display} tokens and the later editor handoff
        // (the card's click, a history reopen) must take the same values, so
        // the save panel previews and writes the name this capture was
        // resolved with. {app} must name what was captured, never Stare
        // itself: during a capture from the whiteboard, or straight after
        // the overlay opens, Stare can be the frontmost application, and a
        // file named after the tool is a silent lie.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let appName = CaptureAppIdentity.appName(
            frontmostName: frontmost?.localizedName,
            frontmostProcessIdentifier: frontmost?.processIdentifier
        )
        let displayName: String? = screen(for: canvas.displayID)?.localizedName
        // The history holds what the user actually got (T2a): every finished
        // capture funnels through here, whatever destination the preference
        // chose. A store write failure never breaks the capture — the store
        // keeps it in memory for the session and logs. The identity is
        // registered for the S5 handoff before anything else, so the editor
        // opens from this capture with the values the resolution made, not
        // ones a later frontmost report would say.
        editorIdentities.register(
            result, identity: CaptureEditorIdentity(app: appName, displayName: displayName))
        captureHistoryStore.add(result, date: date)
        if case .folder = preference.destination, preference.destination.isUsablePath {
            if let url = CaptureFile.write(
                result, preference: preference, date: date, scale: scale,
                app: appName, displayName: displayName
            ) {
                canvas.view.showHint("Capture saved to \(url.lastPathComponent)", seconds: 3)
                Diag.log("capture saved \(result.width)x\(result.height) marks=\(canvas.view.session.strokes.count) file=\(url.lastPathComponent)")
            } else {
                copy(result, to: pasteboard)
                canvas.view.showHint("Capture couldn't be saved; copied it to the clipboard", seconds: 3.5)
                Diag.log("capture file write failed; pasted \(result.width)x\(result.height) marks=\(canvas.view.session.strokes.count)")
            }
        } else {
            copy(result, to: pasteboard)
            canvas.view.showHint("Capture copied to the clipboard", seconds: 2.2)
            Diag.log("capture copied \(result.width)x\(result.height) marks=\(canvas.view.session.strokes.count)")
        }
        // The session history (T3/S12): the composed capture as delivered —
        // the image the card shows and would open in the editor — is what
        // the History pane remembers and reopens.
        history.record(result, at: date)
        cards.show(result, on: screen(for: displayID))
        // A capture ends the drawing mode (owner's call): the result is what was
        // asked for, so the overlay gives way instead of staying over the card it
        // just produced. Every capture path — display, area and window — delivers
        // through here, so the exit happens once and in one place.
        //
        // The focus comes back with it: the card is a non-activating panel, so it
        // stays on screen while the app the user came from gets the keyboard
        // again. Leaving Stare frontmost was the bug this closed.
        if isActive { deactivate(restoringFocus: true) }
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
    /// The pasteboard every capture write goes through. The real one in the
    /// app; a test points it at a board of its own so the comparison it makes
    /// cannot be parked behind a drag session's unfulfilled file promise — a
    /// live `NSDraggingSession` keeps the general pasteboard claimed, and a
    /// later read of it waits for a promise nobody will ever request.
    var pasteboard: NSPasteboard = .general

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
        // Same reason as the board's close: the sessions are stored and restored
        // with their stroke ids, so the undo steps stay valid across a cycle.
        liveFrames.stop()
    }

    /// Command-Z: first the mark being dragged, then the newest entry in the
    /// global history — a draw, a transform, or a layer clear on whichever
    /// display it happened. The owning view's session agrees before it acts,
    /// so a popped entry can never undo a different change than the one it
    /// names.
    func undo() {
        let canvases = activeCanvases
        Diag.log(
            "undo called active=\(NSApp.isActive) key=\(NSApp.keyWindow != nil) entries=\(historyOrder.count) canvases=\(canvases.count) board=\(isBoardActive) overlay=\(isActive)"
        )
        if let canvas = activeCanvasUnderPointer(), canvas.discardActiveMark() { return }
        // An entry that cannot be applied is KEPT, not discarded: a stale step
        // sitting on top used to take the whole history down with it, which is
        // exactly how ⌘Z went silent after a mode cycle. Walk past what cannot
        // apply, undo the newest that can, and put the skipped ones back on top.
        var skipped: [HistoryEntry] = []
        while let last = historyOrder.popLast() {
            if let canvas = canvases[last.owningDisplayID], canvas.undo(entry: last) {
                historyOrder.append(contentsOf: skipped.reversed())
                redoOrder.append(last)
                Diag.log("undo display=\(last.owningDisplayID) remaining=\(historyOrder.count) skipped=\(skipped.count)")
                return
            }
            Diag.log("undo skipped kind=\(last.debugKind) display=\(last.owningDisplayID)")
            skipped.append(last)
        }
        historyOrder.append(contentsOf: skipped.reversed())
        Diag.log("undo empty entries=\(historyOrder.count)")
    }

    /// Shift-Command-Z: puts back the newest undone change, on the display it
    /// came from — a removed mark, a transform, or the cleared batch.
    func redo() {
        let canvases = activeCanvases
        Diag.log("redo called active=\(NSApp.isActive) entries=\(redoOrder.count) board=\(isBoardActive) overlay=\(isActive)")
        var skipped: [HistoryEntry] = []
        while let last = redoOrder.popLast() {
            if let canvas = canvases[last.owningDisplayID], canvas.redo(entry: last) {
                redoOrder.append(contentsOf: skipped.reversed())
                historyOrder.append(last)
                Diag.log("redo display=\(last.owningDisplayID) remaining=\(redoOrder.count) skipped=\(skipped.count)")
                return
            }
            skipped.append(last)
        }
        redoOrder.append(contentsOf: skipped.reversed())
        Diag.log("redo empty entries=\(redoOrder.count)")
    }

    // MARK: - Canvases

    /// Internal so the tests can drive the real observers: the capture
    /// history sheet's re-place (B3) rides on both.
    @objc func screenParametersChanged() {
        // The bottom sheet (B3/S1): a screen-configuration change re-derives
        // the sheet's anchored frame on the screen under the pointer while it
        // is visible. The early return below guards only the overlay/board
        // work; the sheet is re-placed first, whatever else is active.
        captureHistoryPanel.repositionIfVisible()
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
    /// Internal so the tests can drive the real observers: the capture
    /// history sheet's re-place (B3) rides on both.
    @objc func activeSpaceChanged() {
        // The bottom sheet (B3/S1): the sheet follows to the screen under the
        // pointer when the visible Space changes, the same observers the
        // drawing layers ride on.
        captureHistoryPanel.repositionIfVisible()
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
        // Board only: the image layer exists on a whiteboard page. One step per
        // edit, on the same stream the marks use, carrying the page it happened
        // on (L8) — and an edit that changed nothing is no step.
        if let boardView = view as? WhiteboardView {
            boardView.onBoardImageEdited = { [weak self] before, after, page in
                guard let self, before != after else { return }
                historyOrder.append(
                    .boardImage(displayID: displayID, page: page, before: before, after: after)
                )
                redoOrder.removeAll()
            }
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
                },
                onOverflowToggle: { [weak self] in self?.toggleOverflowPanel() }
            )
            : ToolbarPanel(
                state: state,
                onUndo: { [weak self] in self?.undo() },
                onRedo: { [weak self] in self?.redo() },
                onClear: { [weak self] in self?.clearAll() },
                onDone: { [weak self] in self?.deactivate() },
                onOverflowToggle: { [weak self] in self?.toggleOverflowPanel() }
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

    /// Which pointer events must be dropped while the pointer is over a card: the
    /// canvas re-asserts its cursor on the move as well as on the cursor update,
    /// so only swallowing both keeps the arrow (B9).
    static func swallowsPointerEvent(_ type: NSEvent.EventType, overCard: Bool) -> Bool {
        overCard && (type == .cursorUpdate || type == .mouseMoved)
    }

    /// Whether an event came from one of the cards, which are windows of ours.
    /// A move with no window at all is not a card's — it takes the same path as
    /// a canvas move, so the swallow keeps holding for synthesized events.
    static func isCardWindow(_ window: NSWindow?, cards: [CaptureCard]) -> Bool {
        guard let window else { return false }
        return cards.contains { $0 === window }
    }

    /// The B9 probe, off unless asked for: `STARE_CURSOR_PROBE=1` logs what the
    /// monitor saw and decided while the pointer is over a card. Two blind passes
    /// at this cursor were enough; the next one reads instead of guessing.
    static let cursorProbeEnabled = ProcessInfo.processInfo.environment["STARE_CURSOR_PROBE"] == "1"

    /// Whether the pointer over a capture card keeps the arrow, in either live
    /// mode: the overlay sets its own crosshair and the board sets its tool
    /// cursor, and over a card neither may win (B9). `openBoard` sets
    /// `isBoardActive` and never `isActive`, which is why both modes count —
    /// the board was the one that stayed wrong longest.
    ///
    /// Takes the pointer and the frames so a test can ask the question:
    /// `NSEvent.mouseLocation` is not something a test can move.
    func cursorSkipsTheCard(at pointer: CGPoint, cardFrames: [CGRect]) -> Bool {
        guard isActive || isBoardActive else { return false }
        return CardCursor.isOverCard(pointer, cardFrames: cardFrames)
    }

    /// Watches the pointer for the capture cards (B9). The drawing layer sets
    /// one crosshair for a whole display, so a card's own tracking area never
    /// wins against it; re-answering the arrow on every event is what the bar's
    /// monitor already does for its own cursor. `CardCursor` owns the rule and
    /// this monitor only feeds it the pointer and the visible card frames.
    private func installCardCursorMonitor() {
        guard cardCursorMonitor == nil else { return }
        cardCursorMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .mouseEntered, .cursorUpdate]
        ) { [weak self] event in
            guard let self else { return event }
            let overCard = self.cursorSkipsTheCard(
                at: NSEvent.mouseLocation, cardFrames: self.cards.visibleCardFrames
            )
            guard overCard else { return event }
            // A move that already belongs to a card window stays where it is: the
            // card's own hover is a consumer of moves too. What is dropped is the
            // move that would land on the canvas *because* the card does not take
            // mouse-moved events, which is the one that re-asserts the tool cursor.
            let fromACard = Self.isCardWindow(event.window, cards: self.cards.openCards)
            if Self.cursorProbeEnabled {
                Diag.log(
                    "card cursor type=\(event.type.rawValue) swallow=\(!fromACard && Self.swallowsPointerEvent(event.type, overCard: true)) window=\(fromACard ? "card" : "other")"
                )
            }
            guard !fromACard else { return event }
            NSCursor.arrow.set()
            // Both the move and the cursor update have to be dropped: the canvas
            // re-asserts its tool cursor on either, and dropping only the update
            // is why the board kept the tool cursor after the overlay gave way.
            // A move over a card belongs to the card anyway — it is a window of
            // ours sitting on top of that stretch of canvas.
            return Self.swallowsPointerEvent(event.type, overCard: true) ? nil : event
        }
    }

    private func removeCardCursorMonitor() {
        if let monitor = cardCursorMonitor { NSEvent.removeMonitor(monitor) }
        cardCursorMonitor = nil
    }

    private var toolbarMode: String?

    private func hideToolbar() {
        removeToolbarCursorMonitor()
        hideOverflowPanel()
        toolbar?.orderOut(nil)
    }

    /// Opens the hidden tools beside the bar, or closes them if they are already
    /// there (T6). The panel is rebuilt each time it opens, so it always shows
    /// the layout as it is now and lands where the bar currently sits; it never
    /// outlives the bar or the mode.
    private func toggleOverflowPanel() {
        if overflowPanel?.isVisible == true {
            hideOverflowPanel()
            return
        }
        guard let toolbar, let screen = toolbar.screen ?? NSScreen.main else { return }
        hideOverflowPanel()
        let panel = ToolbarOverflowPanel(
            state: state,
            hidden: state.toolbarTools.hiddenTools,
            vertical: state.toolbarOrientation == .vertical,
            onPick: { [weak self] tool in
                self?.state.select(tool)
                self?.hideOverflowPanel()
            }
        )
        panel.place(
            beside: toolbar.frame,
            border: state.toolbarBorder.docked(for: state.toolbarOrientation),
            screen: screen,
            anchor: toolbar.overflowButtonScreenCentre()
        )
        overflowPanel = panel
        panel.orderFrontRegardless()
        installOverflowDismissMonitor()
    }

    private func hideOverflowPanel() {
        removeOverflowDismissMonitor()
        overflowPanel?.orderOut(nil)
        overflowPanel = nil
    }

    /// Whether an event that arrived at `point` (in `window`'s own coordinates,
    /// origin bottom-left; nil whenever the event carries no pointer position —
    /// a key, say) closes the extras panel. The old rule was "any window but the
    /// panel's own", and it closed the panel on the press over the more button
    /// itself: the monitor hid the panel first, then the button's own toggle saw
    /// a closed panel and reopened it, so the owner's second press could never
    /// close it (S12/L31). The fix lives here, in the pure rule: a press inside
    /// the more button's frame in the bar's own window does not close — that
    /// button's toggle owns the open state, one press opens, the next closes.
    /// `moreButtonFrame` is the frame `ToolbarPanel` already reports for the
    /// panel's placement, flipped into the same window coordinates. An unknown
    /// frame (nil — no first layout pass yet) or a foreign window falls back to
    /// the old rule and closes. Pure, so the rule is pinned without a live
    /// event stream.
    static func closesOverflow(
        forEventAt point: CGPoint?,
        in window: NSWindow?,
        panel: NSWindow?,
        moreButtonFrame: (window: NSWindow, frame: CGRect)? = nil
    ) -> Bool {
        guard let panel else { return false }
        if window === panel { return false }
        if let moreButtonFrame, window === moreButtonFrame.window,
           let point, moreButtonFrame.frame.contains(point) {
            return false
        }
        return true
    }

    private func installOverflowDismissMonitor() {
        guard overflowDismissMonitor == nil else { return }
        overflowDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        ) { [weak self] event in
            guard let self else { return event }
            // A key event carries no pointer position, so it can never name a
            // press inside the more button; every other matched event does.
            let pressPoint = event.type == .keyDown ? nil : event.locationInWindow
            let moreButton: (window: NSWindow, frame: CGRect)? = self.toolbar.flatMap { toolbar in
                toolbar.overflowButtonWindowFrame().map { (toolbar, $0) }
            }
            if Self.closesOverflow(
                forEventAt: pressPoint,
                in: event.window,
                panel: self.overflowPanel,
                moreButtonFrame: moreButton
            ) {
                self.hideOverflowPanel()
            }
            return event
        }
        // Another app taking over closes it too: the panel is not a thing that
        // waits in the background.
        appResignedObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideOverflowPanel() }
        }
    }

    private func removeOverflowDismissMonitor() {
        if let monitor = overflowDismissMonitor { NSEvent.removeMonitor(monitor) }
        overflowDismissMonitor = nil
        if let observer = appResignedObserver { NotificationCenter.default.removeObserver(observer) }
        appResignedObserver = nil
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
        case let .boardImage(_, page, before, _):
            guard let page, let boardView = whiteboardView(forPage: page) else { return false }
            return boardView.restorePageImage(before, onPage: page)
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
        case let .boardImage(_, page, _, after):
            guard let page, let boardView = whiteboardView(forPage: page) else { return false }
            return boardView.restorePageImage(after, onPage: page)
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
