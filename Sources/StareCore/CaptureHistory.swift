import Combine
import CoreGraphics
import Foundation

/// One capture this session delivered: the composed image (marks already
/// baked in, exactly what the capture card shows and the editor opens) and
/// the instant it was delivered.
public struct CaptureHistoryEntry: Identifiable, Equatable {
    public let id: UUID
    public let image: CGImage
    public let date: Date

    public init(id: UUID = UUID(), image: CGImage, date: Date) {
        self.id = id
        self.image = image
        self.date = date
    }
}

/// The session capture history (T3/S12): the last captures the session
/// delivered, in memory only — nothing is written to disk, nothing survives
/// an app quit, so losing a capture because the card faded away is the only
/// failure this closes. The entries are the deliveries' own composed images,
/// newest first; beyond the capacity the oldest capture leaves. Clearing the
/// app's process (quitting) is the retention policy; there is no store and
/// no preference document entry — the count is this fixed session capacity.
///
/// Main-thread confined like the capture path that feeds it and the Settings
/// pane that reads it: `record` runs in the capture tail, `onReopen` is wired
/// by `OverlayController` and fired by the History pane's Open button.
public final class CaptureHistory: ObservableObject {
    /// The one session store: the overlay records into it and the History
    /// pane reads it, without threading a reference through the shared
    /// Settings registration (S4 — the pane is constructed by `pane(for:)`
    /// with no extra parameters). Tests build detached instances instead.
    public static let shared = CaptureHistory()

    /// How many of the session's captures stay reachable. A full-size display
    /// capture is large, so the history is deliberately short; every entry
    /// here is the composed image, kept alive in memory only.
    public let capacity: Int

    /// Newest first: the order the History pane lists.
    @Published public private(set) var entries: [CaptureHistoryEntry] = []

    /// Fired with the entry whose capture should reopen in the editor. Wired
    /// by the overlay to its one editor handoff — the same path the capture
    /// card's click takes — so a reopen can never open a second editor
    /// implementation. Unwired, a reopen request changes nothing.
    public var onReopen: ((CaptureHistoryEntry) -> Void)?

    public init(capacity: Int = 10) {
        self.capacity = max(capacity, 1)
    }

    /// Remembers one delivered capture. The image is kept by reference — the
    /// composed capture itself, never a recomposition over what the session
    /// holds now.
    public func record(_ image: CGImage, at date: Date = Date()) {
        entries.insert(CaptureHistoryEntry(image: image, date: date), at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    /// Forgets every capture the session made. The history keeps accepting
    /// records afterwards.
    public func clear() {
        entries.removeAll()
    }
}
