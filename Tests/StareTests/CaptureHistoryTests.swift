import CoreGraphics
import XCTest
@testable import Stare
@testable import StareCore

/// The History pane and the editor handoff (T3/S12). The reopen has to reuse
/// the capture card's editor path — one editor, no second implementation — so
/// the reopening pane hands the remembered capture to the history's reopen
/// hook and the overlay routes that hook through the same handoff the card
/// fires. No windows are opened: the editor handoff is a test witness.
final class CaptureHistoryPaneTests: XCTestCase {

    private func solidImage(_ width: Int, _ height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// A store on a throwaway directory, so the pane never touches the
    /// user's real history.
    private func makeStore(_ images: [(Int, Int)]) throws -> CaptureHistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = CaptureHistoryStore(directory: directory)
        for (width, height) in images {
            _ = store.add(try XCTUnwrap(solidImage(width, height)))
        }
        return store
    }

    // MARK: The pane's reopen routes through the history hook

    func testOpeningAStoredCaptureHandsItToTheReopenHook() throws {
        let store = try makeStore([(10, 10)])
        let history = CaptureHistory(capacity: 2)
        var handed: CaptureHistoryEntry?
        history.onReopen = { handed = $0 }
        let pane = HistoryPane(store: store, history: history)

        let stored = try XCTUnwrap(store.entries.first)
        pane.open(stored)

        // A capture from an earlier session reopens exactly like one from this
        // one: the hook is the history's only editor path.
        XCTAssertEqual(handed?.id, stored.id)
        XCTAssertEqual(handed?.image.width, 10)
        XCTAssertEqual(handed?.image.height, 10)
        XCTAssertEqual(handed?.date, stored.date)
    }

    func testOpeningWithNoHookWiredChangesNothing() throws {
        let store = try makeStore([(10, 10)])
        let pane = HistoryPane(store: store, history: CaptureHistory(capacity: 2))

        // No reopen closure wired yet — the pane's open is a no-op, not a
        // crash, and it never removes the stored capture.
        pane.open(try XCTUnwrap(store.entries.first))
        XCTAssertEqual(store.entries.count, 1)
    }

    func testClearingThePaneEmptiesThePersistedHistory() throws {
        let store = try makeStore([(10, 10), (20, 10)])
        let pane = HistoryPane(store: store, history: CaptureHistory(capacity: 2))

        pane.clear()

        XCTAssertEqual(store.entries, [], "Clear forgets the stored history, not the session's list")
    }

    // MARK: The overlay wires the reopen through the editor handoff

    @MainActor
    func testTheOverlayWiresTheHistoryReopenToTheEditorHandoff() {
        let history = CaptureHistory(capacity: 2)
        let controller = OverlayController(
            captureService: CaptureService(),
            history: history
        )

        XCTAssertNotNil(
            history.onReopen,
            "the history pane's reopen must be wired by the overlay, or nothing in it can reopen a capture"
        )
    }

    @MainActor
    func testReopenHandsTheRememberedCaptureToTheEditorHandoff() throws {
        let history = CaptureHistory(capacity: 2)
        let composed = try XCTUnwrap(solidImage(10, 10))
        history.record(composed, at: Date())
        var handedImages: [CGImage] = []
        var handedPreferences: [CapturePreference] = []
        // Hold the controller: its reopen wiring is `[weak self]`, and a
        // controller nobody keeps would have its handoff torn down first.
        let controller = OverlayController(
            captureService: CaptureService(),
            history: history,
            editorHandoff: { image, preference in
                handedImages.append(image)
                handedPreferences.append(preference)
            }
        )
        defer { _ = controller }

        history.onReopen?(history.entries[0])

        XCTAssertEqual(handedImages.count, 1)
        // The image the editor receives is the capture as composed at
        // delivery — never a recomposition over the session's later state.
        XCTAssertTrue(handedImages[0] === composed)
        XCTAssertEqual(handedPreferences.count, 1)
        XCTAssertEqual(handedPreferences[0], .standard)
    }

