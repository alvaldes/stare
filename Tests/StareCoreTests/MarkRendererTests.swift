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
        scale: CGFloat = 1,
        phase: MarkRenderer.Phase = .committed
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
        MarkRenderer.draw(strokes: strokes, in: ctx, phase: phase)
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

    // MARK: - Spotlight (S15 slice B): the light look

    /// The dim weight the spotlight reaches far from the region (S15 slice
    /// B): one decision shared by the overlay preview and the compositor.
    private var spotlightDimAlpha: CGFloat { 0.55 }

    /// The feather: the distance from the region's boundary at which the dim
    /// reaches its deepest weight, expressed as a fraction of the region's
    /// radii. A constant in the region's own metric, so its real width grows
    /// and shrinks with the region — a large area gets a wide, ambient
    /// falloff, a small one stays crisp.
    private var spotlightFeather: CGFloat { 0.8 }

    /// Black at `alpha` over the white canvas.
    private func dimmedWhite(_ alpha: CGFloat) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        (1 - alpha, 1 - alpha, 1 - alpha, 1)
    }

    /// Builds a spotlight stroke through its persisted raw value, so these
    /// behaviour tests run (and fail) before the tool case exists instead of
    /// failing to compile.
    private func spotlightStroke(
        from: CGPoint,
        to: CGPoint,
        ink: Ink = .black,
        rotation: CGFloat = 0
    ) throws -> Stroke {
        let tool = try XCTUnwrap(Tool(rawValue: "spotlight"), "the spotlight tool must exist")
        var stroke = Stroke(tool: tool, ink: ink, points: [from, to])
        stroke.rotation = rotation
        return stroke
    }

    private static let spotlightRect = (from: CGPoint(x: 20, y: 15), to: CGPoint(x: 80, y: 65))

    /// A canvas large enough to probe the whole falloff: the shipped feather
    /// reaches 2.2 × the region's boundary radius, past the default canvas.
    private static let falloffCanvas = CGSize(width: 160, height: 120)

    /// A canvas for the far field: the region sits centred with room for
    /// more than a whole feather on every side, so corner probes rest past
    /// the ramp's end wherever the feather is tuned.
    private static let farFieldCanvas = CGSize(width: 180, height: 160)
    private static let farFieldRect = (from: CGPoint(x: 60, y: 50), to: CGPoint(x: 120, y: 110))

    /// The lit window is the dragged rectangle's inscribed ellipse: the
    /// centre stays bare and a probe just inside the ellipse's edge on the
    /// rectangle's own axis stays clear too. Inside the region the spotlight
    /// paints with alpha zero, so the content beneath keeps its own exactly
    /// brightness.
    func testSpotlightKeepsTheRegionInteriorClear() throws {
        let stroke = try spotlightStroke(from: Self.spotlightRect.from, to: Self.spotlightRect.to)
        for point in [CGPoint(x: 50, y: 40), CGPoint(x: 79, y: 40), CGPoint(x: 50, y: 16)] {
            let pixel = colour(of: [stroke], at: point, in: Self.canvasSize)
            assertApproximatelyEqual(pixel, (1, 1, 1, 1), tolerance: 0.02)
        }
    }

    /// Everything far from the region rests at the deepest dim weight — the
    /// dim floor away from the light, no matter how far out. The probes are
    /// the corners of a canvas that leaves the region room for more than a
    /// whole feather on every side, and the derivation is asserted, not
    /// trusted: a probe that is not a full feather past the boundary fails
    /// the distance guard before it can sample partway down the ramp.
    func testSpotlightDimsEverythingOutsideTheRegion() throws {
        let stroke = try spotlightStroke(from: Self.farFieldRect.from, to: Self.farFieldRect.to)
        let centre = CGPoint(
            x: (Self.farFieldRect.from.x + Self.farFieldRect.to.x) / 2,
            y: (Self.farFieldRect.from.y + Self.farFieldRect.to.y) / 2
        )
        let semiWidth = (Self.farFieldRect.to.x - Self.farFieldRect.from.x) / 2
        let semiHeight = (Self.farFieldRect.to.y - Self.farFieldRect.from.y) / 2
        let probes = [
            CGPoint(x: 4, y: 4),
            CGPoint(x: Self.farFieldCanvas.width - 4, y: Self.farFieldCanvas.height - 4),
            CGPoint(x: 4, y: Self.farFieldCanvas.height - 4),
        ]
        for point in probes {
            // Normalized distance in the lit ellipse's own metric: 1 at the
            // boundary, 1 + feather where the ramp ends and the floor begins.
            let dx = (point.x - centre.x) / semiWidth
            let dy = (point.y - centre.y) / semiHeight
            let distance = (dx * dx + dy * dy).squareRoot()
            XCTAssertGreaterThanOrEqual(
                distance, 1 + MarkRenderer.spotlightFeather,
                "probe \(point) must rest a full feather past the boundary, got \(distance)"
            )
        }
        for point in probes {
            let pixel = colour(of: [stroke], at: point, in: Self.farFieldCanvas)
            assertApproximatelyEqual(pixel, dimmedWhite(spotlightDimAlpha), tolerance: 0.03)
        }
    }

    /// The falloff eases out of the boundary gently: right outside the
    /// region's edge the dim is a small fraction of its weight, not a step.
    /// At 10% of the boundary radius past the edge the eased ramp has only
    /// covered smoothstep(0.125) ≈ 4% of the way.
    func testSpotlightFalloffIsGentleJustOutsideTheBoundary() throws {
        let stroke = try spotlightStroke(from: Self.spotlightRect.from, to: Self.spotlightRect.to)
        let pixel = colour(of: [stroke], at: CGPoint(x: 83, y: 40), in: Self.falloffCanvas)
        XCTAssertGreaterThan(pixel.red, 1 - spotlightDimAlpha * 0.15,
                             "just outside the boundary the dim must stay gentle, got \(pixel.red)")
    }

    /// The ramp reaches only half the weight halfway along its feather: the
    /// falloff is eased symmetrically (smoothstep), so a large region's
    /// boundary never reads as a line — dim starts high near the light.
    func testSpotlightRampHalfwayHoldsHalfTheWeight() throws {
        let stroke = try spotlightStroke(from: Self.spotlightRect.from, to: Self.spotlightRect.to)
        // Derived from the public feather, never hardcoded: along the x axis
        // from the region's centre, one boundary radius is the boundary
        // itself, so half a feather past that is exactly halfway along the
        // ramp wherever the feather is tuned. The falloff canvas leaves room
        // for the full feather, so the ramp is never clamped by its reach.
        let centreX = (Self.spotlightRect.from.x + Self.spotlightRect.to.x) / 2
        let semiWidth = (Self.spotlightRect.to.x - Self.spotlightRect.from.x) / 2
        let x = centreX + semiWidth * (1 + MarkRenderer.spotlightFeather / 2)
        let pixel = colour(of: [stroke], at: CGPoint(x: x, y: 40), in: Self.falloffCanvas)
        assertApproximatelyEqual(pixel, dimmedWhite(spotlightDimAlpha * 0.5), tolerance: 0.05)
    }

    /// The dim only ever climbs as the probe walks away from the boundary:
    /// monotone falloff, no local bright or dark bands between the light and
    /// the far field.
    func testSpotlightDimRisesMonotonicallyAwayFromTheBoundary() throws {
        let stroke = try spotlightStroke(from: Self.spotlightRect.from, to: Self.spotlightRect.to)
        let xs: [CGFloat] = [78, 80, 82, 85, 88, 91, 94, 97, 100, 104, 108]
        let dimmings = xs.map { 1 - colour(of: [stroke], at: CGPoint(x: $0, y: 40), in: Self.falloffCanvas).red }
        for (before, after) in zip(dimmings, dimmings.dropFirst()) {
            XCTAssertGreaterThan(after, before - 0.02,
                                 "the dim must not brighten walking away from the boundary")
        }
    }

    /// No discontinuity across the boundary: sampled densely on both sides
    /// of the light's edge, the dim never steps by more than a small
    /// fraction of its weight within half a point — the boundary is a
    /// gradient, never an edge.
    func testSpotlightFalloffIsContinuousAcrossTheBoundary() throws {
        let stroke = try spotlightStroke(from: Self.spotlightRect.from, to: Self.spotlightRect.to)
        var probes: [CGFloat] = []
        var x: CGFloat = 76
        while x <= 88 {
            probes.append(x)
            x += 0.5
        }
        let dimmings = probes.map { 1 - colour(of: [stroke], at: CGPoint(x: $0, y: 40), in: Self.falloffCanvas).red }
        for (before, after) in zip(dimmings, dimmings.dropFirst()) {
            XCTAssertLessThanOrEqual(abs(after - before), 0.15,
                                     "the dim must not step across the boundary")
        }
    }

    /// The feather is proportional to the region: two same-aspect regions at
    /// 1× and 2× size show the same dim at the same relative distance past
    /// their boundaries, because the ramp width is a fraction of the radii —
    /// a big region spreads its falloff, a small one keeps it tight.
    func testSpotlightFeatherGrowsWithTheRegion() throws {
        let canvas = CGSize(width: 200, height: 160)
        let small = try spotlightStroke(from: CGPoint(x: 70, y: 55), to: CGPoint(x: 130, y: 105))
        let large = try spotlightStroke(from: CGPoint(x: 40, y: 30), to: CGPoint(x: 160, y: 130))
        // d = 1.3 on each region's x axis: 30% past the boundary radius.
        let smallProbe = colour(of: [small], at: CGPoint(x: 139, y: 80), in: canvas).red
        let largeProbe = colour(of: [large], at: CGPoint(x: 178, y: 80), in: canvas).red
        XCTAssertEqual(smallProbe, largeProbe, accuracy: 0.04,
                       "the falloff must scale with the region, not hold a fixed pt width")
    }

    /// A spotlight has no ink of its own: the dim is identical whatever ink
    /// the mark carries.
    func testSpotlightIgnoresItsInk() throws {
        let red = try spotlightStroke(from: Self.spotlightRect.from, to: Self.spotlightRect.to, ink: .red)
        let blue = try spotlightStroke(from: Self.spotlightRect.from, to: Self.spotlightRect.to, ink: .blue)
        for point in [CGPoint(x: 5, y: 5), CGPoint(x: 50, y: 40)] {
            XCTAssertEqual(
                colour(of: [red], at: point, in: Self.canvasSize).red,
                colour(of: [blue], at: point, in: Self.canvasSize).red,
                accuracy: 0.001
            )
        }
    }

    /// The dim always covers the whole canvas, and the falloff far from the
    /// region rests at the deepest weight, even when the mark itself is
    /// rotated: only the lit window turns with the mark, never the shroud.
    func testRotatedSpotlightStillDimsTheWholeCanvas() throws {
        let stroke = try spotlightStroke(
            from: Self.spotlightRect.from,
            to: Self.spotlightRect.to,
            rotation: .pi / 2
        )
        assertApproximatelyEqual(
            colour(of: [stroke], at: CGPoint(x: 5, y: 5), in: Self.canvasSize),
            dimmedWhite(spotlightDimAlpha),
            tolerance: 0.03
        )
        assertApproximatelyEqual(
            colour(of: [stroke], at: CGPoint(x: 50, y: 40), in: Self.canvasSize),
            (1, 1, 1, 1),
            tolerance: 0.02
        )
    }

    // MARK: - T8b: the in-progress spotlight previews as the ellipse outline

    /// Renders `stroke` into a white RGBA bitmap of the given size and
    /// answers every byte, so two renderings can be compared whole.
    private func rasterBytes(
        of stroke: Stroke,
        phase: MarkRenderer.Phase = .committed,
        in size: CGSize,
        scale: CGFloat = 2
    ) -> [UInt8] {
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
        MarkRenderer.draw(stroke: stroke, in: ctx, phase: phase)
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
        return bytes
    }

    private static let previewRect = (from: CGPoint(x: 20, y: 15), to: CGPoint(x: 80, y: 65))

    /// The whole point of the split: while the mark is in hand the spotlight
    /// previews exactly what the ellipse tool draws for the same drag — byte
    /// for byte, because both go through the same geometry path with the
    /// same outline, thickness and ink.
    func testInProgressSpotlightDrawsExactlyWhatTheEllipseToolDraws() {
        let points = [Self.previewRect.from, Self.previewRect.to]
        let spotlight = Stroke(tool: .spotlight, ink: .red, points: points)
        let ellipse = Stroke(tool: .ellipse, ink: .red, points: points)
        XCTAssertEqual(
            rasterBytes(of: spotlight, phase: .inProgress, in: Self.canvasSize),
            rasterBytes(of: ellipse, in: Self.canvasSize),
            "the in-progress spotlight must render byte for byte as the ellipse preview"
        )
    }

    /// No dim anywhere while the stroke is in progress: far outside the
    /// dragged region the canvas stays exactly bare — the phase the human
    /// asked to remove was the mid-gesture dim. The outline itself still
    /// carries the ink at its edge, like any ellipse preview.
    func testInProgressSpotlightNeverDimsTheCanvas() {
        let stroke = Stroke(
            tool: .spotlight,
            ink: .red,
            points: [Self.previewRect.from, Self.previewRect.to]
        )
        // A corner well outside the region: pure canvas, no dim gradient.
        assertApproximatelyEqual(
            colour(of: [stroke], at: CGPoint(x: 5, y: 5), in: Self.canvasSize, scale: 1, phase: .inProgress),
            (1, 1, 1, 1),
            tolerance: 0.02
        )
        // The region interior: bare too — an outline preview, no wash, no dim.
        assertApproximatelyEqual(
            colour(of: [stroke], at: CGPoint(x: 50, y: 40), in: Self.canvasSize, scale: 1, phase: .inProgress),
            (1, 1, 1, 1),
            tolerance: 0.02
        )
        // Dead on the ellipse's edge on its own axis, the outline is the
        // ellipse tool's full-opacity red ink, its shipped thickness.
        let edge = colour(of: [stroke], at: CGPoint(x: 80, y: 40), in: Self.canvasSize, scale: 4, phase: .inProgress)
        assertApproximatelyEqual(edge, (1, 0.23, 0.19, 1), tolerance: 0.05)
    }

    /// The other side of the explicit input, pinned so the committed look
    /// cannot drift while the preview changes: a committed spotlight dims
    /// the canvas to its settled floor weight (the look the human picked).
    /// The floor probe is derived exactly as in the far-field test above —
    /// the corner of a canvas that leaves more than a whole feather on every
    /// side — so it rests past the ramp wherever the feather is tuned.
    func testCommittedSpotlightStillDimsTheCanvas() throws {
        let stroke = try spotlightStroke(from: Self.farFieldRect.from, to: Self.farFieldRect.to)
        assertApproximatelyEqual(
            colour(of: [stroke], at: CGPoint(x: 4, y: 4), in: Self.farFieldCanvas, scale: 1, phase: .committed),
            dimmedWhite(spotlightDimAlpha),
            tolerance: 0.03
        )
        assertApproximatelyEqual(
            colour(of: [stroke], at: CGPoint(x: 90, y: 80), in: Self.farFieldCanvas, scale: 1, phase: .committed),
            (1, 1, 1, 1),
            tolerance: 0.02
        )
    }
}
