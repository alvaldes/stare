import XCTest
import CoreGraphics
@testable import Stare
import StareCore

/// S7/T11: an applied crop and the editor's marks share one undo journal, so ⌘Z
/// reverses whichever edit was newest. The verifier found the first wiring
/// only covered drag-committed marks: a click tool commits inside `begin`
/// (the numbered badge lands in the document but never in the journal), and
/// a gesture that changes nothing — a click with no drag — must journal
/// nothing either, so one ⌘Z always reverses one real edit.
@MainActor
final class CaptureCropJournalTests: XCTestCase {

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

    /// A real Return key press through the canvas's key handling: under the
    /// staged crop (T4/S6) Return is what commits the dropped rectangle —
    /// the mouseUp no longer applies anything.
    private func pressReturn(_ editor: Editor) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: editor.window.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36))
        editor.canvas.keyDown(with: event)
    }

    /// The standing 50-px crop the repros start from: marquee (50,100)–(150,200)
    /// over a 100×100 capture in a 300×200 window stages the pixel region
    /// (0, 50, 50, 50), and Return confirms it (the staged flow, T4/S6 — the
    /// mouseUp only drops the rectangle).
    private func applyStandingCropByReturn(_ editor: Editor) throws {
        editor.state.selectCrop()
        try down(editor, at: CGPoint(x: 50, y: 100))
        try dragged(editor, to: CGPoint(x: 150, y: 200))
        try up(editor, at: CGPoint(x: 150, y: 200))
        try pressReturn(editor)
    }

    /// A real click: mouse down and up at one point, no dragged events —
    /// the repro's "click with no drag".
    private func click(_ editor: Editor, at point: CGPoint) throws {
        try down(editor, at: point)
        try up(editor, at: point)
    }

    private func drag(_ editor: Editor, from origin: CGPoint, to end: CGPoint) throws {
        try down(editor, at: origin)
        try dragged(editor, to: end)
        try up(editor, at: end)
    }

    // MARK: - Pixel comparison

    private func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private func assertPixels(
        _ value: CGImage?, equals expected: CGImage?, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let valueData = try XCTUnwrap(
            pngData(try XCTUnwrap(value, message, file: file, line: line)),
            message, file: file, line: line)
        let expectedData = try XCTUnwrap(
            pngData(try XCTUnwrap(expected, message, file: file, line: line)),
            message, file: file, line: line)
        XCTAssertEqual(valueData, expectedData, message, file: file, line: line)
    }

    private func assertPixels(
        _ value: CGImage?, differsFrom expected: CGImage?, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let valueData = try XCTUnwrap(
            pngData(try XCTUnwrap(value, message, file: file, line: line)),
            message, file: file, line: line)
        let expectedData = try XCTUnwrap(
            pngData(try XCTUnwrap(expected, message, file: file, line: line)),
            message, file: file, line: line)
        XCTAssertNotEqual(valueData, expectedData, message, file: file, line: line)
    }

    // MARK: - The shared journal walk

    /// Walks the journal all the way down and back up: after undo k the
    /// document is stage `3 − k`, after redo k it is back at stage k — redo
    /// replays exactly the opposite order of the undos (S7).
    private func assertWalkDownAndBackUp(_ editor: Editor, stages: [CGImage]) throws {
        precondition(stages.count == 4)
        for stage in stride(from: 2, through: 0, by: -1) {
            editor.canvas.undo()
            try assertPixels(
                editor.canvas.composedImage(), equals: stages[stage],
                "undo \(3 - stage) must be back at editing stage \(stage)")
        }
        for stage in 1...3 {
            editor.canvas.redo()
            try assertPixels(
                editor.canvas.composedImage(), equals: stages[stage],
                "redo \(stage) must replay stage \(stage) — the opposite order of the undos")
        }
    }

    // MARK: - Click tools journal (N2)

    /// A click tool commits inside `session.begin`, so a whole-session
    /// comparison in `mouseUp` saw no change and never journaled the badge —
    /// ⌘Z then undid the earlier crop instead. The badge must enter the
    /// journal exactly once: undo removes it and keeps the crop, redo brings
    /// it back.
    func testCropThenABadgeClickUndoRemovesTheBadgeAndKeepsTheCrop() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)

        try applyStandingCropByReturn(editor)
        let cropped = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(cropped.width, 50, "the crop applied")

        editor.state.tool = .number
        try click(editor, at: CGPoint(x: 100, y: 100))
        let inked = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(inked.width, 50, "the badge click keeps the crop")
        try assertPixels(inked, differsFrom: cropped, "the click inked one badge")

        editor.canvas.undo()
        let undone = try XCTUnwrap(editor.canvas.composedImage())
        try assertPixels(undone, equals: cropped, "⌘Z removes the badge and keeps the crop")

        editor.canvas.redo()
        let replayed = try XCTUnwrap(editor.canvas.composedImage())
        try assertPixels(replayed, equals: inked, "⇧⌘Z puts the badge back")
    }

    // MARK: - Gestures that change nothing journal nothing (N1)

    /// A click with no drag must not journal: the old comparison compared the
    /// whole session, so the degenerate commit (which only cleared `active`
    /// and left an invisible mark) journalized an edit that never changed the
    /// document — and ⌘Z was swallowed by it.
    func testAClickWithoutADragAddsNoJournalStep() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        let uncropped = try XCTUnwrap(editor.canvas.composedImage())

        try applyStandingCropByReturn(editor)
        let cropped = try XCTUnwrap(editor.canvas.composedImage())
        XCTAssertEqual(cropped.width, 50)

        editor.state.tool = .pen
        editor.state.ink = .red
        try click(editor, at: CGPoint(x: 100, y: 100))
        let afterClick = try XCTUnwrap(editor.canvas.composedImage())
        try assertPixels(afterClick, equals: cropped, "the stray click paints nothing")

        editor.canvas.undo()
        let undone = try XCTUnwrap(editor.canvas.composedImage())
        try assertPixels(undone, equals: uncropped, "⌘Z reverses the crop — the only real edit")

        editor.canvas.redo()
        let replayed = try XCTUnwrap(editor.canvas.composedImage())
        try assertPixels(replayed, equals: cropped, "⇧⌘Z replays the crop")
    }

    /// N1's second repro: two crops with a stray click between them — the two
    /// undos must return their own distinct regions, never the same one twice.
    func testTwoCropsAroundAStrayClickUndoToTheirOwnRegions() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        let uncropped = try XCTUnwrap(editor.canvas.composedImage())

        try applyStandingCropByReturn(editor)
        let firstCrop = try XCTUnwrap(editor.canvas.composedImage())

        editor.state.tool = .pen
        try click(editor, at: CGPoint(x: 100, y: 100))

        // A second crop over the other half, drawn while the region is live:
        // the armed view covers the whole original, so the same view marquee
        // lands on the original's pixels.
        editor.state.selectCrop()
        try down(editor, at: CGPoint(x: 150, y: 100))
        try dragged(editor, to: CGPoint(x: 250, y: 200))
        try up(editor, at: CGPoint(x: 250, y: 200))
        try pressReturn(editor)
        let secondCrop = try XCTUnwrap(editor.canvas.composedImage())
        try assertPixels(secondCrop, differsFrom: firstCrop, "the two crops cover different sides")

        editor.canvas.undo()
        try assertPixels(
            editor.canvas.composedImage(), equals: firstCrop,
            "the first ⌘Z removes the second crop")

        editor.canvas.undo()
        try assertPixels(
            editor.canvas.composedImage(), equals: uncropped,
            "the second ⌘Z removes the first crop — the stray click ate nothing")
    }

    // MARK: - Mixed sequences replay in the opposite order (N3)

    /// crop → badge click → drag: undos reverse the drag, the badge, then the
    /// crop; redos replay the crop, the badge, then the drag.
    func testCropClickDragWalksDownAndBackUp() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        var stages = [try XCTUnwrap(editor.canvas.composedImage())]

        try applyStandingCropByReturn(editor)
        stages.append(try XCTUnwrap(editor.canvas.composedImage()))

        editor.state.tool = .number
        try click(editor, at: CGPoint(x: 100, y: 100))
        stages.append(try XCTUnwrap(editor.canvas.composedImage()))

        editor.state.tool = .pen
        editor.state.ink = .red
        try drag(editor, from: CGPoint(x: 120, y: 80), to: CGPoint(x: 180, y: 120))
        stages.append(try XCTUnwrap(editor.canvas.composedImage()))

        try assertWalkDownAndBackUp(editor, stages: stages)
    }

    /// drag → crop → badge click: the same walk must land on the same stages
    /// in reverse, whatever order the edit kinds came in.
    func testDragCropClickWalksDownAndBackUp() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        var stages = [try XCTUnwrap(editor.canvas.composedImage())]

        editor.state.tool = .pen
        editor.state.ink = .red
        try drag(editor, from: CGPoint(x: 120, y: 80), to: CGPoint(x: 180, y: 120))
        stages.append(try XCTUnwrap(editor.canvas.composedImage()))

        try applyStandingCropByReturn(editor)
        stages.append(try XCTUnwrap(editor.canvas.composedImage()))

        editor.state.tool = .number
        try click(editor, at: CGPoint(x: 100, y: 100))
        stages.append(try XCTUnwrap(editor.canvas.composedImage()))

        try assertWalkDownAndBackUp(editor, stages: stages)
    }

    /// badge click → crop → drag: the third ordering, same walk.
    func testClickCropDragWalksDownAndBackUp() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let editor = Self.makeEditor(image: image)
        var stages = [try XCTUnwrap(editor.canvas.composedImage())]

        editor.state.tool = .number
        try click(editor, at: CGPoint(x: 100, y: 100))
        stages.append(try XCTUnwrap(editor.canvas.composedImage()))

        try applyStandingCropByReturn(editor)
        stages.append(try XCTUnwrap(editor.canvas.composedImage()))

        editor.state.tool = .pen
        editor.state.ink = .red
        try drag(editor, from: CGPoint(x: 120, y: 80), to: CGPoint(x: 180, y: 120))
        stages.append(try XCTUnwrap(editor.canvas.composedImage()))

        try assertWalkDownAndBackUp(editor, stages: stages)
    }

    // MARK: - The two already-pinned orders (previous fix)

    /// crop -> draw -> undo must reverse the mark, not the earlier crop.
    func testCropThenDrawUndoesTheNewestEdit() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let canvas = CaptureEditorCanvas(image: image)
        let state = EditorState()
        canvas.state = state
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas
        XCTAssertEqual(canvas.bounds.size, CGSize(width: 300, height: 200))

        state.selectCrop()
        canvas.mouseDown(with: try XCTUnwrap(event(.leftMouseDown, at: CGPoint(x: 50, y: 100), window: window)))
        canvas.mouseDragged(with: try XCTUnwrap(event(.leftMouseDragged, at: CGPoint(x: 150, y: 200), window: window)))
        canvas.mouseUp(with: try XCTUnwrap(event(.leftMouseUp, at: CGPoint(x: 150, y: 200), window: window)))
        // The staged flow (T4/S6): the drop only staged the rectangle; Return cuts.
        canvas.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)))
        let cropped = try XCTUnwrap(canvas.composedImage())
        XCTAssertLessThan(cropped.width, 100, "the crop applied")

        state.tool = .pen
        state.ink = .red
        canvas.mouseDown(with: try XCTUnwrap(event(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window)))
        canvas.mouseDragged(with: try XCTUnwrap(event(.leftMouseDragged, at: CGPoint(x: 140, y: 100), window: window)))
        canvas.mouseUp(with: try XCTUnwrap(event(.leftMouseUp, at: CGPoint(x: 140, y: 100), window: window)))
        let afterMark = try XCTUnwrap(canvas.composedImage())

        canvas.undo()
        let afterUndo = try XCTUnwrap(canvas.composedImage())
        XCTAssertEqual(afterUndo.width, afterMark.width, "⌘Z must reverse the newest edit (the mark), not the earlier crop")
        XCTAssertEqual(afterUndo.height, afterMark.height)

        canvas.redo()
        let afterRedo = try XCTUnwrap(canvas.composedImage())
        XCTAssertEqual(afterRedo.width, afterMark.width, "⇧⌘Z replays the mark, not the crop")
    }

    /// draw -> crop -> ⌘Z twice must reverse the crop first, then the mark;
    /// ⇧⌘Z replays them the opposite way (S7).
    func testDrawThenCropUndoesTheNewestEdit() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let canvas = CaptureEditorCanvas(image: image)
        let state = EditorState()
        canvas.state = state
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas

        state.tool = .pen
        state.ink = .red
        canvas.mouseDown(with: try XCTUnwrap(event(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window)))
        canvas.mouseDragged(with: try XCTUnwrap(event(.leftMouseDragged, at: CGPoint(x: 140, y: 100), window: window)))
        canvas.mouseUp(with: try XCTUnwrap(event(.leftMouseUp, at: CGPoint(x: 140, y: 100), window: window)))
        let full = try XCTUnwrap(canvas.composedImage())
        XCTAssertEqual(full.width, 100)

        state.selectCrop()
        canvas.mouseDown(with: try XCTUnwrap(event(.leftMouseDown, at: CGPoint(x: 50, y: 100), window: window)))
        canvas.mouseDragged(with: try XCTUnwrap(event(.leftMouseDragged, at: CGPoint(x: 150, y: 200), window: window)))
        canvas.mouseUp(with: try XCTUnwrap(event(.leftMouseUp, at: CGPoint(x: 150, y: 200), window: window)))
        // The staged flow (T4/S6): the drop only staged the rectangle; Return cuts.
        canvas.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)))
        let cropped = try XCTUnwrap(canvas.composedImage())
        XCTAssertLessThan(cropped.width, 100, "the crop applied")

        // ⌘Z reverses the newest edit — the crop — and the mark stays.
        canvas.undo()
        let afterFirstUndo = try XCTUnwrap(canvas.composedImage())
        XCTAssertEqual(afterFirstUndo.width, full.width, "⌘Z must reverse the crop, not the earlier mark")
        XCTAssertEqual(afterFirstUndo.height, full.height)

        // The next ⌘Z reverses the mark again.
        canvas.undo()
        let afterSecondUndo = try XCTUnwrap(canvas.composedImage())
        XCTAssertEqual(afterSecondUndo.width, full.width, "the second ⌘Z removes the mark")

        // ⇧⌘Z replays the most recently undone edit first: the mark, then
        // the crop — the exact opposite order of the two undos above.
        canvas.redo()
        let afterFirstRedo = try XCTUnwrap(canvas.composedImage())
        XCTAssertEqual(afterFirstRedo.width, full.width, "⇧⌘Z must replay the mark before the crop")

        canvas.redo()
        let afterSecondRedo = try XCTUnwrap(canvas.composedImage())
        XCTAssertEqual(afterSecondRedo.width, cropped.width, "the crop comes back too")
    }
}
