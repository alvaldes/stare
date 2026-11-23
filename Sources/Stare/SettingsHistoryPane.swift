import AppKit
import SwiftUI
import StareCore

/// The session's capture history (T3/S12): the captures this session
/// delivered, newest first, each with an Open button that reopens it in the
/// capture editor — the same editor window, tools and inks the capture
/// card's click opens, through the history's one reopen hook. Everything
/// lives in memory: quitting Stare empties the history and there is no
/// store, so the pane says so instead of implying a retention guarantee.
///
/// The history comes in without parameters (S4): the shared `CaptureHistory`
/// the overlay records into is the one the pane reads, so the registration
/// in `SettingsView.pane(for:)` stays a plain five-line addition. Detached
/// instances keep the tests off the shared store.
struct HistoryPane: View {
    @ObservedObject var history: CaptureHistory

    init(history: CaptureHistory = .shared) {
        self.history = history
    }

    var body: some View {
        SettingsPane(
            title: "History",
            subtitle: "The captures this session made, ready to reopen."
        ) {
            VStack(spacing: SettingsMetrics.cardSpacing) {
                capturesCard
                clearCard
            }
            .settingsSingleColumn()
        }
    }

    // MARK: Entries

    private var capturesCard: some View {
        SettingsCard(title: "This session", symbol: "clock.arrow.circlepath") {
            if history.entries.isEmpty {
                Text("No captures yet. Every capture you take — display, area, window or board — is listed here until Stare quits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history.entries) { entry in
                    entryRow(entry)
                }
            }
            Text("The history is kept in memory only — nothing is saved to disk, and quitting Stare forgets it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func entryRow(_ entry: CaptureHistoryEntry) -> some View {
        HStack(spacing: 12) {
            Image(decorative: entry.image, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 72, maxHeight: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: .separatorColor)))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, weight: .medium))
                Text(verbatim: "\(entry.image.width) × \(entry.image.height) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") { open(entry) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Capture from \(entry.date.formatted(date: .abbreviated, time: .shortened))")
    }

    private var clearCard: some View {
        SettingsCard(title: "Forget", symbol: "trash") {
            SettingRow(
                title: "Clear the history",
                detail: "Removes every remembered capture of this session at once. The captures already on the clipboard or in their folder are untouched.",
                content: Button("Clear") { clear() }
            )
        }
    }

    // MARK: Actions

    /// Reopens the entry's capture in the editor through the history's one
    /// reopen hook — the overlay routes it into the same handoff the capture
    /// card's click uses, so there is no second editor path. Unwired (before
    /// the overlay builds), the request changes nothing.
    func open(_ entry: CaptureHistoryEntry) {
        history.onReopen?(entry)
    }

    /// Forgets every capture of the session; the store keeps accepting
    /// records afterwards.
    func clear() {
        history.clear()
    }
}
