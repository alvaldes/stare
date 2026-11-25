import AppKit
import SwiftUI
import StareCore

/// The capture history's settings: what a preview looks like, the one way to
/// forget the whole thing, and the history itself.
///
/// The list is the PERSISTED history — the very same `CaptureHistoryStore.shared`
/// the ⌥⇧I panel reads, so a Clear here is a Clear there — not the session's in-memory list: a capture taken yesterday is
/// just as much "the history" as one taken a minute ago, and a pane that only
/// showed this session's read as if the rest had been thrown away. That means
/// the pane outlives the session's `CaptureHistory` on purpose; the `CaptureHistory`
/// is still passed in because reopening in the editor goes through its one
/// `onReopen` hook, wired by the overlay at launch.
struct HistoryPane: View {
    let store: CaptureHistoryStore
    @ObservedObject var history: CaptureHistory
    /// The preferences owner, optional so a detached pane still renders the
    /// history alone: the preview card is the only thing that needs it, and a
    /// test that renders the list must not reach the user's real preferences.
    private let preferences: PreferencesModel?
    /// Bumped after Clear so the list rebuilds from the store it just emptied:
    /// the store is not observable, and a pane that only reads it at body time
    /// keeps showing the captures it no longer holds.
    @State private var historyRevision = 0

    init(
        store: CaptureHistoryStore = .shared,
        history: CaptureHistory = .shared,
        model: PreferencesModel? = nil
    ) {
        self.store = store
        self.history = history
        self.preferences = model
    }

    var body: some View {
        SettingsPane(
            title: "History",
            subtitle: "Every capture the history kept, from any session."
        ) {
            VStack(spacing: SettingsMetrics.cardSpacing) {
                previewsCard
                // Clear sits above the list, as the owner asked: the thing
                // that empties the history reads first and the history it
                // empties comes after it.
                clearCard
                capturesCard
                    // Clear empties the store, and the list has to show that
                    // without closing and reopening the window.
                    .id(historyRevision)
            }
            .settingsSingleColumn()
        }
    }

    /// B1: how wide the panel's thumbnails are. The panel reads the preference
    /// on every open, so the change shows on the next ⌥⇧I instead of at launch.
    @ViewBuilder private var previewsCard: some View {
        if let preferences {
            HistoryPreviewsCard(model: preferences)
        }
    }

    // MARK: Entries

    private var capturesCard: some View {
        SettingsCard(title: "Captures", symbol: "clock.arrow.circlepath") {
            if store.entries.isEmpty {
                Text("Nothing here yet. Every capture you take — display, area, window or board — is listed here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.entries) { entry in
                    entryRow(entry)
                }
            }
            Text("The history lives on disk, so it survives quitting Stare and holds captures from every session. Clearing it is the only thing that removes them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func entryRow(_ entry: PersistedCaptureEntry) -> some View {
        // The image is read ONCE per row: it draws the thumbnail and it decides
        // whether Open can do anything. An entry whose file was removed outside
        // Stare has no image to open, and a button that looks live and does
        // nothing on click is worse than one that says so (R3-002).
        let image = store.image(for: entry)
        return HStack(spacing: 12) {
            if let image {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 72, maxHeight: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: .separatorColor)))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(width: 72, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, weight: .medium))
                Text(verbatim: "\(entry.pixelWidth) × \(entry.pixelHeight) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") { open(entry) }
                .disabled(!canOpen(entry))
                .help(image == nil ? "This capture's file is no longer there" : "Open it in the editor")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Capture from \(entry.date.formatted(date: .abbreviated, time: .shortened))")
    }

    private var clearCard: some View {
        SettingsCard(title: "Forget", symbol: "trash") {
            SettingRow(
                title: "Clear the history",
                detail: "Removes every remembered capture, from this session and every earlier one. The captures already on the clipboard or in their folder are untouched.",
                content: Button("Clear") { clear() }
            )
        }
    }

    // MARK: Actions

    /// Reopens the stored capture in the editor through the history's one
    /// reopen hook — the overlay routes it into the same handoff the capture
    /// card's click uses, so a capture from an earlier session opens exactly
    /// like one from this one. Unwired (before the overlay builds), nothing
    /// happens.
    func open(_ entry: PersistedCaptureEntry) {
        guard canOpen(entry), let onReopen = history.onReopen,
            let image = store.image(for: entry) else { return }
        onReopen(CaptureHistoryEntry(id: entry.id, image: image, date: entry.date))
    }

    /// Whether the row's Open can actually do something: it needs the editor
    /// hook AND the stored image the editor would open. Deciding it here keeps
    /// the button and the action on one rule, so a capture whose file is gone
    /// never offers a click that silently does nothing (R3-002).
    func canOpen(_ entry: PersistedCaptureEntry) -> Bool {
        history.onReopen != nil && store.image(for: entry) != nil
    }

    /// Forgets every stored capture; the store keeps accepting records
    /// afterwards.
    func clear() {
        store.clear()
        historyRevision &+= 1
    }
}

/// The previews card, split out so it can observe the preferences owner while
/// the pane itself takes it as an optional and stays renderable without one.
struct HistoryPreviewsCard: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        SettingsCard(title: "Previews", symbol: "square.grid.2x2") {
            SettingRow(
                title: "Thumbnail size",
                detail: "How wide each capture is in the history grid. Bigger previews mean fewer per row.",
                content: HStack(spacing: 8) {
                    Slider(value: $model.history.thumbnailSize, in: HistoryPreference.thumbnailSizeRange)
                        .frame(width: 130)
                    Text("\(Int(model.history.thumbnailSize)) pt")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                }
            )
        }
    }
}
