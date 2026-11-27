import AppKit
import Foundation
import StareCore

/// One entry of the persisted capture history (T2a/S2a): the metadata the
/// panel's line shows and the file name the image loads from. Newest-first
/// ordering is the array order the store keeps.
struct PersistedCaptureEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let pixelWidth: Int
    let pixelHeight: Int
    /// PNG file name inside the store's captures folder.
    let fileName: String
}

/// The persisted capture history (T2a/S2a): every finished capture, newest
/// first, capped at 50, stored under a Stare-owned folder in Application
/// Support — one `index.json` beside a `captures/` folder of PNG files.
///
/// The store never breaks a capture: every operation either does its small
/// job or does nothing, and a failed write keeps the capture in memory for
/// the session only (it is not persisted, so a fresh store never sees it)
/// while the failure is logged. A corrupt or partial index loads as empty,
/// and entries whose file went missing are dropped at load, so the panel can
/// never offer a capture it cannot hand out.
final class CaptureHistoryStore {
    /// The history keeps the newest 50 captures (S2a).
    static let maxEntries = 50

    /// The one store the app runs on. The ⌥⇧I panel and the Settings pane both
    /// read the history, and a Clear in one has to be the same history the
    /// other sees: two stores on the same directory diverge in memory (each
    /// caches images and an index) until each re-reads disk, so a capture
    /// cleared in Settings could still sit in an open panel. Tests build their
    /// own store on a throwaway directory and never touch this one.
    static let shared = CaptureHistoryStore()

    /// The store's root: `…/Application Support/Stare/CaptureHistory` in the
    /// production path. Overridable for tests.
    let directory: URL

    private var capturesDirectory: URL {
        directory.appendingPathComponent("captures", isDirectory: true)
    }
    private var indexURL: URL {
        directory.appendingPathComponent("index.json")
    }

    /// Every capture, newest first.
    private(set) var entries: [PersistedCaptureEntry] = []
    /// Images of captures added this session (and lazily loaded ones), so a
    /// capture whose file write failed still has an image to hand out and a
    /// re-open panel does not re-read every file at once.
    private var imageCache: [UUID: CGImage] = [:]

