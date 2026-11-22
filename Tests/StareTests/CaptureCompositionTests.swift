import XCTest
import CoreGraphics
@testable import Stare
import StareCore

/// S7/T11: what the user sees in the editor is what Save/Copy produce. The
/// verifier found the composed image placing marks at the view's scaled point
/// without subtracting the letterbox origin of the fitted display.
@MainActor
final class CaptureCompositionTests: XCTestCase {

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

    /// A mark drawn at view (100,100) on a letterboxed canvas must be saved at
    /// the pixel that view point maps to: the fitted display is (50,0,200,200)
    /// at 0.5 px/pt, so the pixel is (25,50).
    func testAMarkIsSavedWhereItWasDrawn() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let canvas = CaptureEditorCanvas(image: image)
        canvas.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        let mark = Stroke(tool: .pen, ink: .red, points: [CGPoint(x: 100, y: 100), CGPoint(x: 106, y: 100)])
        canvas.seedMarks([mark])

        let composed = try XCTUnwrap(canvas.composedImage())
        let box = try XCTUnwrap(inkBox(of: composed))
        XCTAssertEqual(box.minX, 25, accuracy: 1.5, "the composed mark must sit at the pixel its view point maps to (x)")
        XCTAssertEqual(box.minY, 50, accuracy: 1.5, "the composed mark must sit at the pixel its view point maps to (y)")
    }

    /// With a crop applied, a mark drawn afterwards is saved at the same
    /// absolute pixel of the original it was drawn over: the region only cuts
    /// the base, it must not shift the mark again. The region (25,25,50,50) is
    /// taken at 0.5 px/pt, so the refitted display is (50,0,200,200) at
    /// 0.25 px/pt and the mark drawn at view (100,100) maps to the original's
    /// pixel (37.5,50) — (12.5,25) inside the cropped base.
    func testAMarkDrawnAfterACropLandsOnTheAbsolutePixel() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let canvas = CaptureEditorCanvas(image: image)
        let state = EditorState()
        canvas.state = state
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas

        // Take the region (25,25,50,50) with a real crop gesture.
        state.selectCrop()
        canvas.mouseDown(with: try XCTUnwrap(event(.leftMouseDown, at: CGPoint(x: 100, y: 50), window: window)))
        canvas.mouseDragged(with: try XCTUnwrap(event(.leftMouseDragged, at: CGPoint(x: 200, y: 150), window: window)))
        canvas.mouseUp(with: try XCTUnwrap(event(.leftMouseUp, at: CGPoint(x: 200, y: 150), window: window)))
        // The staged flow (T4/S6): the drop only staged the rectangle; Return cuts.
        canvas.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)))
        let cropped = try XCTUnwrap(canvas.composedImage())
        XCTAssertEqual(cropped.width, 50, "the region (25,25,50,50) was applied")
        XCTAssertEqual(cropped.height, 50)

        state.tool = .pen
        state.ink = .red
        canvas.mouseDown(with: try XCTUnwrap(event(.leftMouseDown, at: CGPoint(x: 100, y: 100), window: window)))
        canvas.mouseDragged(with: try XCTUnwrap(event(.leftMouseDragged, at: CGPoint(x: 106, y: 100), window: window)))
        canvas.mouseUp(with: try XCTUnwrap(event(.leftMouseUp, at: CGPoint(x: 106, y: 100), window: window)))

        let composed = try XCTUnwrap(canvas.composedImage())
        XCTAssertEqual(composed.width, 50, "the crop, not the mark, sets the composed size")
        let box = try XCTUnwrap(inkBox(of: composed))
        XCTAssertEqual(box.minX, 12, accuracy: 1.5, "the mark lands at the absolute pixel (12.5,25) of the region (x)")
        XCTAssertEqual(box.minY, 25, accuracy: 1.5, "the mark lands at the absolute pixel (12.5,25) of the region (y)")
    }

    private func event(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1)
    }
}