    @MainActor
    func testTheEditorHandoffIsTheOneEntryTheCardAndTheHistoryShare() throws {
        let history = CaptureHistory(capacity: 2)
        let composed = try XCTUnwrap(solidImage(10, 10))
        var opened: [CGImage] = []
        let controller = OverlayController(
            captureService: CaptureService(),
            history: history,
            editorHandoff: { image, _ in
                opened.append(image)
            }
        )

        // The single handoff both entrances share: the card's onOpen calls it,
        // and so does the history reopen. With no mode active the guards
        // no-op and the editor still receives its call.
        controller.openCaptureEditor(composed)
        history.onReopen?(CaptureHistoryEntry(id: UUID(), image: composed, date: Date()))

        XCTAssertEqual(opened.count, 2)
        XCTAssertTrue(opened[0] === composed)
        XCTAssertTrue(opened[1] === composed)
    }
}

@testable import Stare

/// Tests for the persisted capture history store (S2/S2a): Application
/// Support layout, newest 50, newest-first order, clearing deletes the files,
/// and a corrupt or partial index never breaks a fresh load.
final class CaptureHistoryTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    // MARK: Helpers

    private func makeStoreDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stare-history-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeImage(width: Int = 8, height: Int = 6) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func capturesDirectory(of directory: URL) -> URL {
        directory.appendingPathComponent("captures", isDirectory: true)
    }

    private func indexURL(of directory: URL) -> URL {
        directory.appendingPathComponent("index.json")
    }

    private func storedFileNames(in directory: URL) -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: capturesDirectory(of: directory).path)) ?? []
        return Set(files)
    }

    // MARK: Order

    func testEntriesAreNewestFirst() {
        let directory = makeStoreDirectory()
        let store = CaptureHistoryStore(directory: directory)

        let first = store.add(makeImage(), date: Date(timeIntervalSince1970: 100))
        let second = store.add(makeImage(), date: Date(timeIntervalSince1970: 200))
        let third = store.add(makeImage(), date: Date(timeIntervalSince1970: 300))

        XCTAssertEqual(store.entries.map(\.id), [third.id, second.id, first.id])
    }

    // MARK: Cap

    func testStoreKeepsOnlyTheNewest50AndDeletesEvictedFiles() {
        let directory = makeStoreDirectory()
        let store = CaptureHistoryStore(directory: directory)

        var added: [PersistedCaptureEntry] = []
        for index in 0..<55 {
            added.append(store.add(makeImage(width: 4 + index % 3, height: 5), date: Date(timeIntervalSince1970: TimeInterval(index))))
        }

        XCTAssertEqual(store.entries.count, 50)
        // The newest 50 survive: the first five adds are evicted, the rest
        // stay, newest first.
        XCTAssertEqual(store.entries.map(\.id), added[5...].reversed().map(\.id))
        XCTAssertEqual(storedFileNames(in: directory), Set(store.entries.map(\.fileName)))
    }

    // MARK: Clear

    func testClearEmptiesTheEntriesAndDeletesTheStoredFiles() {
        let directory = makeStoreDirectory()
        let store = CaptureHistoryStore(directory: directory)
        _ = store.add(makeImage(), date: Date(timeIntervalSince1970: 1))
        _ = store.add(makeImage(), date: Date(timeIntervalSince1970: 2))

        store.clear()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(storedFileNames(in: directory).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL(of: directory).path))
    }

    // MARK: Persistence

    func testAFreshStoreInstanceSeesThePersistedEntriesAndImages() {
        let directory = makeStoreDirectory()
        let first = CaptureHistoryStore(directory: directory)
        let older = first.add(makeImage(width: 10, height: 4), date: Date(timeIntervalSince1970: 1))
        let newer = first.add(makeImage(width: 6, height: 12), date: Date(timeIntervalSince1970: 2))

        let second = CaptureHistoryStore(directory: directory)

        XCTAssertEqual(second.entries.map(\.id), [newer.id, older.id])
        XCTAssertEqual(second.entries.map(\.pixelWidth), [6, 10])
        XCTAssertEqual(second.entries.map(\.pixelHeight), [12, 4])
        XCTAssertEqual(second.image(for: newer)?.width, 6)
        XCTAssertEqual(second.image(for: older)?.height, 4)
    }

    // MARK: Corrupt or partial index

    func testACorruptIndexLoadsAsEmptyAndTheStoreKeepsWorking() {
        let directory = makeStoreDirectory()
        _ = CaptureHistoryStore(directory: directory).add(makeImage(), date: Date(timeIntervalSince1970: 1))
        try! Data("not an index".utf8).write(to: indexURL(of: directory))

        let fresh = CaptureHistoryStore(directory: directory)

        XCTAssertTrue(fresh.entries.isEmpty)
        // The store keeps working: the next add rebuilds a valid index.
        _ = fresh.add(makeImage(), date: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(CaptureHistoryStore(directory: directory).entries.count, 1)
    }

    func testEntriesWhoseFileIsMissingAreDroppedOnLoad() {
        let directory = makeStoreDirectory()
        let store = CaptureHistoryStore(directory: directory)
        let older = store.add(makeImage(), date: Date(timeIntervalSince1970: 1))
        _ = store.add(makeImage(), date: Date(timeIntervalSince1970: 2))
        try! FileManager.default.removeItem(at: capturesDirectory(of: directory).appendingPathComponent(older.fileName))

        let fresh = CaptureHistoryStore(directory: directory)

        XCTAssertEqual(fresh.entries.count, 1)
        XCTAssertEqual(fresh.entries.first?.date.timeIntervalSince1970, 2)
    }

    // MARK: Write failure never breaks the capture

    func testAWriteFailureKeepsTheCaptureInMemoryForTheSessionAndLogsIt() {
        let directory = makeStoreDirectory()
        // Make the captures folder unusable: a regular file sits where the
        // folder would be, so every PNG write fails.
        try! Data().write(to: capturesDirectory(of: directory))

        let store = CaptureHistoryStore(directory: directory)
        let entry = store.add(makeImage(), date: Date(timeIntervalSince1970: 1))

        // The capture stays in memory for the session: the panel can still
        // show and hand it out.
        XCTAssertEqual(store.entries.map(\.id), [entry.id])
        XCTAssertNotNil(store.image(for: entry))
        // Nothing was persisted: a fresh store sees nothing.
        XCTAssertTrue(CaptureHistoryStore(directory: directory).entries.isEmpty)
    }
}

