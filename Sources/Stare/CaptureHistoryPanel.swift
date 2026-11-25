import AppKit
import StareCore
import SwiftUI

/// The paste-style capture history panel (T2a/S2), re-shaped as the full-width
/// bottom sheet (B3/S1): a non-activating borderless panel above every other
/// Stare surface — the board, the toolbar and the capture cards included —
/// spanning the screen's visible frame width, anchored flush to its bottom
/// edge, at a fixed 0.42 height, showing the newest captures first in a grid,
/// one metadata line per capture, keyboard navigation (arrows move, Return
/// picks, Esc closes), click to pick, and a Clear button that empties the
/// store and deletes the stored captures.
final class CaptureHistoryPanel: NSPanel {
    /// Above the whiteboard (`.screenSaver`) and the capture cards
    /// (`.screenSaver + 2`): every Stare surface sits behind the history.
    static let panelLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)

    /// The sheet's fixed height rule (B3/S1): 0.42 of the screen's VISIBLE
    /// height — inside `visibleFrame`, so the Dock and the notch stay clear.
    static let sheetHeightFraction: CGFloat = 0.42

    /// The shelf's floor (S1: "never less than one card row plus the header").
    /// One row is the thumbnail (aspect-fit inside its width, capped at 4:3's
    /// height for the reference row) + the caption line, the gap and the
    /// cell's own padding (t + 4 + 12 + 12 = t + 28); above it the header row
    /// and its top padding (22 + 16); under it the sheet's bottom padding
    /// (16). `t + 92`, where t is the thumbnail preference's width.
    static func minimumShelfHeight(thumbnailSize: Double) -> CGFloat {
        CGFloat(thumbnailSize) + 92
    }

    /// The floor at the shipped default preference (170 pt) — what a test or
    /// call without a preference pins against.
    static let defaultMinimumShelfHeight = minimumShelfHeight(thumbnailSize: HistoryPreference.defaultThumbnailSize)

    /// Degenerate pre-show size, replaced by `showPanel`'s anchored frame on
    /// every open. Kept for the no-screen fallback nothing else in AppKit can
    /// avoid (a borderless window needs SOME frame at init).
    static let fallbackContentSize = CGSize(width: 1200, height: 420)

    let model: CaptureHistoryPanelModel

    /// The delivery seam (T2a): what picking does with the capture's image.
    /// Defaults to the clipboard (PNG + TIFF); T2b can route a pick into the
    /// whiteboard without reworking the panel.
    var onPick: (CGImage) -> Void {
        get { model.onPick }
        set { model.onPick = newValue }
    }

    /// Runs when the panel hides (Esc, a pick, the toggle-off), so the owner
    /// can return key focus to the surface that was working before it.
    var onHidden: (() -> Void)?

    init(
        store: CaptureHistoryStore,
        thumbnailSize: @escaping () -> Double = { HistoryPreference.defaultThumbnailSize },
        onPick: @escaping (CGImage) -> Void = CaptureHistoryPanel.copyToPasteboard
    ) {
        model = CaptureHistoryPanelModel(
            store: store,
            thumbnailSize: thumbnailSize,
            onPick: onPick,
            onClose: {}
        )
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.fallbackContentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = Self.panelLevel
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        let hosting = CaptureHistoryPanelHostingView(rootView: CaptureHistoryPanelContent(model: model))
        hosting.sizingOptions = []
        // The sheet's content tracks the window's frame, so the slide never
        // lays content out at a stale size (B3: sizingOptions stay [], too —
        // SwiftUI must never resize the window mid-animation).
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        self.hostingView = hosting
        setContentSize(Self.fallbackContentSize)

        // The model outlives nothing: closing routes back to the panel, so
        // picking (or Esc) hides the window it came from.
        model.onClose = { [weak self] in self?.hide() }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var hostingView: CaptureHistoryPanelHostingView?

    /// Opens (or refreshes) the panel: newest first, selected on the newest,
    /// spanning the screen under the pointer's visible frame flush to its
    /// bottom (B3), and key so the keyboard works. The hosting view takes
    /// first responder, or every key event in the window's real dispatch path
    /// dies: `NSHostingView` declines first responder by default, and with
    /// nobody responder the arrows, Return and Esc reach nothing.
    ///
    /// The slide (B3, net-new): the sheet rises from just below the bottom
    /// edge with a short ease-out, and only at the END of the open does it
    /// become key and take first responder — a window that went key mid-slide
    /// would eat keys while its frame was still moving. The sheet re-derives
    /// its target from `screenUnderPointer()` on EVERY open, so a display
    /// added or a setting changed since the last open is honoured.
    func showPanel() {
        model.refresh()
        let target = Self.frame(on: screenUnderPointer())
        setContentSize(target.size)
        guard Self.animates else {
            // The synchronous path — the plain order the tests drive: place,
            // front, key, first responder, monitors. Same as the pre-B3 open
            // apart from the anchored frame.
            setFrame(target, display: true)
            orderFrontRegardless()
            makeKey()
            if let hostingView {
                makeFirstResponder(hostingView)
            }
            installKeyMonitor()
            installOutsideClickMonitors()
            Diag.log(
                "history shown entries=\(model.entries.count) selected=\(model.selectedIndex.map(String.init) ?? "nil") key=\(isKeyWindow)" +
                    " frame=\(target)"
            )
            return
        }
        isSlideOpening = true
        setFrame(Self.offscreenFrame(from: target), display: false)
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.openDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            self.setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            guard let self, self.isSlideOpening else { return }
            isSlideOpening = false
            guard isVisible else { return } // closed mid-slide: hide() owns the close
            setFrame(target, display: false)
            makeKey()
            if let hostingView {
                makeFirstResponder(hostingView)
            }
            installKeyMonitor()
            installOutsideClickMonitors()
            Diag.log(
                "history shown entries=\(model.entries.count) selected=\(model.selectedIndex.map(String.init) ?? "nil") key=\(isKeyWindow)" +
                    " frame=\(target)"
            )
        })
    }

    // MARK: The slide (B3)

    /// Slide only in the real app: `NSAnimationContext`'s completion runs on
    /// the main run loop, which the test harness (`swift test`, `--selftest`)
    /// never spins — an un-spun loop would leave the open not-yet-key and the
    /// close not-yet-hidden at assertion time. `isRunning` is true only under
    /// `app.run()` (main.swift), so headless runs take the synchronous path
    /// above and every pinned behaviour is frame- and hook-exact as before.
    static var animates: Bool { NSApp?.isRunning ?? false }

    /// The slide's entrance: a short ease-out rise off the bottom edge.
    static var openDuration: TimeInterval { 0.22 }

    /// The slide's exit: a short ease-in sink, matched half-feel shorter, a
    /// faster get-out-of-the-way than the entrance.
    static var closeDuration: TimeInterval { 0.18 }

    /// The frame a slide starts from (or exits through): the anchored frame's
    /// size, just below its bottom edge. Below the screen's visible bottom —
    /// that is the point: the shelf appears to rise off the screen itself.
    private static func offscreenFrame(from anchored: CGRect) -> CGRect {
        CGRect(origin: CGPoint(x: anchored.minX, y: anchored.minY - anchored.height), size: anchored.size)
    }

    /// True while the entrance slide is in flight: `hide()` called then takes
    /// the synchronous path (monitors off, order out, hook once) instead of
    /// fighting the open's frames.
    private var isSlideOpening = false

    /// True while the exit slide is in flight: a second `hide()` is a no-op,
    /// so `onHidden` still fires exactly once per close.
    private var isSlideClosing = false

    /// A screen-configuration or Space change while the sheet is visible
    /// re-derives the anchored frame on the screen under the pointer (the
    /// controller's `screenParametersChanged`/`activeSpaceChanged` observers
    /// call this; B3/S1). The slide is an ENTRANCE gesture: the re-place is
    /// never animated.
    func repositionIfVisible() {
        guard isVisible, !isSlideClosing else { return }
        setFrame(Self.frame(on: screenUnderPointer()), display: true)
    }

    func hide() {
        removeKeyMonitor()
        removeOutsideClickMonitors()
        // A hide during the exit slide is not another close: the hook has
        // still not run, and a second run would double it (B3: exactly once).
        guard !isSlideClosing else { return }
        if isVisible, Self.animates, !isSlideOpening {
            isSlideClosing = true
            let exit = Self.offscreenFrame(from: frame)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.closeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                context.allowsImplicitAnimation = true
                self.setFrame(exit, display: true)
            }, completionHandler: { [weak self] in
                guard let self else { return }
                isSlideClosing = false
                orderOut(nil)
                onHidden?()
            })
            return
        }
        orderOut(nil)
        onHidden?()
    }

    // MARK: Clicking outside (B2)

    /// The monitors that close the panel on the first click anywhere else —
    /// Maccy's behaviour, which is what a paste-style palette teaches a user to
    /// expect: the panel does not need Esc or a second shortcut to get out of
    /// the way. (B3 re-derivation: with the sheet spanning the bottom strip,
    /// "else" is anything outside that strip — a click anywhere in it keeps
    /// the sheet open.)
    ///
    /// Two monitors because one cannot see both worlds: a LOCAL one for clicks
    /// inside Stare (another of our windows, or the board) and a GLOBAL one for
    /// clicks in every other app. Mouse events need no accessibility grant;
    /// the keyboard monitor is the one that would.
    private var outsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?

    /// Whether a click closes the panel: anything that is not the panel itself
    /// and not inside its frame. Kept as a value rule so the decision is
    /// testable without windows, monitors or a screen.
    nonisolated static func hides(forClickOnPanelWindow windowIsPanel: Bool, insidePanelFrame: Bool) -> Bool {
        !(windowIsPanel || insidePanelFrame)
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleClickOutside(event)
            return event
        }
        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleClickOutside(nil)
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let globalOutsideClickMonitor { NSEvent.removeMonitor(globalOutsideClickMonitor) }
        outsideClickMonitor = nil
        globalOutsideClickMonitor = nil
    }

    /// A click on the panel belongs to the panel; one inside its frame is a
    /// near miss the user still reads as the panel's — and since B3 that frame
    /// is the full-width bottom strip, so the clause reads: a click anywhere
    /// in the bottom strip keeps the sheet open. Everything else closes it,
    /// and the click itself goes on to whatever it landed on.
    private func handleClickOutside(_ event: NSEvent?) {
        guard isVisible else { return }
        let hides = Self.hides(
            forClickOnPanelWindow: event?.window === self,
            insidePanelFrame: frame.contains(NSEvent.mouseLocation)
        )
        guard hides else { return }
        Diag.log("history closed by an outside click")
        hide()
    }

    // MARK: Keyboard monitoring

    /// A local monitor as well as the responder chain: SwiftUI can move the
    /// window's first responder after the panel is key, and a key that lands
    /// nowhere is exactly the bug the owner hit twice. The monitor sees the
    /// event before the window does, so the mapping below runs once, never
    /// twice.
    private var keyMonitor: Any?

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// The one key mapping: Esc closes, the arrows walk the grid (↓/→ toward the
    /// older captures, because the grid reads newest first), Return picks.
    /// Anything with Command or Control is somebody else's and passes through.
    /// Returns whether the event was consumed.
    /// The B10 probe, off unless asked for: `STARE_HISTORY_KEY_PROBE=1` in the
    /// environment makes every key the panel receives log the code, the entry
    /// count and the selection before and after. A probe that ran always would
    /// grow the log on every arrow press for the rest of the app's life.
    static let keyProbeEnabled = ProcessInfo.processInfo.environment["STARE_HISTORY_KEY_PROBE"] == "1"

    func handleKey(_ event: NSEvent) -> Bool {
        // Command and Control belong to the app's menus and its own shortcuts.
        guard event.modifierFlags.intersection([.command, .control]).isEmpty else { return false }
        let probeIndex = model.selectedIndex.map(String.init) ?? "nil"
        if Self.keyProbeEnabled {
            Diag.log("history key keyCode=\(event.keyCode) entries=\(model.entries.count) before=\(probeIndex)")
        }
        defer {
            if Self.keyProbeEnabled {
                Diag.log("history key keyCode=\(event.keyCode) after=\(model.selectedIndex.map(String.init) ?? "nil")")
            }
        }
        switch event.keyCode {
        case 53: // Esc
            hide()
            return true
        case 123: // ←: one entry newer
            model.moveSelection(-1)
            return true
        case 124: // →: one entry older
            model.moveSelection(1)
            return true
        case 126: // ↑: one ROW newer — the cell directly above
            model.moveSelection(-model.columnCount)
            return true
        case 125: // ↓: one ROW older — the cell directly below, in a grid of N columns that is N entries along
            model.moveSelection(model.columnCount)
            return true
        case 36, 76: // Return, keypad Enter
            model.pickSelected()
            return true
        default:
            return false
        }
    }

    /// The anchored bottom-sheet frame inside `screen`'s visible frame (B3):
    /// full visible width, flush to the visible bottom, at the fixed height
    /// rule — never below one card row plus the header, never over the screen.
    /// Kept screen-free below so the rule is value-testable without displays.
    static func frame(on screen: NSScreen?) -> CGRect {
        guard let screen else {
            return CGRect(origin: .zero, size: fallbackContentSize)
        }
        return sheetFrame(inVisibleFrame: screen.visibleFrame)
    }

    /// The height rule, value side: `0.42 × visible.height`, floored at one
    /// card row plus the header, clamped to the visible height it lives in.
    static func sheetFrame(inVisibleFrame visible: CGRect, minimumHeight: CGFloat = defaultMinimumShelfHeight) -> CGRect {
        let height = min(max(visible.height * sheetHeightFraction, minimumHeight), visible.height)
        return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: height)
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Today's delivery, the same shape the overlay's capture tail writes:
    /// both PNG and TIFF, because some apps take PNG and others only TIFF.
    static func copyToPasteboard(_ image: CGImage) {
        let representation = NSBitmapImageRep(cgImage: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        if let png = representation.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = representation.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}

/// The keyboard: arrows move the selection, Return picks it, Esc closes.
final class CaptureHistoryPanelHostingView: NSHostingView<CaptureHistoryPanelContent> {
    /// The panel is key, so the view must actually take focus: accept first
    /// responder explicitly, or the key events never reach `keyDown`.
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard window?.isVisible == true else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 53, 123, 124, 125, 126, 36, 76:
            // Install the panel as the router instead of duplicating the
            // mapping: the monitor normally consumes these first.
            if let panel = window as? CaptureHistoryPanel {
                _ = panel.handleKey(event)
                return
            }
            super.keyDown(with: event)
        default:
            super.keyDown(with: event)
        }
    }

    private var model: CaptureHistoryPanelModel {
        rootView.model
    }
}

