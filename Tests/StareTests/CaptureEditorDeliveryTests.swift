import AppKit
import XCTest

@testable import Stare
import StareCore

/// L7: an edited variant the user copies or saves out of the editor is a
/// capture like any other, so it reaches the history instead of vanishing with
/// the window. The seam is the editor content's `onDeliver`: one call site for
/// both paths, so neither can be forgotten.
@MainActor
final class CaptureEditorDeliveryTests: XCTestCase {
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

    private func makeContent() -> CaptureEditorContent {
        CaptureEditorContent(
            image: solid(40, 20),
            capture: .standard,
            redactionStyle: .blur
        )
    }

    func testAProducedVariantIsDeliveredWithItsComposedImage() throws {
        let content = makeContent()
        var delivered: [CGImage] = []
        content.onDeliver = { delivered.append($0) }

        content.deliverComposed()

        let handed = try XCTUnwrap(delivered.first, "the editor must hand its composed image over")
        XCTAssertEqual(delivered.count, 1, "one production, one delivery")
        XCTAssertEqual(handed.width, 40)
        XCTAssertEqual(handed.height, 20)
    }

    func testAnUnwiredEditorDeliversNothingAndDoesNotCrash() {
        // A detached editor (a harness, or the window before the overlay wires
        // it) has no hook: producing a variant must be inert, not fatal.
        let content = makeContent()
        XCTAssertNil(content.onDeliver)
        content.deliverComposed()
    }

    func testTheEditorControllerCarriesTheHookToEachWindowItOpens() {
        try? XCTSkipIf(NSScreen.screens.isEmpty, "no screen: a window cannot be ordered on screen")
        let controller = CaptureEditorController()
        var delivered = 0
        controller.onDeliver = { _ in delivered += 1 }
        controller.open(image: solid(20, 10))

        // The window the controller opened holds the same hook, so a copy or a
        // completed save inside it reports through the controller.
        let content = controller.windowsForTesting
            .compactMap { $0.contentView as? CaptureEditorContent }
            .first
        XCTAssertNotNil(content)
        content?.deliverComposed()
        XCTAssertEqual(delivered, 1)

        // The window goes away with the test: leaving it on screen is state the
        // rest of the suite inherits, and a later test that resolves "the window
        // under the pointer" pays for it.
        for window in controller.windowsForTesting {
            window.orderOut(nil)
            window.close()
        }
    }
}
