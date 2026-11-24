import AppKit
import Foundation
import XCTest

@testable import Stare

/// The store's index hardening: an entry whose `fileName` leaves the store's
/// own captures folder (a path separator, `..`) never loads, and the files a
/// hostile index names are never read or deleted — the prune a later `add()`
/// runs must leave them alone. Also: the 50-entry cap is enforced at load,
/// deleting the files of the entries the cap drops (inside `captures/` only).
final class CaptureHistoryIndexPathTests: XCTestCase {
    /// The store keeps the newest 50 captures (S2a).
    private let maxEntries = 50

    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    // MARK: Helpers

    /// A root that is NOT the store directory itself: the store lives in
    /// `root/store/captures`, so an index entry can name a file outside
    /// `captures/` but still inside `root`, which deletion must never touch.
    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stare-index-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(
            at: root.appendingPathComponent("store/captures", isDirectory: true),
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(root)
        return root
    }

    private func makeStoreDirectory(root: URL) -> URL {
        root.appendingPathComponent("store", isDirectory: true)
    }

    private func capturesDirectory(of directory: URL) -> URL {
        directory.appendingPathComponent("captures", isDirectory: true)
    }

    private func indexURL(of directory: URL) -> URL {
        directory.appendingPathComponent("index.json")
    }

    private func makeImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return context.makeImage()!
    }

    private func pngData() -> Data {
        let representation = NSBitmapImageRep(cgImage: makeImage())
        return representation.representation(using: .png, properties: [:])!
    }

    private func entry(id: UUID, fileName: String, date: Date) -> PersistedCaptureEntry {
        PersistedCaptureEntry(
            id: id,
            date: date,
            pixelWidth: 2,
            pixelHeight: 2,
            fileName: fileName
        )
    }

    private func storedFileNames(in directory: URL) -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: capturesDirectory(of: directory).path)) ?? []
        return Set(files)
    }

    // MARK: Hostile file names

    func testAnIndexEntryWhoseFileNameLeavesTheCapturesFolderIsDroppedAtLoadAndItsFileSurvivesALaterAdd() throws {
        let root = makeRoot()
        let storeDirectory = makeStoreDirectory(root: root)
        // The files the hostile entries name: `captures/../second-outside.png`
        // and `captures/../../outside.png` — real files outside the captures
        // folder.
        let storeSideURL = storeDirectory.appendingPathComponent("second-outside.png")
        let parentURL = root.appendingPathComponent("outside.png")
        try pngData().write(to: storeSideURL)
        try pngData().write(to: parentURL)
        // 49 valid entries with real files, then two hostile entries pointing
        // at those real outside files (inside the loaded cap window, so a
        // later add's prune reaches them): the verifier's probe.
        var entries: [PersistedCaptureEntry] = []
        for index in 0..<(maxEntries - 1) {
            let name = "kept-\(index).png"
            try pngData().write(to: capturesDirectory(of: storeDirectory).appendingPathComponent(name))
            entries.append(entry(id: UUID(), fileName: name, date: Date(timeIntervalSince1970: TimeInterval(index))))
        }
        entries.append(entry(id: UUID(), fileName: "../second-outside.png", date: Date(timeIntervalSince1970: 1000)))
        entries.append(entry(id: UUID(), fileName: "../../outside.png", date: Date(timeIntervalSince1970: 1001)))
        try JSONEncoder().encode(entries).write(to: indexURL(of: storeDirectory))

        let fresh = CaptureHistoryStore(directory: storeDirectory)

        XCTAssertEqual(fresh.entries.count, maxEntries - 1, "only the single-component, in-folder entries load")
        XCTAssertFalse(
            fresh.entries.contains { $0.fileName != ($0.fileName as NSString).lastPathComponent },
            "no entry whose fileName leaves the captures folder survives the load"
        )

        // A later add runs the prune: the evicted file is the store's own,
        // and the hostile entries' unrelated files must survive.
        let added = fresh.add(makeImage())

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeSideURL.path), "an add never deletes a file outside captures/")
        XCTAssertTrue(FileManager.default.fileExists(atPath: parentURL.path), "an add never deletes a file outside captures/")
        XCTAssertEqual(
            storedFileNames(in: storeDirectory),
            Set(fresh.entries.map(\.fileName)),
            "the captures folder holds exactly the loaded entries' files"
        )
        XCTAssertEqual(fresh.entries.map(\.fileName).first, added.fileName, "the new capture is the newest entry")
        XCTAssertEqual(fresh.entries.count, maxEntries - 1 + 1)
    }

    // MARK: Cap at load

    func testLoadingEnforcesTheCapAndDeletesTheFilesOfTheEntriesItDrops() throws {
        let root = makeRoot()
        let storeDirectory = makeStoreDirectory(root: root)
        // A disk state the add path can no longer produce (an older version's
        // or a foreign tool's index): 55 valid entries with all files present.
        var files: Set<String> = []
        var entries: [PersistedCaptureEntry] = []
        for index in 0..<55 {
            let name = "kept-\(index).png"
            try pngData().write(to: capturesDirectory(of: storeDirectory).appendingPathComponent(name))
            files.insert(name)
            entries.append(entry(id: UUID(), fileName: name, date: Date(timeIntervalSince1970: TimeInterval(index))))
        }
        try JSONEncoder().encode(entries).write(to: indexURL(of: storeDirectory))

        let fresh = CaptureHistoryStore(directory: storeDirectory)

        XCTAssertEqual(fresh.entries.count, maxEntries)
        XCTAssertEqual(
            storedFileNames(in: storeDirectory),
            Set(fresh.entries.map(\.fileName)),
            "the cap also holds at load: the entries it drops leave no orphan files"
        )
        XCTAssertEqual(storedFileNames(in: storeDirectory).count, maxEntries)
    }
}
