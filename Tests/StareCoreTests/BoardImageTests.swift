import AppKit
import CoreGraphics
import XCTest

import StareCore

/// T2b/S2: the whiteboard's image layer — the clamped paste placement
/// (centred in the visible area, reused from the editor's own clamp), the
/// pixel-accurate compositing the board capture and the blur start from,
/// and the history-pick routing decision.
final class BoardImageTests: XCTestCase {

    // MARK: Helpers

    private func solid(_ width: Int, _ height: Int, _ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A pixel in BOTTOM-LEFT coordinates — the bitmap context's own space,
    /// the one the compositor draws in — read through the rep's top-left
    /// accessor.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let representation = NSBitmapImageRep(cgImage: image)
        let colour = representation.colorAt(x: x, y: image.height - 1 - y)!.usingColorSpace(.deviceRGB)!
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue)
    }

    // MARK: Rule 1 — the clamped paste placement

    func testPasteLandsCentredInTheVisibleAreaAtTheImageOwnSize() {
        let layer = BoardImage.pasted(
            solid(100, 80, 1, 0, 0),
            inView: CGRect(x: 0, y: 0, width: 800, height: 600),
            transform: .identity
        )
        XCTAssertEqual(layer.rect, CGRect(x: 350, y: 260, width: 100, height: 80))
        XCTAssertEqual(layer.viewRect(for: .identity), layer.rect, "at identity the page rect is the view rect")
    }

    func testAnImageLargerThanTheVisibleAreaIsFittedWholeAndStaysCentred() {
        // The owner's second pass: a pasted screen capture must not cover the
        // board. It is fitted into a fraction of the visible area, whole.
        // B3: an image bigger than the visible area used to be capped per
        // axis — width to the canvas width, height to the canvas height —
        // which squashed its proportions AND filled the board edge to edge,
        // so a paste read as "not centred". It is fitted by ONE factor now,
        // so it keeps its own shape and sits visibly inside the area.
        let big = BoardImage.pasted(
            solid(900, 700, 0, 1, 0),
            inView: CGRect(x: 0, y: 0, width: 800, height: 600),
            transform: .identity
        )
        let area = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertEqual(big.rect.width / big.rect.height, 900.0 / 700.0, accuracy: 0.001, "the image keeps its shape")
        XCTAssertLessThanOrEqual(big.rect.width, area.width * BoardImage.insertedAreaFraction)
        XCTAssertLessThanOrEqual(big.rect.height, area.height * BoardImage.insertedAreaFraction)
        XCTAssertEqual(big.rect.height, area.height * BoardImage.insertedAreaFraction, accuracy: 0.001,
            "the tight axis fits the fraction of the page a paste may take — never the page edge to edge")
        XCTAssertEqual(big.rect.midX, area.midX, accuracy: 0.001, "centred across")
        XCTAssertEqual(big.rect.midY, area.midY, accuracy: 0.001, "centred down")
    }

    func testAPasteIntoAnEmptyVisibleAreaLandsAtThePageOriginAtItsOwnSize() {
        // A paste while the board has no laid-out canvas cannot centre on
        // nothing: centring on a zero rect put the layer at a negative
        // half-size, which is the one placement a user can never find.
        let layer = BoardImage.pasted(solid(100, 80, 1, 0, 0), inView: .zero, transform: .identity)
        XCTAssertEqual(layer.rect, CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    func testPasteStoresPageSpaceSoItPansAndZoomsWithThePage() {
        let transform = BoardTransform(offset: CGSize(width: 100, height: 50), zoom: 2)
        let layer = BoardImage.pasted(
            solid(100, 80, 0, 0, 1),
            inView: CGRect(x: 0, y: 0, width: 800, height: 600),
            transform: transform
        )
        XCTAssertEqual(
            layer.viewRect(for: transform),
            CGRect(x: 350, y: 260, width: 100, height: 80),
            "the layer lands where the view shows it, whatever the page's transform"
        )
        XCTAssertEqual(layer.rect, CGRect(x: 275, y: 180, width: 50, height: 40), "the rect is stored in page space")
        // The round trip is exact: the stored page rect maps back to the same
        // view rect, so the layer never drifts.
        XCTAssertEqual(transform.rect(fromPage: layer.rect), layer.viewRect(for: transform))
    }

    // MARK: Rule 2 — the capture includes the layer at exactly those pixels

    func testTheLayerCompositesOverTheBaseAtExactlyItsRect() throws {
        let base = solid(8, 8, 1, 1, 1)
        let layer = BoardImage(image: solid(2, 2, 1, 0, 0), rect: CGRect(x: 3, y: 3, width: 2, height: 2))
        let composed = try XCTUnwrap(layer.composited(over: base, transform: .identity, scale: 1))
        XCTAssertEqual(composed.width, 8, "the layer never enlarges the capture")
        XCTAssertEqual(composed.height, 8)
        // The compositor renders in sRGB, so a device-space test colour reads
        // back with a small cross-space tint on its zero channels; placement
        // is what the test pins, and the tint never approaches the base's 1.
        XCTAssertEqual(pixel(composed, x: 3, y: 3).red, 1, accuracy: 0.01, "the layer's pixel")
        XCTAssertLessThan(pixel(composed, x: 3, y: 3).green, 0.2, "the layer's pixel is the layer's colour")
        XCTAssertEqual(pixel(composed, x: 4, y: 4).red, 1, accuracy: 0.01, "the layer's other pixel")
        XCTAssertLessThan(pixel(composed, x: 4, y: 4).green, 0.2)
        XCTAssertEqual(pixel(composed, x: 2, y: 2).red, 1, accuracy: 0.01, "outside the rect the base shows through")
        XCTAssertEqual(pixel(composed, x: 2, y: 2).green, 1, accuracy: 0.01)
        XCTAssertEqual(pixel(composed, x: 5, y: 5).red, 1, accuracy: 0.01)
        XCTAssertEqual(pixel(composed, x: 5, y: 5).green, 1, accuracy: 0.01)
    }

    func testTheLayerCompositesThroughThePageTransformAtCaptureScale() throws {
        // The capture pipeline: the base is the display at `scale` pixels per
        // point, and a panned page's layer lands where the view shows it.
        let transform = BoardTransform(offset: CGSize(width: 2, height: 1), zoom: 1)
        let layer = BoardImage(image: solid(2, 2, 1, 0, 0), rect: CGRect(x: 4, y: 4, width: 2, height: 2))
        // view rect = (4−2, 4−1, 2, 2) = (2, 3, 2, 2); at scale 2 that is
        // pixels x ∈ [4, 8), y ∈ [6, 10) in bottom-left coordinates.
        let composed = try XCTUnwrap(
            layer.composited(over: solid(16, 16, 1, 1, 1), transform: transform, scale: 2)
        )
        XCTAssertEqual(pixel(composed, x: 4, y: 6).red, 1, accuracy: 0.01)
        XCTAssertLessThan(pixel(composed, x: 4, y: 6).green, 0.2, "the layer's pixel is the layer's colour")
        XCTAssertEqual(pixel(composed, x: 7, y: 9).red, 1, accuracy: 0.01)
        XCTAssertLessThan(pixel(composed, x: 7, y: 9).green, 0.2)
        XCTAssertEqual(pixel(composed, x: 3, y: 6).red, 1, accuracy: 0.01, "a pixel left of the view rect stays base")
        XCTAssertEqual(pixel(composed, x: 3, y: 6).green, 1, accuracy: 0.01)
        XCTAssertEqual(pixel(composed, x: 8, y: 6).red, 1, accuracy: 0.01, "a pixel right of the view rect stays base")
    }

    // MARK: Rule 3 — the routing decision

    func testAHistoryPickRoutesToTheBoardOnlyWhileItIsOpen() {
        XCTAssertEqual(HistoryPickDestination.destination(isBoardActive: true), .whiteboardPage)
        XCTAssertEqual(HistoryPickDestination.destination(isBoardActive: false), .clipboard)
    }

    func testAHistoryPickFallsBackToTheClipboardWhenTheBoardIsOpenWithoutAView() {
        XCTAssertEqual(
            HistoryPickDestination.destination(isBoardActive: true, hasBoardView: false),
            .clipboard,
            "a pick the board cannot take must not be silently dropped"
        )
        XCTAssertEqual(HistoryPickDestination.destination(isBoardActive: true, hasBoardView: true), .whiteboardPage)
        XCTAssertEqual(HistoryPickDestination.destination(isBoardActive: false, hasBoardView: false), .clipboard)
    }
}
