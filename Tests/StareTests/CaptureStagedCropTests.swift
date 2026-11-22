import XCTest
import CoreGraphics
@testable import Stare
import StareCore

/// S6/T4: the staged crop. Dropping the marquee — or finishing a grip drag
/// over an applied region — does NOT cut the pixels any more: the rectangle
/// stays on screen with its grips, adjustable by moving and resizing, until
/// Return confirms (exactly one journal step) or Escape / picking a tool
/// gives it up with nothing applied. The tests drive real mouse and key
/// events through `CaptureEditorCanvas` the way the existing crop tests do,
/// and judge everything through `composedImage()` — the public interface
/// the user's own Save/Copy go through.
@MainActor
final class CaptureStagedCropTests: XCTestCase {

    private static func solidImage(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// A black left half and a white right half, so two different regions of
    /// the same size compose differently and a moved rectangle is visible in
    /// what the crop cuts, not just in its size.
    private static func splitImage(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return context.makeImage()
    }

    private func event(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1)
    }

    // MARK: - Fixtures

    private struct Editor {
        let canvas: CaptureEditorCanvas
        let state: EditorState
        let window: NSWindow
    }

    private static func makeEditor(image: CGImage) -> Editor {
        let canvas = CaptureEditorCanvas(image: image)
        let state = EditorState()
        canvas.state = state
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas
        XCTAssertEqual(canvas.bounds.size, CGSize(width: 300, height: 200))
        return Editor(canvas: canvas, state: state, window: window)
    }

    private func down(_ editor: Editor, at point: CGPoint) throws {
        editor.canvas.mouseDown(with: try XCTUnwrap(
            event(.leftMouseDown, at: point, window: editor.window)))
    }

    private func dragged(_ editor: Editor, to point: CGPoint) throws {
        editor.canvas.mouseDragged(with: try XCTUnwrap(
            event(.leftMouseDragged, at: point, window: editor.window)))
    }

    private func up(_ editor: Editor, at point: CGPoint) throws {
        editor.canvas.mouseUp(with: try XCTUnwrap(
            event(.leftMouseUp, at: point, window: editor.window)))
    }

    /// The standing marquee: drag (50,100)–(150,200) over a 100×100 capture
    /// in a 300×200 window stages the pixel region (0, 50, 50, 50) as the
    /// rectangle waiting for Return.
    private func stageStandingRectangle(_ editor: Editor) throws {
        editor.state.selectCrop()
        try down(editor, at: CGPoint(x: 50, y: 100))
        try dragged(editor, to: CGPoint(x: 150, y: 200))
        try up(editor, at: CGPoint(x: 150, y: 200))
    }

