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

    // MARK: The pane's reopen routes through the history hook

    func testOpeningAnEntryHandsTheEntryToTheReopenHook() throws {
        let history = CaptureHistory(capacity: 2)
        let entry = CaptureHistoryEntry(
            id: UUID(),
            image: try XCTUnwrap(solidImage(10, 10)),
            date: Date(timeIntervalSince1970: 100)
        )
        history.onReopen = { handed in
            XCTAssertEqual(handed.id, entry.id)
            XCTAssertTrue(handed.image === entry.image)
        }
        let pane = HistoryPane(history: history)

        pane.open(entry)
    }

    func testOpeningWithNoHookWiredChangesNothing() throws {
        let history = CaptureHistory(capacity: 2)
        let composed = try XCTUnwrap(solidImage(10, 10))
        history.record(composed, at: Date())
        let pane = HistoryPane(history: history)

        // No reopen closure wired yet — the pane's open is a no-op, not a
        // crash, and it never mutates the history.
        pane.open(history.entries[0])
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertTrue(history.entries[0].image === composed)
    }

    func testClearingThePaneEmptiesTheHistory() throws {
        let history = CaptureHistory(capacity: 2)
        history.record(try XCTUnwrap(solidImage(10, 10)), at: Date())
        history.record(try XCTUnwrap(solidImage(20, 10)), at: Date())
        let pane = HistoryPane(history: history)

        pane.clear()

        XCTAssertEqual(history.entries, [])
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
