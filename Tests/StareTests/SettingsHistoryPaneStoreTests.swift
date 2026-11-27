import AppKit
import Combine
import SwiftUI
import XCTest

@testable import Stare
import StareCore

/// The two warnings the Settings slice's review raised, pinned:
/// the pane must read the SAME store the ⌥⇧I panel reads (two stores on one
/// directory diverge in memory), and a row whose capture file is gone must not
/// offer an Open that silently does nothing.
final class SettingsHistoryPaneStoreTests: XCTestCase {
    private func solid(
        _ width: Int, _ height: Int,
        red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1
    ) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
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

    /// The announcement itself, at the store: a successful rewrite carries
    /// the rewritten entry (its refreshed pixel size, its front position);
    /// a rewrite the store refuses — an unknown id — announces nothing, the
    /// way it writes nothing.
    func testTheStoreAnnouncesOnlySuccessfulRewritesWithTheRewrittenEntry() throws {
        let store = try makeStore([(10, 10), (12, 8)])
        var announced: [PersistedCaptureEntry] = []
        let listener = store.rewriteAnnounced.sink { announced.append($0) }
        defer { _ = listener }

        XCTAssertFalse(
            store.rewrite(entryID: UUID(), with: try XCTUnwrap(solid(20, 20, red: 1, green: 0, blue: 0))),
            "an unknown entry is not the store's to rewrite"
        )
        XCTAssertTrue(announced.isEmpty, "a refused rewrite announces nothing")

        let entry = store.entries[1]
        XCTAssertTrue(store.rewrite(entryID: entry.id, with: try XCTUnwrap(solid(20, 12, red: 0, green: 0, blue: 1))))

        XCTAssertEqual(announced.map(\.id), [entry.id], "the announcement is the rewritten entry, the one the pane re-reads for")
        XCTAssertEqual(announced.last?.pixelWidth, 20, "the announced entry carries the saved pixel size")
        XCTAssertEqual(store.entries.first?.id, entry.id, "the announced entry sits at the front the move gave it")
    }

    // MARK: A standing-open pane follows a rewrite (editor-save-in-place)

    /// The pane's whole rendered content, one RGBA channel per pixel.
    private struct PaneRender {
        let data: [UInt8]
        let width: Int
        let height: Int
    }

    /// Rows of one colour somewhere in a render: min and max y.
    private struct ColourBand {
        let minY: Int
        let maxY: Int
    }

    /// The two saturated row colours make the assertions channel-exact:
    /// magenta and red differ only in blue, red and green in red, so no
    /// label ink, button accent (blue, but never pure) or separator can
    /// answer as either thumbnail.
    private let isRed = { (r: CGFloat, g: CGFloat, b: CGFloat) in r > 0.8 && g < 0.3 && b < 0.3 }
    private let isGreen = { (r: CGFloat, g: CGFloat, b: CGFloat) in g > 0.8 && r < 0.3 && b < 0.3 }
    private let isMagenta = { (r: CGFloat, g: CGFloat, b: CGFloat) in r > 0.8 && g < 0.3 && b > 0.8 }

    /// The pane on a real window, once — the SAME hosting view (and through
    /// it the SAME pane instance, with its `@State`) renders before and
    /// after the rewrite: recreating either would be the fresh-open
    /// behaviour every fresh open already has.
    @MainActor
    private func renderedPane(_ pane: HistoryPane) -> (view: NSHostingView<HistoryPane>, window: NSWindow) {
        let size = CGSize(width: 460, height: 800)
        let hosting = NSHostingView(rootView: pane)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.appearance = NSAppearance(named: .aqua)
        // Never order a test window front on whatever display holds the
        // pointer: park it on the primary screen first.
        window.confineToPrimaryScreen()
        window.orderFrontRegardless()
        return (hosting, window)
    }

    /// One render's pixels: the view's cached display, re-read row-major.
    private func pixels(of view: NSView) throws -> PaneRender {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = try XCTUnwrap(rep.cgImage)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let buffer = try XCTUnwrap(context.data)
        let pointer = buffer.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        let data = Array(UnsafeBufferPointer(start: pointer, count: image.width * image.height * 4))
        return PaneRender(data: data, width: image.width, height: image.height)
    }

    /// The y-extent of the rows matching one colour predicate.
    private func band(
        in pixels: PaneRender,
        matching matches: (CGFloat, CGFloat, CGFloat) -> Bool
    ) -> ColourBand? {
        var minY: Int?
        var maxY: Int?
        for y in 0..<pixels.height {
            for x in stride(from: 0, to: pixels.width, by: 2) {
                let i = (y * pixels.width + x) * 4
                if matches(
                    CGFloat(pixels.data[i]) / 255.0,
                    CGFloat(pixels.data[i + 1]) / 255.0,
                    CGFloat(pixels.data[i + 2]) / 255.0
                ) {
                    if minY == nil { minY = y }
                    maxY = y
                    break
                }
            }
        }
        guard let minY, let maxY else { return nil }
        return ColourBand(minY: minY, maxY: maxY)
    }