    /// A real Return key press through the canvas's key handling.
    private func pressReturn(_ editor: Editor) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: editor.window.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36))
        editor.canvas.keyDown(with: event)
    }

    /// The bounding box of everything that is not pure white, in top-left
    /// origin coordinates — enough to tell a moved crop apart from the
    /// un-moved one over the split image.
    private func inkBox(of image: CGImage) -> CGRect? {
        let rep = NSBitmapImageRep(cgImage: image)
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if colour.greenComponent < 0.92 || colour.blueComponent < 0.92 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    let top = rep.pixelsHigh - 1 - y
                    minY = min(minY, top); maxY = max(maxY, top)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: - Deliverable 1: the marquee no longer applies the crop

    func testAStagedMarqueeLeavesTheImageWholeWithItsRectangleWaiting() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try stageStandingRectangle(editor)

        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(composed.width, 100, "the drop must not cut the pixels yet")
        XCTAssertEqual(composed.height, 100)

        // One selection state, as today: the crop stays the armed item
        // while its rectangle waits, so the user can go on adjusting it.
        XCTAssertTrue(editor.state.isCropMarked)
        XCTAssertTrue(editor.canvas.showsCropHint, "the hint names how to confirm")
    }

    // MARK: - Deliverable 4: Return confirms, exactly as the old apply did

    func testReturnConfirmsTheStagedCropAndJournalsExactlyOneStep() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try stageStandingRectangle(editor)

        try pressReturn(editor)

        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(composed.width, 50, "the staged rectangle (0,50,50,50) became the applied crop")
        XCTAssertEqual(composed.height, 50)
        let box = try XCTUnwrap(inkBox(of: composed))
        XCTAssertEqual(box.width, 50, accuracy: 1.5, "the crop must be black over the split's left half")
        // Exactly one journal step: one ⌘Z returns the whole picture.
        editor.canvas.undo()
        let undone = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(undone.width, 100)
        XCTAssertEqual(undone.height, 100)
        // And ⇧⌘Z replays it.
        editor.canvas.redo()
        let replayed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(replayed.width, 50)
        XCTAssertEqual(replayed.height, 50)
        // The epilogue of the old apply holds: the mark goes back to the
        // remembered tool.
        XCTAssertFalse(editor.state.isCropMarked)
        XCTAssertFalse(editor.canvas.showsCropHint, "nothing is pending any more")
    }

    func testEscapeDropsTheStagedRectangleAndLeavesTheImageExactlyAsItWas() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try stageStandingRectangle(editor)

        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: editor.window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        editor.canvas.keyDown(with: escape)

        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(composed.width, 100, "Escape leaves the picture whole")
        XCTAssertEqual(composed.height, 100)
        XCTAssertFalse(editor.canvas.showsCropHint)
        XCTAssertFalse(editor.state.isCropMarked, "the mark goes back to the remembered tool")

        // No journal step: the picture is exactly as it was, and neither ⌘Z
        // nor ⇧⌘Z can move it.
        editor.canvas.undo()
        try XCTAssertEqual(
            NSBitmapImageRep(cgImage: editor.canvas.composedImage() ?? image).tiffRepresentation ?? Data(),
            NSBitmapImageRep(cgImage: composed).tiffRepresentation ?? Data(),
            "⌘Z must have nothing to reverse — the cancel journalized nothing")
        editor.canvas.redo()
        try XCTAssertEqual(
            NSBitmapImageRep(cgImage: editor.canvas.composedImage() ?? image).tiffRepresentation ?? Data(),
            NSBitmapImageRep(cgImage: composed).tiffRepresentation ?? Data(),
            "⇧⌘Z must have nothing to replay either")

        // The dropped rectangle cannot come back: a later Return confirms
        // nothing.
        editor.state.selectCrop()
        try pressReturn(editor)
        let unconfirmed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(unconfirmed.width, 100, "Return with no staged rectangle confirms nothing")
    }

    // MARK: - Deliverable 2: the pending rectangle is adjustable

    func testThePendingRectangleCanBeMovedBeforeReturn() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try stageStandingRectangle(editor)
        // At 0.5 px/pt the staged rect (0,50,50,50) has the view rect
        // (50,100)-(150,200). Its whole crop starts as pure black.
        try down(editor, at: CGPoint(x: 100, y: 150))
        try dragged(editor, to: CGPoint(x: 114, y: 150))
        try up(editor, at: CGPoint(x: 114, y: 150))

        let whole = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(whole.width, 100, "the move must not cut the pixels either")
        XCTAssertEqual(whole.height, 100)

        try pressReturn(editor)
        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(composed.width, 50, "the MOVED rectangle is what got confirmed")
        XCTAssertEqual(composed.height, 50)
        // The region moved 7 px right: the composition must expose 7 px of
        // white on the right of what was a pure-black crop.
        let box = try XCTUnwrap(inkBox(of: composed))
        XCTAssertEqual(box.width, 43, accuracy: 2, "the crop starts 7 px into the black half")
    }

    func testThePendingRectangleCanBeResizedBeforeReturn() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try stageStandingRectangle(editor)
        // At 0.5 px/pt the staged rect (0,50,50,50) has the view rect
        // (50,100)-(150,200); its bottom-right grip sits at (150,200).
        // Dragging that grip to (166,140) → pixel (58,70) resizes the
        // region to (0,50,58,20).
        try down(editor, at: CGPoint(x: 150, y: 200))
        try dragged(editor, to: CGPoint(x: 166, y: 140))
        try up(editor, at: CGPoint(x: 166, y: 140))

        let whole = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(whole.width, 100, "the resize must not cut the pixels either")
        XCTAssertEqual(whole.height, 100)

        try pressReturn(editor)
        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(composed.width, 58, "the RESIZED rectangle is what got confirmed")
        XCTAssertEqual(composed.height, 20)
        let box = try XCTUnwrap(inkBox(of: composed))
        XCTAssertEqual(box.height, 20, accuracy: 1.5, "the crop kept the resized height")
    }

    // MARK: - Deliverable 3: the hint

    func testTheHintShowsWhileTheRectangleIsPendingAndGoesAfterConfirming() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        XCTAssertFalse(editor.canvas.showsCropHint, "nothing pending, nothing to hint")

        try stageStandingRectangle(editor)
        XCTAssertTrue(
            editor.canvas.showsCropHint,
            "a staged rectangle must say how to confirm it — Hit ↵ to crop")

        try pressReturn(editor)
        XCTAssertFalse(
            editor.canvas.showsCropHint,
            "after the pixels are cut the hint goes away")
    }

    // MARK: - Deliverable 5: picking a tool drops the rectangle

    func testPickingAToolDropsThePendingRectangleAndMarksThatTool() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try stageStandingRectangle(editor)
        XCTAssertTrue(editor.canvas.showsCropHint)

        editor.state.tool = .number
        XCTAssertTrue(editor.state.isToolMarked(.number), "one selection state: the tool is marked")
        XCTAssertFalse(editor.state.isCropMarked, "the crop is not, as today")
        XCTAssertFalse(editor.canvas.showsCropHint, "the dropped rectangle stops hinting")

        let composed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(composed.width, 100, "dropping the rectangle applies nothing")

        // The dropped rectangle cannot be confirmed afterwards.
        editor.state.selectCrop()
        try pressReturn(editor)
        let unconfirmed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(unconfirmed.width, 100)
    }

    // MARK: - Deliverable 6: a re-entered applied region also waits

    func testAReenteredAppliedRegionAlsoWaitsForReturn() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try stageStandingRectangle(editor)
        try pressReturn(editor)
        let first = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(first.width, 50)

        // Re-enter the crop: the applied region's grips are live (S7), and
        // a drag on its bottom-right grip — at view (150,200) at 0.5 px/pt —
        // must STAGE again, not cut: the user must always be able to adjust
        // before the pixels move. Drag to (166,140) → pixel (58,70) resizes
        // the region to (0,50,58,20).
        editor.state.selectCrop()
        try down(editor, at: CGPoint(x: 150, y: 200))
        try dragged(editor, to: CGPoint(x: 166, y: 140))
        try up(editor, at: CGPoint(x: 166, y: 140))

        let staged = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(staged.width, 50, "the drag did not cut yet — the first crop still holds")
        XCTAssertEqual(staged.height, 50)
        XCTAssertTrue(editor.canvas.showsCropHint, "the staged rectangle names its confirm key again")

        try pressReturn(editor)
        let confirmed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(confirmed.width, 58, "Return cut the adjusted region (0,50,58,20)")
        XCTAssertEqual(confirmed.height, 20)
        XCTAssertFalse(editor.canvas.showsCropHint)
    }

    func testEscapeAfterAdjustingAnAppliedRegionKeepsTheAppliedCrop() throws {
        let image = try XCTUnwrap(Self.splitImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        try stageStandingRectangle(editor)
        try pressReturn(editor)
        let applied = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(applied.width, 50)

        // Re-enter, stir the grips — the grip at view (150,200) is dragged
        // to (166,140) — then cancel: the applied crop stays exactly as it
        // was and the cancel journals nothing (S7/T4).
        editor.state.selectCrop()
        try down(editor, at: CGPoint(x: 150, y: 200))
        try dragged(editor, to: CGPoint(x: 166, y: 140))
        try up(editor, at: CGPoint(x: 166, y: 140))
        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: editor.window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        editor.canvas.keyDown(with: escape)

        let kept = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(kept.width, 50, "the applied crop survives the staged adjustment's Escape")
        XCTAssertEqual(kept.height, 50)

        // The journal still holds exactly one step: ⌘Z removes the applied
        // crop and ⇧⌘Z brings it back — the staged stir left no trace.
        editor.canvas.undo()
        let undone = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(undone.width, 100)
        editor.canvas.redo()
        let replayed = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(replayed.width, 50)
    }
}