/// The panel's model: the entries newest first, the selection, and the
/// keyboard routing, all observable so the SwiftUI content re-renders.
@MainActor
final class CaptureHistoryPanelModel: ObservableObject {
    @Published private(set) var entries: [PersistedCaptureEntry] = []
    @Published private(set) var selectedIndex: Int?

    /// True when there is nothing to show: the content renders its empty
    /// state instead of the grid.
    var isEmpty: Bool { entries.isEmpty }

    var selectedEntry: PersistedCaptureEntry? {
        selectedIndex.flatMap { entries.indices.contains($0) ? entries[$0] : nil }
    }

    private let store: CaptureHistoryStore

    /// The delivery seam (T2a): what picking hands the capture's image to.
    /// The panel's default is the clipboard; the owner can inject a whiteboard
    /// route (T2b) without reworking the panel.
    var onPick: (CGImage) -> Void
    var onClose: () -> Void

    /// The grid cell width in points (B1). Read from the preferences on every
    /// `refresh()`, so a change made in Settings reaches the next open: the
    /// panel is a session-long window and its content must not pin a value
    /// chosen before the user touched the slider.
    @Published private(set) var thumbnailSize: Double
    private let thumbnailSizeProvider: () -> Double

    init(
        store: CaptureHistoryStore,
        thumbnailSize: @escaping () -> Double = { HistoryPreference.defaultThumbnailSize },
        onPick: @escaping (CGImage) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.thumbnailSizeProvider = thumbnailSize
        self.thumbnailSize = thumbnailSize()
        self.onPick = onPick
        self.onClose = onClose
    }

