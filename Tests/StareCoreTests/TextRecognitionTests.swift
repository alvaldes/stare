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
        // ⌥⇧O became fixed for real; the pin's ⌥⇧L is gone (T4 pin fix, and
        // its dead constants removed in the T5 follow-up), so ⌥⇧L is free —
        // and must stay that way if it ever comes back.
        let taken: [HotkeyBinding] = [
            HotkeyAction.drawOverlay.defaultBinding, // ⌥⇧A
            HotkeyAction.pointerHighlight.defaultBinding, // ⌥⇧M
            HotkeyAction.pin.defaultBinding, // ⌥⇧P
            HotkeyAction.whiteboard.defaultBinding, // ⌥⇧W
            PinnedImageHotkeyDefaults.pin, // ⌥⇧I
            HotkeyBinding(key: .s, modifiers: [.option]), // ⌥S
            HotkeyBinding(key: .s, modifiers: [.shift]), // ⇧S
            HotkeyBinding(key: .s, modifiers: [.option, .shift]), // ⌥⇧S
            HotkeyBinding(key: .s, modifiers: []), // S
        ]
        XCTAssertFalse(
            taken.contains(TextRecognitionHotkeyDefaults.binding),
            "⌥⇧O must stay free for OCR")
        XCTAssertFalse(
            taken.contains(HotkeyBinding(key: .l, modifiers: [.option, .shift])),
            "⌥⇧L stays free: the pin's lock is the 🔒 control, the shortcut exists no more")
        XCTAssertEqual(TextRecognitionHotkeyDefaults.displayName, "⌥⇧O")
        XCTAssertEqual(TextRecognitionHotkeyDefaults.binding, HotkeyBinding(key: .o, modifiers: [.option, .shift]))
    }

    // MARK: - The surface state machine

    func testAPressFromIdleOpensTheSurface() {
        var machine = TextSelectionSurfaceMachine()
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.send(.hotkeyPressed), .opened)
        XCTAssertEqual(machine.phase, .inviting)
    }

    func testAPressWhileTheSurfaceIsUpCancelsItVisibly() {
        // A second press while the surface is open ends the gesture: the
        // outcome is visible (the surface closes) — the shortcut is never
        // left dead behind an open surface.
        var machine = TextSelectionSurfaceMachine(phase: .inviting)
        XCTAssertEqual(machine.send(.hotkeyPressed), .close(cancelled: true))
        XCTAssertEqual(machine.phase, .closing)

        var dragging = TextSelectionSurfaceMachine(phase: .dragging)
        XCTAssertEqual(dragging.send(.hotkeyPressed), .close(cancelled: true))
        XCTAssertEqual(dragging.phase, .closing)

        // A press during teardown is owned by the teardown, not the hotkey.
        var closing = TextSelectionSurfaceMachine(phase: .closing)
        XCTAssertEqual(closing.send(.hotkeyPressed), .ignored)
    }

    func testEscapeCancelsWhileTheSurfaceIsUp() {
        var inviting = TextSelectionSurfaceMachine(phase: .inviting)
        XCTAssertEqual(inviting.send(.escapePressed), .close(cancelled: true))
        XCTAssertEqual(inviting.phase, .closing)

        var dragging = TextSelectionSurfaceMachine(phase: .dragging)
        XCTAssertEqual(dragging.send(.escapePressed), .close(cancelled: true))

        var closing = TextSelectionSurfaceMachine(phase: .closing)
        XCTAssertEqual(closing.send(.escapePressed), .ignored)
        XCTAssertEqual(closing.phase, .closing)
    }

    func testADragMovesTheSurfaceIntoDraggingInPlace() {
        var machine = TextSelectionSurfaceMachine(phase: .inviting)
        XCTAssertEqual(machine.send(.dragStarted), .beganDrag)
        XCTAssertEqual(machine.phase, .dragging)
        // A second drag-start inside a drag is nothing new.
        XCTAssertEqual(machine.send(.dragStarted), .ignored)
        XCTAssertEqual(machine.phase, .dragging)
    }

    func testAStrayClickCancelsTheGestureFromAnyLivingPhase() {
        // A bare click — before a drag, or a mouseUp whose rect misses the
        // 4×4 minimum — is not a selection: the gesture ends cancelled.
        var inviting = TextSelectionSurfaceMachine(phase: .inviting)
        XCTAssertEqual(inviting.send(.clickDismissed), .close(cancelled: true))

        var dragging = TextSelectionSurfaceMachine(phase: .dragging)
        XCTAssertEqual(dragging.send(.clickDismissed), .close(cancelled: true))
        XCTAssertEqual(dragging.phase, .closing)
    }

    func testACommittedSelectionClosesTheSurfaceForDelivery() {
        var machine = TextSelectionSurfaceMachine(phase: .dragging)
        XCTAssertEqual(machine.send(.selectionCommitted), .close(cancelled: false))
        XCTAssertEqual(machine.phase, .closing)
        // There is nothing to commit before a drag starts.
        var inviting = TextSelectionSurfaceMachine(phase: .inviting)
        XCTAssertEqual(inviting.send(.selectionCommitted), .ignored)
    }

    func testAnIdleTimeoutDismissesOnlyBeforeADragStarts() {
        // The idling surface is the safety net for a shortcut the system
        // cannot see: it closes itself only while the user has committed
        // nothing — never mid-drag.
        var inviting = TextSelectionSurfaceMachine(phase: .inviting)
        XCTAssertEqual(inviting.send(.idleTimedOut), .close(cancelled: true))

        var dragging = TextSelectionSurfaceMachine(phase: .dragging)
        XCTAssertEqual(dragging.send(.idleTimedOut), .ignored)
        XCTAssertEqual(dragging.phase, .dragging, "a drag is never interrupted by idling")
    }

    func testTheSurfaceClosingResetsTheMachineToIdleFromAnyPhase() {
        // The teardown is the ground truth: whatever phase the machine was
        // in, once the surface is closed the next press opens fresh.
        for phase in [TextSelectionSurfacePhase.inviting, .dragging, .closing] {
            var machine = TextSelectionSurfaceMachine(phase: phase)
            XCTAssertEqual(machine.send(.surfaceClosed), .reverted)
            XCTAssertEqual(machine.phase, .idle)
        }
        var idle = TextSelectionSurfaceMachine()
        XCTAssertEqual(idle.send(.surfaceClosed), .ignored)
        XCTAssertEqual(idle.phase, .idle)
    }

    func testTheInstructionCopyShowsOnlyWhileInviting() {
        XCTAssertEqual(
            TextRecognitionSurfaceCopy.instruction(for: .inviting),
            "Drag over text to copy it · Esc to cancel")
        for phase in [TextSelectionSurfacePhase.idle, .dragging, .closing] {
            XCTAssertEqual(
                TextRecognitionSurfaceCopy.instruction(for: phase), "",
                "the drag itself and the teardown carry no instruction copy")
        }
        XCTAssertGreaterThan(TextRecognitionSurfaceCopy.idleDismissAfter, 0)
    }

    func testPointerOnNoDisplayIsSaidInThePill() {
        XCTAssertEqual(TextRecognitionFeedback.noDisplay.title, "No display under the pointer")
    }
}
