import AppKit
import SwiftUI

/// The paste-style capture history panel (T2a/S2): a non-activating borderless
/// panel above every other Stare surface — the board, the toolbar and the
/// capture cards included — showing the newest captures first in a grid, one
/// metadata line per capture, keyboard navigation (arrows move, Return picks,
/// Esc closes), click to pick, and a Clear button that empties the store and
/// deletes the stored captures.
final class CaptureHistoryPanel: NSPanel {
    /// Above the whiteboard (`.screenSaver`) and the capture cards
    /// (`.screenSaver + 2`): every Stare surface sits behind the history.
    static let panelLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)

    /// The panel's content size: three columns of thumbnails plus the header.
    static let contentSize = CGSize(width: 640, height: 420)

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

    init(store: CaptureHistoryStore, onPick: @escaping (CGImage) -> Void = CaptureHistoryPanel.copyToPasteboard) {
        model = CaptureHistoryPanelModel(
            store: store,
            onPick: onPick,
            onClose: {}
        )
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.contentSize),
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
        contentView = hosting
        self.hostingView = hosting
        setContentSize(Self.contentSize)

        // The model outlives nothing: closing routes back to the panel, so
        // picking (or Esc) hides the window it came from.
        model.onClose = { [weak self] in self?.hide() }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var hostingView: CaptureHistoryPanelHostingView?

    /// Opens (or refreshes) the panel: newest first, selected on the newest,
    /// centred on the screen under the pointer, and key so the keyboard
    /// works. The hosting view takes first responder, or every key event in
    /// the window's real dispatch path dies: `NSHostingView` declines first
    /// responder by default, and with nobody responder the arrows, Return
    /// and Esc reach nothing.
    func showPanel() {
        model.refresh()
        setFrame(Self.frame(on: screenUnderPointer()), display: true)
        orderFrontRegardless()
        makeKey()
        if let hostingView {
            makeFirstResponder(hostingView)
        }
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        orderOut(nil)
        onHidden?()
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
    func handleKey(_ event: NSEvent) -> Bool {
        // Command and Control belong to the app's menus and its own shortcuts.
        guard event.modifierFlags.intersection([.command, .control]).isEmpty else { return false }
        switch event.keyCode {
        case 53: // Esc
            hide()
            return true
        case 123, 126: // ←, ↑: previous — one entry newer
            model.moveSelection(-1)
            return true
        case 124, 125: // →, ↓: next — one entry older
            model.moveSelection(1)
            return true
        case 36, 76: // Return, keypad Enter
            model.pickSelected()
            return true
        default:
            return false
        }
    }

    /// Centres the panel inside `screen`'s visible frame, clamped so it never
    /// leaves the screen.
    static func frame(on screen: NSScreen?) -> CGRect {
        guard let screen else {
            return CGRect(origin: .zero, size: contentSize)
        }
        let frame = screen.visibleFrame
        let origin = CGPoint(
            x: frame.midX - contentSize.width / 2,
            y: frame.midY - contentSize.height / 2
        )
        return CGRect(
            x: min(max(origin.x, frame.minX), frame.maxX - contentSize.width),
            y: min(max(origin.y, frame.minY), frame.maxY - contentSize.height),
            width: contentSize.width,
            height: contentSize.height
        )
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

    init(store: CaptureHistoryStore, onPick: @escaping (CGImage) -> Void, onClose: @escaping () -> Void) {
        self.store = store
        self.onPick = onPick
        self.onClose = onClose
    }

    /// Reloads from the store and starts selected on the newest capture.
    func refresh() {
        entries = store.entries
        selectedIndex = entries.isEmpty ? nil : 0
    }

    /// Selects `index` outright; an out-of-bounds index is ignored.
    func select(at index: Int) {
        guard entries.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// Arrow navigation: moves the selection by `delta`, clamped so it never
    /// leaves the entries.
    func moveSelection(_ delta: Int) {
        guard let current = selectedIndex else { return }
        let next = min(max(current + delta, 0), entries.count - 1)
        selectedIndex = next
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

    private let columns = [
        GridItem(.adaptive(minimum: 170), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Capture History")
                    .font(.headline)
                Spacer()
                Button("Clear") { model.clearHistory() }
                    .disabled(model.isEmpty)
            }
            .padding([.top, .horizontal], 14)

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
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                            CaptureHistoryCell(model: model, index: index, entry: entry)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// One grid cell: the thumbnail, its metadata line, the selection outline and
/// the click-to-pick gesture.
struct CaptureHistoryCell: View {
    let model: CaptureHistoryPanelModel
    let index: Int
    let entry: PersistedCaptureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image = model.image(for: entry) {
                Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .onTapGesture { model.pick(at: index) }
    }

    private var isSelected: Bool {
        model.selectedEntry?.id == entry.id
    }

    /// The one metadata line: when the capture was taken and its pixel size.
    private var metadata: String {
        let size = "\(entry.pixelWidth)×\(entry.pixelHeight)"
        return entry.date.formatted(date: .abbreviated, time: .shortened) + " · " + size
    }
}