    /// Creates the store at `directory` (default: the app's Application
    /// Support, `Stare/CaptureHistory`), tolerating anything already there:
    /// a corrupt or partial index loads as empty and the next add rewrites it.
    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        createDirectoriesIfNeeded()
        loadIndex()
    }

    /// The production directory: a Stare-owned folder in Application Support.
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundle = Bundle.main.bundleIdentifier ?? "dev.alvaldes.stare"
        return base
            .appendingPathComponent(bundle, isDirectory: true)
            .appendingPathComponent("CaptureHistory", isDirectory: true)
    }

    private func createDirectoriesIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
        } catch {
            // An unusable captures folder (a file in the way, a read-only
            // disk) is a write-failure session: adds keep their captures in
            // memory and log, exactly like any other write failure.
            Diag.log("capture history: captures folder unavailable: \(error)")
        }
    }

    /// Records one finished capture (T2a): writes the PNG beside the index,
    /// prepends the entry, and prunes past the newest 50, deleting the
    /// evicted files. A failed write still returns the entry — the capture
    /// stays in memory for the session — and logs instead of throwing.
    @discardableResult
    func add(_ image: CGImage, date: Date = Date()) -> PersistedCaptureEntry {
        let entry = PersistedCaptureEntry(
            id: UUID(),
            date: date,
            pixelWidth: image.width,
            pixelHeight: image.height,
            fileName: "\(UUID().uuidString).png"
        )
        imageCache[entry.id] = image

        let persisted: Bool
        if let data = CaptureFile.data(for: image, format: .png) {
            do {
                try data.write(to: capturesDirectory.appendingPathComponent(entry.fileName))
                persisted = true
            } catch {
                Diag.log("capture history: png write failed: \(error)")
                persisted = false
            }
        } else {
            Diag.log("capture history: png encoding failed")
            persisted = false
        }

        entries.insert(entry, at: 0)
        if persisted {
            persistIndex()
            pruneToCap()
        }
        return entry
    }

    /// The image of `entry`, from the session cache or the stored file, or
    /// nil when the file is gone (a corrupt entry the index kept).
    func image(for entry: PersistedCaptureEntry) -> CGImage? {
        if let cached = imageCache[entry.id] { return cached }
        guard let url = capturedFileURL(for: entry.fileName) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        imageCache[entry.id] = image
        return image
    }

    /// The validated URL of `entry`'s stored file (S2), or nil: only for a
    /// file name the hostile-name rule admits AND a file that actually exists
    /// on disk. The context menu's file actions read this — an item is
    /// offered only when there is a real URL behind it, so an offered item
    /// can never fail to find its file.
    func fileURL(for entry: PersistedCaptureEntry) -> URL? {
        guard let url = capturedFileURL(for: entry.fileName),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    /// Removes ONE entry (S2, the context menu's Delete): the entry leaves
    /// the in-memory array, its stored PNG is deleted, its session cache is
    /// dropped, and the persisted index is rewritten so a fresh store never
    /// lists it. The deletion goes through `capturedFileURL` and operates on
    /// the store's OWN in-list copy — a fake or hostile argument can only
    /// ever delete a file directly inside the captures folder.
    @discardableResult
    func remove(_ entry: PersistedCaptureEntry) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            Diag.log("capture history: remove ignored; not stored")
            return false
        }
        let removed = entries.remove(at: index)
        imageCache.removeValue(forKey: removed.id)
        deleteStoredFile(for: removed)
        persistIndex()
        Diag.log("capture history: removed entries=\(entries.count)")
        return true
    }

    /// Empties the history and deletes the stored captures with it (S2a):
    /// every file in the captures folder, the index, and the session cache.
    func clear() {
        entries.removeAll()
        imageCache.removeAll()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: capturesDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: indexURL)
    }

    // MARK: In-place rewrite (editor-save-in-place S2)

    /// The entry whose session-cached image IS `image` — the one the history
    /// sheet's Edit hands the editor (the panel loads through `image(for:)`,
    /// which returns the cached instance), so the one legitimate match is
    /// that same instance: no pixel scanning, no guessing for an image the
    /// store has never handed out (an edited variant, an evicted capture),
    /// which callers treat as no entry.
    func entry(for image: CGImage) -> PersistedCaptureEntry? {
        guard let (id, _) = imageCache.first(where: { $1 === image }) else { return nil }
        return entries.first { $0.id == id }
    }

    /// Rewrites ONE entry's stored PNG in place (editor-save-in-place S2):
    /// the file keeps its name, the entry keeps its id and date, and only
    /// the pixels — and the pixel size, when the edit cropped it — change,
    /// so a save can never become a second entry or a second file. The
    /// rewritten entry then takes the position a changed capture deserves
    /// (the open-sheet rule, the owner's first report): an edit is a new
    /// version of that capture, so it moves to the FRONT of the newest-first
    /// array, in memory and in the persisted index. The session cache is
    /// EVICTED, not refreshed: the pixels the panel — and any next Edit, and
    /// the Settings pane's re-reads — read come back as a fresh decode of
    /// the file that is now on disk, so every surface answers the SAME
    /// pixels from one source. Stuffing the composed instance into the
    /// cache would keep the cached decoded pixels and the later decodes on
    /// two different stories about what the capture is (owner's report one:
    /// "aun sigo sin ver que se actualice la preview"). False means "the
    /// store does not hold that id, or the write failed" — the caller
    /// decides the fallback.
    @discardableResult
    func rewrite(entryID: UUID, with image: CGImage) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
            let data = CaptureFile.data(for: image, format: .png)
        else {
            Diag.log("capture history: rewrite ignored; unknown entry")
            return false
        }
        do {
            try data.write(to: capturesDirectory.appendingPathComponent(entries[index].fileName))
        } catch {
            Diag.log("capture history: rewrite failed: \(error)")
            return false
        }
        let written = entries[index]
        // The move is a re-position, never a re-entry: the id, the date and
        // the file name stay the capture's own; only the pixels change —
        // and the position, to the front the newest-first order gives a
        // changed capture.
        entries[index] = PersistedCaptureEntry(
            id: written.id,
            date: written.date,
            pixelWidth: image.width,
            pixelHeight: image.height,
            fileName: written.fileName
        )
        if index != 0 {
            entries.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        }
        // The cache must not keep ANY decode from before the save: the next
        // `image(for:)` decodes the file this write just replaced, so the
        // panel cell, a re-open editor and a fresh store all agree pixel for
        // pixel. (Editor-save-in-place S2 — the store cache half of the
        // owner's first report.)
        imageCache.removeValue(forKey: written.id)
        persistIndex()
        Diag.log("capture history: rewrote \(written.fileName) \(image.width)x\(image.height) front=\(index == 0 ? 0 : 1)")
        return true
    }

    // MARK: Index

    /// The stored file's URL only when `fileName` names a file directly
    /// inside the captures folder: a single path component — no separator,
    /// no `..`, no empty or dot name. A hostile index entry naming a file
    /// outside the store (`../x.png`, `a/b.png`) never gets a URL, so it is
    /// never loaded and never deleted.
    private func capturedFileURL(for fileName: String) -> URL? {
        guard !fileName.isEmpty,
              fileName == (fileName as NSString).lastPathComponent,
              fileName != ".",
              fileName != ".."
        else { return nil }
        return capturesDirectory.appendingPathComponent(fileName)
    }

    /// Deletes the stored file of `entry` — through `capturedFileURL`, so
    /// even a hostile name can only ever reach a file directly inside the
    /// captures folder.
    private func deleteStoredFile(for entry: PersistedCaptureEntry) {
        guard let url = capturedFileURL(for: entry.fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        guard let loaded = try? JSONDecoder().decode([PersistedCaptureEntry].self, from: data) else {
            // Corrupt or partial index: behave like a fresh store; the next
            // add rewrites the index.
            Diag.log("capture history: index unreadable; starting empty")
            return
        }
        // Tolerant load: an entry whose file went missing (a partial write,
        // a manual deletion) cannot hand out an image, so it leaves; an
        // entry whose `fileName` leaves the captures folder is hostile and
        // leaves with it.
        let valid = loaded.filter { entry in
            guard let url = capturedFileURL(for: entry.fileName) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
        entries = Array(valid.prefix(Self.maxEntries))
        // The cap is enforced at load too: the entries `prefix` drops leave
        // no orphan files behind, the same way `pruneToCap` evicts.
        for entry in valid.dropFirst(Self.maxEntries) {
            imageCache.removeValue(forKey: entry.id)
            deleteStoredFile(for: entry)
        }
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(entries) else {
            Diag.log("capture history: index encoding failed")
            return
        }
        do {
            try data.write(to: indexURL)
        } catch {
            Diag.log("capture history: index write failed: \(error)")
        }
    }

    private func pruneToCap() {
        guard entries.count > Self.maxEntries else { return }
        // Entries are newest first, so the oldest ones sit at the tail: the
        // cap evicts from the back, never from the front.
        let evicted = entries[Self.maxEntries...]
        entries.removeLast(entries.count - Self.maxEntries)
        for entry in evicted {
            imageCache.removeValue(forKey: entry.id)
            deleteStoredFile(for: entry)
        }
    }
}
