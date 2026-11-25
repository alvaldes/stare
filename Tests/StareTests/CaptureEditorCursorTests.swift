import AppKit
import XCTest

@testable import Stare
import StareCore

/// Spec S3 of batch A: the capture editor answers with the active tool's own
/// cursor instead of a blanket arrow ("los cursores cambian" — they used to
/// change between the overlay and the editor, because the editor was
/// arrow-only). The editor's gesture cursors (space pan, pan drag, ⌘ + scroll)
/// keep winning over the tool's, and every cursor still goes through the
/// canvas's own `reassertCursor()` — the only place the editor sets a cursor.
@MainActor
final class CaptureEditorCursorTests: XCTestCase {
    private func solid(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func canvas(tool: Tool) -> CaptureEditorCanvas {
        let editor = CaptureEditorCanvas(image: solid(40, 20))
        let state = EditorState()
        state.tool = tool
        editor.state = state
        return editor
    }

    /// The pen over the editor answers with the pen's drawn glyph — a
    /// 16-pt image centred on the hotspot — never the plain arrow, and the
    /// reassertion wins over whatever cursor was showing before.
    func testTheEditorAnswersWithTheActiveToolSCursor() throws {
        let editor = canvas(tool: .pen)
        NSCursor.crosshair.set()
        editor.reassertCursor()

        let current = try XCTUnwrap(NSCursor.current)
        XCTAssertNotEqual(current, NSCursor.arrow, "the editor must not answer with a blanket arrow")
        XCTAssertEqual(current.image.size.width, 16, "the tool's drawn glyph is a 16-pt cursor")
        XCTAssertEqual(current.image.size.height, 16, "the tool's drawn glyph is a 16-pt cursor")
        XCTAssertEqual(current.hotSpot.x, 8, accuracy: 0.01, "the glyph is centred on the hotspot")
        XCTAssertEqual(current.hotSpot.y, 8, accuracy: 0.01, "the glyph is centred on the hotspot")
        NSCursor.arrow.set()
    }

    /// Switching the tool switches the answer: the eraser's ring replaces the
    /// pen's dot without the pointer ever leaving the canvas.
    func testASwitchedToolSwitchesTheAnswer() throws {
        let editor = canvas(tool: .pen)
        editor.reassertCursor()
        let penCursor = try XCTUnwrap(NSCursor.current)

        editor.state?.tool = .eraser
        editor.reassertCursor()
        let current = try XCTUnwrap(NSCursor.current)

        XCTAssertNotEqual(current, NSCursor.arrow, "the eraser keeps a tool cursor")
        XCTAssertNotEqual(
            current.image.tiffRepresentation, penCursor.image.tiffRepresentation,
            "the eraser's ring must not be the pen's dot")
        NSCursor.arrow.set()
    }

    /// The crop keeps the arrow: its staged rectangle has its own pointer
    /// vocabulary today, so arming the crop must not show a drawing tool's
    /// cursor while the region is being shaped.
    func testAnArmedCropKeepsTheArrow() throws {
        let editor = canvas(tool: .pen)
        editor.state?.selectCrop()
        editor.reassertCursor()
        XCTAssertEqual(NSCursor.current, NSCursor.arrow, "the armed crop keeps the plain arrow")
        NSCursor.arrow.set()
    }

    /// A tool that cannot work over a still image must never show its cursor
    /// here, even if the detached state still carries it.
    func testAWhiteboardOnlyToolNeverShowsItsCursorInTheEditor() throws {
        for tool in [Tool.select, .text, .laser] {
            let editor = canvas(tool: tool)
            editor.reassertCursor()
            XCTAssertEqual(NSCursor.current, NSCursor.arrow, "\(tool) has no cursor in the capture editor")
        }
        NSCursor.arrow.set()
    }

    /// The editor's own gesture cursors keep winning over the tool's: the
    /// space key shows the open hand, and releasing it hands the pointer back
    /// to the tool's cursor (not the arrow). Real key events, the canvas's own
    /// key handling, no new set() path.
    func testTheGestureCursorWinsOverTheToolSCursor() throws {
        let editor = canvas(tool: .pen)

        let down = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        ))
        editor.keyDown(with: down)
        XCTAssertEqual(NSCursor.current, NSCursor.openHand, "space held → open hand")

        let up = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        ))
        editor.keyUp(with: up)
        let current = try XCTUnwrap(NSCursor.current)
        XCTAssertNotEqual(current, NSCursor.arrow, "space released → back to the tool's cursor, not the arrow")
        XCTAssertEqual(current.hotSpot.x, 8, accuracy: 0.01, "back to the tool's centred glyph")
        NSCursor.arrow.set()
    }
}
