import CoreGraphics
import XCTest

import StareCore

/// S15 slice A: filled shapes, filled arrow heads and outline-only marks,
/// decided once in `MarkRenderer` so the overlay preview and the compositor
/// (which both call it) can never disagree.
final class MarkRendererTests: XCTestCase {
    // MARK: - Pixel harness

    /// Renders `strokes` into a white RGBA bitmap of the given size (bottom-left
    /// origin, like the compositor's own contexts) and answers the colour at
    /// `point`, in the same point space the strokes are laid out in. `scale`
    /// rasterizes that many pixels per point, so a sampled line's anti-aliasing
    /// never reaches a probe placed more than a point away from it.
    private func colour(
        of strokes: [Stroke],
        at point: CGPoint,
        in size: CGSize,
        scale: CGFloat = 1
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        MarkRenderer.draw(strokes: strokes, in: ctx)
        let image = ctx.makeImage()!
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let reader = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        reader.draw(image, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))
        let x = min(width - 1, max(0, Int(point.x * scale)))
        // Bottom-left origin: rows walk from the bottom of the point space up.
        let y = min(height - 1, max(0, Int((size.height - point.y) * scale)))
        let index = (y * width + x) * 4
        return (
            CGFloat(bytes[index]) / 255,
            CGFloat(bytes[index + 1]) / 255,
            CGFloat(bytes[index + 2]) / 255,
            CGFloat(bytes[index + 3]) / 255
        )
    }

    private static let canvasSize = CGSize(width: 100, height: 80)

    /// The fill weight the renderer uses (S15 slice A): a translucent ink
    /// wash under a full-opacity outline, so the content underneath stays
    /// readable — the same principle the highlighter draws with.
    private var fillOpacity: CGFloat { 0.3 }

    /// Ink `ink` washed over the white canvas at the fill opacity.
    private func fillOnWhite(_ ink: Ink) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let components = ink.cgColor(alpha: fillOpacity).components!
        let (r, g, b) = (components[0], components[1], components[2])
        return (
            r * fillOpacity + 1 * (1 - fillOpacity),
            g * fillOpacity + 1 * (1 - fillOpacity),
            b * fillOpacity + 1 * (1 - fillOpacity),
            1
        )
    }

    private func assertApproximatelyEqual(
        _ pixel: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat),
        _ expected: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat),
        tolerance: CGFloat = 0.02,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (actual, want) in zip([pixel.red, pixel.green, pixel.blue], [expected.red, expected.green, expected.blue]) {
            XCTAssertEqual(actual, want, accuracy: tolerance, file: file, line: line)
        }
    }

    // MARK: - Filled shapes (S15)

    func testFilledRectangleFillsInteriorAndKeepsOutline() {
        let stroke = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 60)],
            fill: true
        )
        // The interior centre carries the fill wash…
        assertApproximatelyEqual(
            colour(of: [stroke], at: CGPoint(x: 50, y: 40), in: Self.canvasSize),
            fillOnWhite(.red)
        )
        // …and the bottom edge still carries the full-opacity outline (sample
        // dead on the edge's centre line, so the pixel is fully covered).
        let edge = colour(of: [stroke], at: CGPoint(x: 50, y: 20), in: Self.canvasSize)
        assertApproximatelyEqual(edge, (1, 0.23, 0.19, 1), tolerance: 0.05)
    }

    func testFilledEllipseFillsInterior() {
        let stroke = Stroke(
            tool: .ellipse,
            ink: .blue,
            points: [CGPoint(x: 20, y: 15), CGPoint(x: 80, y: 65)],
            fill: true
        )
        let expected = fillOnWhite(.blue)
        assertApproximatelyEqual(
            colour(of: [stroke], at: CGPoint(x: 50, y: 40), in: Self.canvasSize),
            expected
        )
    }

    func testFilledShapeNeverSplitsOutlineFromPreviewOrCaptureSources() {
        // One decision, two tools: the fill is a property of the mark, so a
        // scaled (transformed) copy keeps it — the editor's exact round trip.
        let rectangle = Stroke(tool: .rectangle, ink: .red, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 60)], fill: true)
        let scaled = MarkTransform.translated(MarkTransform.scaled(rectangle, from: rectangle.anchor, by: 1.5), by: CGPoint(x: -10, y: -10))
        XCTAssertTrue(scaled.isFilled)
        XCTAssertEqual(scaled.arrowHead, rectangle.arrowHead)
        XCTAssertFalse(Stroke(tool: .rectangle, ink: .red, points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]).isFilled)
    }

    // MARK: - Outline-only preserved (S15 defaults)

    func testOutlineRectangleAndEllipseLeaveTheirInteriorsUntouched() {
        for tool in [Tool.rectangle, .ellipse] {
            let stroke = Stroke(tool: tool, ink: .red, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 60)])
            let pixel = colour(of: [stroke], at: CGPoint(x: 50, y: 40), in: Self.canvasSize)
            XCTAssertEqual(pixel.red, 1, accuracy: 0.02, "\(tool.rawValue) interior must stay bare")
            XCTAssertEqual(pixel.green, 1, accuracy: 0.02, "\(tool.rawValue) interior must stay bare")
            XCTAssertEqual(pixel.blue, 1, accuracy: 0.02, "\(tool.rawValue) interior must stay bare")
        }
    }

    // MARK: - Arrow heads (S15)

    /// A point inside the head triangle that no stroked line covers. The
    /// triangle's free band is narrow (the head is 16 pt with line width 3),
    /// so the probe sits a point past the shaft stroke's own half width and
    /// one past the edge's perpendicular reach, and is rasterized at `scale`
    /// (4 px per point) so anti-aliasing never reaches it.
    private func interiorHeadPoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        let alongX = dx / length, alongY = dy / length
        let unitX = -alongY, unitY = alongX // perpendicular to the shaft
        let lineWidth = Stroke(tool: .arrow, ink: .red, points: [start, end]).lineWidth
        let barbLength = min(PathBuilder.arrowHeadLength, length * 0.6)
        let station = barbLength * 0.8 // distance back from the tip
        let halfWidth = station * tan(PathBuilder.arrowHeadHalfAngle)
        let offset = lineWidth / 2 + 1.0
        // The edge's perpendicular reach must clear the stroke, too.
        let edgeReach = (halfWidth - offset) * cos(PathBuilder.arrowHeadHalfAngle)
        XCTAssertTrue(edgeReach > lineWidth / 2 + 0.5 && offset > lineWidth / 2 + 0.5,
                      "probe must clear every stroke; offset \(offset), edge reach \(edgeReach)")
        return CGPoint(
            x: end.x - alongX * station + unitX * offset,
            y: end.y - alongY * station + unitY * offset
        )
    }

    func testFilledArrowHeadInksTheTriangleInterior() {
        let start = CGPoint(x: 20, y: 20), end = CGPoint(x: 75, y: 45)
        let stroke = Stroke(tool: .arrow, ink: .green, points: [start, end], arrowHead: .filled)
        let pixel = colour(of: [stroke], at: interiorHeadPoint(from: start, to: end), in: Self.canvasSize, scale: 4)
        assertApproximatelyEqual(pixel, (0.2, 0.78, 0.35, 1), tolerance: 0.05)
    }

    func testOpenArrowHeadLeavesTheTriangleInteriorBare() {
        let start = CGPoint(x: 20, y: 20), end = CGPoint(x: 75, y: 45)
        let stroke = Stroke(tool: .arrow, ink: .green, points: [start, end])
        let pixel = colour(of: [stroke], at: interiorHeadPoint(from: start, to: end), in: Self.canvasSize, scale: 4)
        assertApproximatelyEqual(pixel, (1, 1, 1, 1), tolerance: 0.03)
    }

    func testFilledArrowHeadCyclesThroughArrowHeadStyleNext() {
        XCTAssertEqual(ArrowHeadStyle.open.next, .filled)
        XCTAssertEqual(ArrowHeadStyle.filled.next, .open)
        XCTAssertEqual(ArrowHeadStyle(rawValue: "open"), .open)
        XCTAssertEqual(ArrowHeadStyle(rawValue: "filled"), .filled)
    }
}