    /// Reloads from the store and starts selected on the newest capture.
    func refresh() {
        thumbnailSize = thumbnailSizeProvider()
        entries = store.entries
        selectedIndex = entries.isEmpty ? nil : 0
        Diag.log("history refresh entries=\(entries.count) selected=\(selectedIndex.map(String.init) ?? "nil")")
    }

    /// Selects `index` outright; an out-of-bounds index is ignored.
    func select(at index: Int) {
        guard entries.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// Arrow navigation: moves the selection by `delta`, clamped so it never
    /// leaves the entries.
    /// How many cells the grid shows per row, reported by the view. The vertical
    /// arrows move by a row — in a three-column grid the second element under the
    /// first is the FOURTH, not the second — so the model has to know the width
    /// the grid actually got.
    private(set) var columnCount = 1

    /// Recomputes the row width from the grid's measured width and the same
    /// adaptive minimum the `GridItem` uses.
    func updateColumnCount(forGridWidth width: CGFloat) {
        let minimum = CGFloat(thumbnailSize)
        let spacing: CGFloat = 10
        guard width > 0 else { return }
        let columns = max(1, Int((width + spacing) / (minimum + spacing)))
        guard columns != columnCount else { return }
        columnCount = columns
        Diag.log("history grid columns=\(columns) width=\(Int(width))")
    }

    /// "3 / 12" — the selection's place in the history, or nil when nothing is
    /// selected. The header shows it so the focus is legible, not only outlined.
    var selectionPosition: String? {
        guard let index = selectedIndex, !entries.isEmpty else { return nil }
        return "\(index + 1) / \(entries.count)"
    }

    func moveSelection(_ delta: Int) {
        guard let current = selectedIndex else {
            Diag.log("history move ignored: nothing selected")
            return
        }
        let next = min(max(current + delta, 0), entries.count - 1)
        selectedIndex = next
        Diag.log("history move delta=\(delta) from=\(current) to=\(next) entries=\(entries.count)")
    }

    /// Picks `index`: the capture's image goes through `onPick` and the panel
    /// closes. An entry without a loadable image is skipped.
    func pick(at index: Int) {
        guard entries.indices.contains(index),
              let image = store.image(for: entries[index])
        else { return }
        onPick(image)
        onClose()
    }

    /// Return: picks whatever the arrows selected.
    func pickSelected() {
        guard let index = selectedIndex else { return }
        pick(at: index)
    }

    /// The Clear button (S2a): empties the store — deleting the stored
    /// captures — and the model with it.
    func clearHistory() {
        store.clear()
        refresh()
    }

    /// The thumbnail for one grid cell, loaded from the store (session cache
    /// first, then the stored file).
    func image(for entry: PersistedCaptureEntry) -> CGImage? {
        store.image(for: entry)
    }

    func close() {
        onClose()
    }
}

/// The panel's SwiftUI content: header with the title and the Clear button,
/// then the grid of thumbnails with one metadata line each, or the empty
/// state when the history holds nothing.
struct CaptureHistoryPanelContent: View {
    @ObservedObject var model: CaptureHistoryPanelModel

