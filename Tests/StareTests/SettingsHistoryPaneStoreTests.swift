import AppKit
import XCTest

@testable import Stare
import StareCore

/// The two warnings the Settings slice's review raised, pinned:
/// the pane must read the SAME store the ⌥⇧I panel reads (two stores on one
/// directory diverge in memory), and a row whose capture file is gone must not
/// offer an Open that silently does nothing.
final class SettingsHistoryPaneStoreTests: XCTestCase {
    private func solid(_ width: Int, _ height: Int) -> CGImage? {
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

    private func makeStore(_ images: [(Int, Int)]) throws -> CaptureHistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = CaptureHistoryStore(directory: directory)
        for (width, height) in images {
            _ = store.add(try XCTUnwrap(solid(width, height)))
        }
        return store
    }

    /// R3-001: the default is the one store the app runs on. Identity only —
    /// this test must never mutate the real history.
    func testThePaneDefaultsToTheOneStoreThePanelReads() {
        let pane = HistoryPane(history: CaptureHistory(capacity: 1))
        XCTAssertTrue(
            pane.store === CaptureHistoryStore.shared,
            "the pane and the ⌥⇧I panel must read the same store, or a Clear in one is invisible to the other"
        )
    }

    /// R3-002, as far as it can actually happen: the store drops, at load, any
    /// entry whose file went missing (`loadIndex` filters on the file), so the
    /// dead-button state is only reachable in-session. The guard is still the
    /// right one — a row without an image and without the hook must not offer a
    /// live-looking Open — and it is what the button and the action share.
    func testARowWithoutTheEditorHookCannotBeOpened() throws {
        let store = try makeStore([(10, 10)])
        let pane = HistoryPane(store: store, history: CaptureHistory(capacity: 2))

        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertFalse(pane.canOpen(entry), "no editor hook, nothing to open with")
        pane.open(entry)
        XCTAssertEqual(store.entries.count, 1, "and opening it changes nothing")
    }

    func testACaptureWhoseFileIsThereCanBeOpened() throws {
        let store = try makeStore([(10, 10)])
        let history = CaptureHistory(capacity: 2)
        var opened = 0
        history.onReopen = { _ in opened += 1 }
        let pane = HistoryPane(store: store, history: history)

        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertTrue(pane.canOpen(entry))
        pane.open(entry)
        XCTAssertEqual(opened, 1)
    }
}