/// The store's `remove` and `fileURL` (S2, the history's right-click menu):
/// removing ONE entry takes the entry, the stored PNG, the session cache and
/// the persisted index with it, and `fileURL` hands out the validated URL or
/// nil. Every byte these APIs touch lives inside the captures folder — the
/// hostile-name rule that guards load and prune guards them too.
final class CaptureHistoryStoreMenuAPITests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    // MARK: Helpers

    private func makeStoreDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stare-history-remove-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeImage(width: Int = 8, height: Int = 6) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makeStore(entries count: Int = 1) -> (CaptureHistoryStore, [PersistedCaptureEntry]) {
        let store = CaptureHistoryStore(directory: makeStoreDirectory())
        var added: [PersistedCaptureEntry] = []
        for index in 0..<count {
            added.append(store.add(
                makeImage(width: 10 + index, height: 8),
                date: Date(timeIntervalSince1970: TimeInterval(index + 1))
            ))
        }
        return (store, added.reversed())
    }

    private func capturesDirectory(of directory: URL) -> URL {
        directory.appendingPathComponent("captures", isDirectory: true)
    }

    private func indexURL(of directory: URL) -> URL {
        directory.appendingPathComponent("index.json")
    }

    private func storedIndexIDs(of directory: URL) -> [UUID]? {
        guard let data = try? Data(contentsOf: indexURL(of: directory)) else { return nil }
        return (try? JSONDecoder().decode([PersistedCaptureEntry].self, from: data))?.map(\.id)
    }

    // MARK: fileURL

    func testFileURLReturnsTheValidatedURLInsideTheCapturesFolder() {
        let (store, entries) = makeStore(entries: 2)
        let entry = entries[1]

        let url = store.fileURL(for: entry)

        XCTAssertEqual(url, capturesDirectory(of: store.directory).appendingPathComponent(entry.fileName))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path))
    }

    func testFileURLIsNilWhenTheFileIsGone() {
        let store = CaptureHistoryStore(directory: makeStoreDirectory())
        let entry = store.add(makeImage())
        try! FileManager.default.removeItem(
            at: capturesDirectory(of: store.directory).appendingPathComponent(entry.fileName)
        )

        XCTAssertNil(store.fileURL(for: entry), "a URL handed out for a missing file would end in a failing action")
    }

    func testFileURLIsNilForANameThatLeavesTheCapturesFolder() {
        let store = CaptureHistoryStore(directory: makeStoreDirectory())
        for name in [
            "../outside.png",
            "a/b.png",
            "",
            ".",
            "..",
            "/etc/passwd",
            "sub/../kept.png",
        ] {
            let hostile = PersistedCaptureEntry(
                id: UUID(), date: Date(), pixelWidth: 1, pixelHeight: 1, fileName: name
            )
            XCTAssertNil(store.fileURL(for: hostile), "the hostile name \(name) must never get a URL")
        }
    }

    // MARK: remove

    func testRemoveTakesTheEntryItsFileTheCacheAndTheIndexWithIt() {
        let (store, entries) = makeStore(entries: 2)
        let gone = entries[1] // the older of the two
        let survivors = entries[0]

        XCTAssertTrue(store.remove(gone))

        XCTAssertFalse(store.entries.map(\.id).contains(gone.id))
        XCTAssertEqual(store.entries.map(\.id), [survivors.id], "the other entry is untouched")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: capturesDirectory(of: store.directory).appendingPathComponent(gone.fileName).path
        ), "the removed entry's stored file is deleted")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: capturesDirectory(of: store.directory).appendingPathComponent(survivors.fileName).path
        ))
        XCTAssertNil(store.image(for: gone), "the removed entry's cache line is dropped with it")
        XCTAssertEqual(storedIndexIDs(of: store.directory), [survivors.id],
                       "the persisted index no longer lists the removed entry")
        // A fresh store agrees: nothing about the removal lives only in memory.
        let fresh = CaptureHistoryStore(directory: store.directory)
        XCTAssertEqual(fresh.entries.map(\.id), [survivors.id])
        XCTAssertNil(fresh.image(for: gone))
    }

    func testRemovingAnEntryThatIsNotInTheStoreChangesNothing() {
        let (store, entries) = makeStore(entries: 2)
        let outsider = PersistedCaptureEntry(
            id: UUID(), date: Date(), pixelWidth: 3, pixelHeight: 3, fileName: entries[0].fileName
        )

        XCTAssertFalse(store.remove(outsider))
        XCTAssertEqual(store.entries.map(\.id), entries.map(\.id))
        XCTAssertEqual(
            Set((try? FileManager.default.contentsOfDirectory(
                atPath: capturesDirectory(of: store.directory).path
            )) ?? []),
            Set(store.entries.map(\.fileName))
        )
    }

    func testARemoveArgumentWhoseIDMatchesCannotSendADeletionOutsideTheCapturesFolder() {
        let (store, entries) = makeStore(entries: 1)
        let victim = store.directory.appendingPathComponent("victim.png")
        try! Data("sentinel".utf8).write(to: victim) // outside captures/, inside the store root
        let deceitful = PersistedCaptureEntry(id: entries[0].id, date: Date(), pixelWidth: 1, pixelHeight: 1, fileName: "../victim.png")

        XCTAssertTrue(store.remove(deceitful), "the ID matches the stored entry, so the ENTRY leaves")
        // The removal operates on the store's OWN in-list copy: its real,
        // admitted file name went with it, and the deceitful name never
        // reached the disk at all.
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path),
                      "a hostile file name can never delete anything outside captures/")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: capturesDirectory(of: store.directory).appendingPathComponent(entries[0].fileName).path
        ), "the real entry's file went with the real entry")
    }
}