    /// One adaptive column spec built from the preference (B1): the cell
    /// width chosen in Settings, not a constant the panel decides on its own.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: model.thumbnailSize), spacing: 10)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Capture History")
                    .font(.headline)
                // Which capture the keys are on, in words: the outline alone was
                // not readable as "the one in focus", and a position makes the
                // state legible even while the grid scrolls under it.
                if let position = model.selectionPosition {
                    Text(position)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") { model.clearHistory() }
                    .disabled(model.isEmpty)
            }
            .padding([.top, .horizontal], 16)

            if model.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No captures yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Captures you finish show up here, newest first.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                                CaptureHistoryCell(
                                    model: model,
                                    index: index,
                                    entry: entry,
                                    isSelected: model.selectedEntry?.id == entry.id
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        // The grid tells the model how wide it is, so the
                        // vertical arrows can move by a row (see columnCount).
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear { model.updateColumnCount(forGridWidth: proxy.size.width) }
                                    .onChange(of: proxy.size.width) { _, width in
                                        model.updateColumnCount(forGridWidth: width)
                                    }
                            }
                        )
                    }
                    // Minimal scroll, not `anchor: .center`: centring on every
                    // move pins the selected cell to the middle of the panel, so
                    // the highlight stays put and the captures slide under it —
                    // the keys read as scrolling without moving the focus (B10).
                    .onChange(of: model.selectedIndex) { _, selected in
                        guard let selected, model.entries.indices.contains(selected) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(model.entries[selected].id)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The slab (B3/S1): frosted material with only the TOP corners
        // rounded; the window itself stays rectangular, and the radius is on
        // the sheet's material so it reads as a plate rising from the bottom
        // edge, not a floating card.
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
    }
}

/// One grid cell: the thumbnail, its metadata line, the selection outline and
/// the click-to-pick gesture.
struct CaptureHistoryCell: View {
    let model: CaptureHistoryPanelModel
    let index: Int
    let entry: PersistedCaptureEntry
    /// The selection arrives as a VALUE, never read off `model` inside the cell:
    /// a cell whose stored properties are all unchanged (the same model
    /// instance, the same index, the same entry) is skipped by SwiftUI, so the
    /// outline stayed on the first cell while the header's counter updated —
    /// the arrows moved the model and nothing moved on screen.
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image = model.image(for: entry) {
                Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            Text(metadata)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .onTapGesture { model.pick(at: index) }
    }

    /// The one metadata line: when the capture was taken and its pixel size.
    private var metadata: String {
        let size = "\(entry.pixelWidth)×\(entry.pixelHeight)"
        return entry.date.formatted(date: .abbreviated, time: .shortened) + " · " + size
    }
}
