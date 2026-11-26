import AppKit
import SwiftUI
import XCTest

@testable import Stare
import StareCore

/// Round four S5: "no esta resuelto sigue mostrando el custom cursor del tool
/// activo sobre la barra y sobre el window title y los botones de la ventana
/// del editor". The armed tool's cursor answers ONLY over the image; over the
/// editor's own chrome — the palette row, the window title, the window
/// buttons — it is the plain arrow, and leaving the image and re-entering it
/// behave both ways. The correction rides the ONE cursor path: the
/// canvas-backed decision `CaptureEditorCanvas.cursor(atWindowPoint:)`, and
/// the content routes every crossing (its own tracking area, the canvas's
/// exit) through it — no second ambient `set()`.
@MainActor
final class CaptureEditorCursorChromeTests: XCTestCase {
    private func solid(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private struct Editor {
        let window: CaptureEditorWindow
        let content: CaptureEditorContent
        let canvas: CaptureEditorCanvas
        let chrome: NSHostingView<EditorChrome>
        let state: EditorState

        /// A point of the editor's content, in window coordinates — the space
        /// `event.locationInWindow` carries and the cursor decision reads.
        func windowPoint(_ contentPoint: CGPoint) -> CGPoint {
            content.convert(contentPoint, to: nil)
        }

        var chromeWindowPoint: CGPoint {
            windowPoint(CGPoint(x: chrome.frame.midX, y: chrome.frame.midY))
        }

        var canvasWindowPoint: CGPoint {
            windowPoint(CGPoint(x: canvas.frame.midX, y: canvas.frame.midY))
        }

        /// Somewhere over the window's title bar, above the content row.
        var titleBarWindowPoint: CGPoint {
            CGPoint(x: window.frame.width / 2, y: window.contentView!.bounds.height + 12)
        }
    }

    private static func makeEditor(image: CGImage) -> Editor {
        let window = CaptureEditorWindow(
            image: image, capture: .standard, redactionStyle: .blur, onDeliver: nil,
            onClose: { _ in })
        window.confineToPrimaryScreen()
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        let content = try! XCTUnwrap(
            window.editorContent, "the editor window was built around its content")
        return Editor(
            window: window,
            content: content,
            canvas: content.canvas,
            chrome: content.chrome,
            state: content.state)
    }

    /// The active pen's own glyph: a 16-pt drawn image centred on its hotspot
    /// — the vocabulary `CaptureEditorCursorTests` pins for the tool cursor.
    private func assertToolCursor(message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let current = NSCursor.current
        XCTAssertFalse(current === NSCursor.arrow, "never the blanket arrow\(message.isEmpty ? "" : ": \(message)")", file: file, line: line)
        XCTAssertEqual(current.image.size.width, 16, "the tool's drawn glyph, not the blanket arrow", file: file, line: line)
        XCTAssertEqual(current.image.size.height, 16, "the tool's drawn glyph, not the blanket arrow", file: file, line: line)
        XCTAssertEqual(current.hotSpot.x, 8, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(current.hotSpot.y, 8, accuracy: 0.01, file: file, line: line)
    }

    // MARK: - The one decision: the tool's glyph over the picture, the arrow over the chrome

    func testTheToolsCursorAnswersOnlyOverTheImage() throws {
        let editor = Self.makeEditor(image: solid(300, 200))
        defer { editor.window.orderOut(nil) }
        editor.state.tool = .pen

        // The canvas-backed decision itself: over the picture the armed
        // tool's own glyph answers.
        let decision = editor.canvas.cursor(atWindowPoint: editor.canvasWindowPoint)
        XCTAssertEqual(decision.image.size.width, 16, "over the picture the armed tool's own glyph answers")
        XCTAssertEqual(decision.image.size.height, 16, "over the picture the armed tool's own glyph answers")
        XCTAssertEqual(decision.hotSpot.x, 8, accuracy: 0.01, "the glyph is centred on the hotspot")
        XCTAssertEqual(decision.hotSpot.y, 8, accuracy: 0.01, "the glyph is centred on the hotspot")

        // The same decision through the content route (the chrome's own row,
        // the title bar): the arrow answers over everything the picture is
        // not — the palette, the title bar, the window buttons.
        XCTAssertEqual(
            editor.content.cursor(atWindowPoint: editor.chromeWindowPoint),
            NSCursor.arrow, "the palette row is the chrome's: the arrow answers")
        XCTAssertEqual(
            editor.content.cursor(atWindowPoint: editor.titleBarWindowPoint),
            NSCursor.arrow, "the window title is the chrome's too")
        XCTAssertNotEqual(decision, NSCursor.arrow, "the tool's glyph is no blanket arrow over the picture")
    }

    // MARK: - Leaving the image and re-entering it both behave

    /// The canvas's own exit answer routes the ONE decision: the pointer
    /// leaving the picture — onto the palette row, the title bar, the window
    /// buttons or out of the window — hands the arrow over, never the stale
    /// tool glyph the owner watched sit over the bar.
    func testLeavingTheImageHandsTheArrowBack() throws {
        let editor = Self.makeEditor(image: solid(300, 200))
        defer { editor.window.orderOut(nil); NSCursor.arrow.set() }
        editor.state.tool = .pen
        editor.canvas.reassertCursor()
        assertToolCursor(message: "the pen's glyph is what the picture answers while the pointer sits on it")

        // AppKit refuses to synthesize `.mouseExited/.mouseEntered` events
        // (`NSEvent has no public constructor` — the same limitation the
        // cursorUpdate delivery tests document), so the crossing events below
        // are `.mouseMoved` carries: the handlers route their LOCATION through
        // the one decision, and the location is the pin.
        let exit = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: editor.chromeWindowPoint, modifierFlags: [],
            timestamp: 0, windowNumber: editor.window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0))
        editor.canvas.mouseExited(with: exit)

        XCTAssertEqual(NSCursor.current, NSCursor.arrow, "the chrome answered the arrow on the way out")

        // A crossing into the title bar itself leaves through the content: the
        // same decision, the same arrow.
        let titleExit = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: editor.titleBarWindowPoint, modifierFlags: [],
            timestamp: 0, windowNumber: editor.window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0))
        editor.content.mouseExited(with: titleExit)
        XCTAssertEqual(NSCursor.current, NSCursor.arrow, "the title bar is the arrow's too")
    }

    /// Re-entering the picture re-asserts the armed tool's glyph — the entry
    /// half of the leave/enter pair,/S5's "make both behave".
    func testReenteringTheImageRestoresTheToolCursor() throws {
        let editor = Self.makeEditor(image: solid(300, 200))
        defer { editor.window.orderOut(nil); NSCursor.arrow.set() }
        editor.state.tool = .pen

        let enter = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: editor.canvasWindowPoint, modifierFlags: [],
            timestamp: 0, windowNumber: editor.window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0))
        editor.canvas.mouseEntered(with: enter)

        assertToolCursor(message: "the tool glyph came back when the pointer came back")
    }

    // MARK: - The delivery half: the content owns the cursor tracking area

    /// AppKit delivers `cursorUpdate` only through a tracking area, and the
    /// chrome (the content above the canvas) never declared one — that
    /// absence is WHY the stale tool glyph survived over the bar. The content
    /// now owns the same area every other cursor surface of the app
    /// installs, and its handlers route through the one decision.
    func testTheEditorContentInstallsTheCursorDeliveryArea() throws {
        let editor = Self.makeEditor(image: solid(300, 200))
        defer { editor.window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let areas = editor.content.trackingAreas.filter { $0.owner === editor.content }
        XCTAssertEqual(areas.count, 1, "the content owns exactly one tracking area")
        let options = try XCTUnwrap(areas.first).options
        XCTAssertTrue(options.contains(.cursorUpdate), "the area carries the cursor updates")
        XCTAssertTrue(options.contains(.mouseEnteredAndExited), "the area carries the crossings")
        XCTAssertTrue(options.contains(.activeAlways), "the area answers while the app is inactive or the window is not key")
        XCTAssertTrue(options.contains(.inVisibleRect), "the area follows the visible content")
    }
}
