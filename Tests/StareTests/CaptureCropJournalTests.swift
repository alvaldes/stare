import XCTest
import CoreGraphics
@testable import Stare
import StareCore

/// S7/T11: an applied crop and the editor's marks share one undo journal, so ⌘Z
/// reverses whichever edit was newest. The verifier found this unwired.
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