    /// (evidence test, editor-save-in-place — the Settings pane's half) A
    /// rewrite through the store reaches a pane that is already standing
    /// open: the SAME pane instance renders before and after, and afterwards
    /// its own pixels show the SAVED colour in the rewritten row's slot, at
    /// the FRONT (the store's open-sheet rule for an in-place save).
    /// Unrecreated by construction: a fresh open is not the defect.
    @MainActor
    func testARewriteReachesAStandingOpenPaneWithoutRecreatingIt() throws {
        // Two entries, the one to rewrite the OLDER one: its rewrite has a
        // real position to win (the front) and a VALUE-EQUAL entry row —
        // same id, same date, no crop, so only the pixels change — the case
        // a value-keyed re-render would skip.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureHistoryStore(directory: directory)
        let kept = store.add(try XCTUnwrap(solid(24, 16, red: 0, green: 1, blue: 0)), date: Date(timeIntervalSince1970: 1))
        _ = store.add(try XCTUnwrap(solid(24, 16, red: 1, green: 0, blue: 1)), date: Date(timeIntervalSince1970: 2))

        let pane = HistoryPane(store: store, history: CaptureHistory(capacity: 2))
        let (hosting, window) = renderedPane(pane)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))

        let before = try pixels(of: hosting)
        let magentaBefore = try XCTUnwrap(band(in: before, matching: isMagenta), "the untouched entry's row renders")
        let greenBefore = try XCTUnwrap(band(in: before, matching: isGreen), "the to-be-rewritten entry's row renders")
        XCTAssertNil(band(in: before, matching: isRed), "nothing rewritten yet, the saved colour is nowhere on screen")
        
        // The buffer's vertical direction, read from the one order the
        // store's newest-first array dictates (magenta is the front row): a
        // cgImage's scanline order is an implementation detail, and the
        // position half below reads "front" through this SAME direction.
        let frontIsLowY = magentaBefore.minY < greenBefore.minY

        // The edit: the ONE store call an in-place save makes — same id, same
        // date, same 24×16 (no crop), only the pixels. The pane instance is
        // never recreated; only its own re-read can move the pixels.
        XCTAssertTrue(store.rewrite(
            entryID: kept.id,
            with: try XCTUnwrap(solid(24, 16, red: 1, green: 0, blue: 0))
        ))
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))

        window.orderOut(nil)
        let after = try pixels(of: hosting)
        let magentaAfter = try XCTUnwrap(band(in: after, matching: isMagenta), "the untouched entry's row is still there")
        let redAfter = try XCTUnwrap(band(in: after, matching: isRed), "the pixels must be the NEW ones, not the green the entry had")
        XCTAssertNil(
            band(in: after, matching: isGreen),
            "the pane's own pixels must show the saved pixels — the rewritten capture's old colour must be gone (the owner's report, the pane half)"
        )
        let movedToFront = frontIsLowY
            ? redAfter.minY < magentaAfter.minY
            : redAfter.minY > magentaAfter.minY
        XCTAssertTrue(movedToFront, "the rewritten capture sits in the front row the store's rewrite gives it")
    }

    /// Canary naming its report (editor-save-in-place, the Settings pane's
    /// half): a standing-open pane cannot see a rewrite on its own — the
    /// store is not observable, and the rewritten row is VALUE-EQUAL (same
    /// id, same date) — so the pane's ONE re-read mechanism is the store's
    /// rewrite announcement running the SAME `historyRevision` bump its
    /// Clear re-read already uses, re-keying the captures card the way the
    /// sheet's `.id(model.revision)` keys the grid. A refactor that invents
    /// a second listener or a poll, or drops the store's announcement,
    /// fails here.
    func testCanaryThePanesReReadIsTheStoreRewriteAnnouncementRunningItsClearRevisionBump() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        let paneSource = try String(
            contentsOf: url.appendingPathComponent("Sources/Stare/SettingsHistoryPane.swift"),
            encoding: .utf8)
        XCTAssertTrue(
            paneSource.contains(".onReceive(store.rewriteAnnounced)"),
            "the pane's re-read rides the ONE announcement the store's rewrite makes"
        )
        XCTAssertEqual(
            paneSource.components(separatedBy: ".id(historyRevision)").count - 1,
            1,
            "the announcement reuses the SAME revision bump the Clear re-read uses — no second re-read mechanism"
        )
        let storeSource = try String(
            contentsOf: url.appendingPathComponent("Sources/Stare/CaptureHistory.swift"),
            encoding: .utf8)
        XCTAssertTrue(
            storeSource.contains("rewriteAnnounced.send"),
            "the store — the one source both history surfaces read — announces the rewrite"
        )
    }
}
