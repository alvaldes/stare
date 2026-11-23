import CoreGraphics
import XCTest
@testable import StareCore

/// The pure decisions of on-device OCR and QR (T5/S7): how recognition
/// observations become the clipboard string, the plan for the selection
/// (stray click dismissed, oversize downscaled), the crop of a screen
/// selection into display pixels, the user-facing copy, and the fixed
/// `⌥⇧O` binding's freedom from every other shortcut.
final class TextRecognitionTests: XCTestCase {
    private func observation(
        _ payload: String,
        centerYTop: Double,
        centerX: Double = 100
    ) -> TextRecognitionObservation {
        TextRecognitionObservation(payload: payload, centerY: centerYTop, centerX: centerX)
    }

    // MARK: - Reading order

    func testObservationsAreOrderedTopToBottom() {
        // Vision's coordinate space: larger centerY = higher on the page, so
        // the clipboard string must read top-first.
        let outcome = TextRecognition.clipboardOutcome(from: [
            observation("bottom", centerYTop: 10),
            observation("top", centerYTop: 300),
            observation("middle", centerYTop: 150),
        ])
        XCTAssertEqual(outcome, .clipboard("top\nmiddle\nbottom"))
    }

    func testObservationsOnOneLineAreOrderedLeftToRight() {
        let outcome = TextRecognition.clipboardOutcome(from: [
            observation("right", centerYTop: 100, centerX: 500),
            observation("left", centerYTop: 100, centerX: 50),
        ])
        XCTAssertEqual(outcome, .clipboard("left\nright"))
    }

    func testMixedTextAndQrMergeInReadingOrder() {
        // A payload from a QR code is one observation among the text lines:
        // position, not kind, decides the reading order.
        let text = [
            observation("before", centerYTop: 900),
            observation("after", centerYTop: 100),
        ]
        let qr = [observation("https://stare.test/qr", centerYTop: 500)]
        let outcome = TextRecognition.clipboardOutcome(from: text + qr)
        XCTAssertEqual(outcome, .clipboard("before\nhttps://stare.test/qr\nafter"))
    }

    // MARK: - Empty and whitespace results

    func testNoObservationsMeansNothingFound() {
        XCTAssertEqual(TextRecognition.clipboardOutcome(from: []), .nothingFound)
    }

    func testWhitespaceOnlyObservationsMeansNothingFound() {
        XCTAssertEqual(
            TextRecognition.clipboardOutcome(from: [
                observation("   ", centerYTop: 100),
                observation("\t\n", centerYTop: 50),
            ]),
            .nothingFound)
    }

    func testLineEdgesAreTrimmedButInteriorTextIsKept() {
        let outcome = TextRecognition.clipboardOutcome(from: [
            observation("  spaced   out  ", centerYTop: 100, centerX: 10),
            observation("second", centerYTop: 60, centerX: 510),
        ])
        XCTAssertEqual(outcome, .clipboard("spaced   out\nsecond"))
    }

    // MARK: - Selection plan

    func testAStrayClickBelowTheMinimumIsDismissed() {
        // The same 4×4 stray-click rule area capture uses: below the minimum
        // the gesture ends without capturing anything.
        let plan = TextRecognition.plan(
            selection: CGRect(x: 0, y: 0, width: 6, height: 3),
            displayScale: 2)
        XCTAssertEqual(plan, .dismiss)
    }

    func testExactlyTheMinimumIsWorthy() {
        let plan = TextRecognition.plan(
            selection: CGRect(x: 0, y: 0, width: 4, height: 4),
            displayScale: 1)
        XCTAssertEqual(plan, .capture(scale: 1))
    }

    func testASelectionAtTheDisplayScaleIsUsedAsIs() {
        let plan = TextRecognition.plan(
            selection: CGRect(x: 0, y: 0, width: 400, height: 300),
            displayScale: 3)
        XCTAssertEqual(plan, .capture(scale: 3))
    }

    func testAnOversizeSelectionIsDownscaledToThePixelBudget() {
        // 2400×1800 points at scale 3 is 7200 pixels on the long side, past
        // the 4096 cap: the plan returns the scale that brings the longest
        // side back to the cap exactly.
        let plan = TextRecognition.plan(
            selection: CGRect(x: 0, y: 0, width: 2400, height: 1800),
            displayScale: 3,
            maxPixelSide: 4096)
        guard case let .capture(scale) = plan else {
            return XCTFail("expected a capture plan, got \(plan)")
        }
        XCTAssertEqual(2400 * scale, 4096, accuracy: 0.001)
        XCTAssertTrue(scale < 3)
    }

    // MARK: - Crop mapping

    func testSelectionInScreenPointsMapsIntoDisplayPixelsWithTopLeftOrigin() {
        // A display at global (100, 200) sized 2000×1500, selection the
        // middle band: the crop lands top-left relative to the display's
        // frame, because capture pixel space has its origin at the top.
        let screenFrame = CGRect(x: 100, y: 200, width: 2000, height: 1500)
        let selection = CGRect(x: 300, y: 900, width: 400, height: 300)
        let crop = TextRecognition.cropRect(selection: selection, in: screenFrame, pixelScale: 2)
        XCTAssertEqual(crop, CGRect(x: 400, y: 600, width: 800, height: 600))
    }

    // MARK: - User-facing copy

    func testFeedbackCopySaysWhatHappened() {
        XCTAssertEqual(
            TextRecognitionFeedback.permissionMissing.title,
            "Screen Recording permission needed · System Settings → Privacy",
            "the missing-permission copy is the one the app already uses elsewhere")
        XCTAssertEqual(TextRecognitionFeedback.nothingFound.title, "No text found")
        XCTAssertEqual(TextRecognitionFeedback.failed.title, "Text recognition failed")
    }

    // MARK: - The fixed shortcut is free

    func testTheOcrShortcutDoesNotCollideWithAnyOtherShortcut() {
        // The pinned-image defaults reserve ⌥⇧O for OCR by contract; here it
        // becomes fixed for real, and the pin makes that contract testable.
        let taken: [HotkeyBinding] = [
            HotkeyAction.drawOverlay.defaultBinding, // ⌥⇧A
            HotkeyAction.pointerHighlight.defaultBinding, // ⌥⇧M
            HotkeyAction.pin.defaultBinding, // ⌥⇧P
            HotkeyAction.whiteboard.defaultBinding, // ⌥⇧W
            PinnedImageHotkeyDefaults.pin, // ⌥⇧I
            PinnedImageHotkeyDefaults.lock, // ⌥⇧L
            HotkeyBinding(key: .s, modifiers: [.option]), // ⌥S
            HotkeyBinding(key: .s, modifiers: [.shift]), // ⇧S
            HotkeyBinding(key: .s, modifiers: [.option, .shift]), // ⌥⇧S
            HotkeyBinding(key: .s, modifiers: []), // S
        ]
        XCTAssertFalse(
            taken.contains(TextRecognitionHotkeyDefaults.binding),
            "⌥⇧O must stay free for OCR")
        XCTAssertEqual(TextRecognitionHotkeyDefaults.displayName, "⌥⇧O")
        XCTAssertEqual(TextRecognitionHotkeyDefaults.binding, HotkeyBinding(key: .o, modifiers: [.option, .shift]))
    }
}
