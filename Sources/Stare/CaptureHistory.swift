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
