import CoreGraphics
import XCTest

@testable import StareCore

/// Slice 1 of T7 (S5, S7): the pointer highlight is drawn by one pure
/// renderer in StareCore, so the overlay and the Settings preview draw
/// identical pixels because they call the same code. Every assertion here
/// reads rendered pixels, except the two `extent` ones.
final class PointerHighlightRendererTests: XCTestCase {
    /// The 72 pt / 0.26 band / ink geometry every pixel assertion below was
    /// calibrated against. Explicit on purpose: v0.4/S9 moved the factory
    /// default to the owner's own look (rhombus, 100 pt, 0.1 band, dashed,
    /// fixed purple), and these tests pin the renderer, not that default.
    private func verifiedStyle(
        _ preset: PointerStylePreset = .squircle,
        bandWidth: Double = 0.26,
        glowIntensity: Double = 1,
        opacity: Double = 1
    ) -> PointerStyle {
        PointerStyle(
            preset: preset,
            size: 72,
            colorSource: .ink,
            bandWidth: bandWidth,
            glowIntensity: glowIntensity,
            opacity: opacity
        )
    }

    // MARK: - Helpers

    private let canvasSize = 400
    private let center = CGPoint(x: 200, y: 200)

    /// Alpha channel of the rendered canvas, addressable in context
    /// coordinates (origin bottom-left, like the unflipped bitmap).
    private struct Canvas {
        let data: [UInt8]
        let width: Int
        let height: Int

        func alpha(atX x: CGFloat, atY y: CGFloat) -> Double {
            // Bitmap data stores the top row first, so a context (bottom-left
            // origin) coordinate maps to row `height - 1 - y`.
            let px = max(0, min(width - 1, Int(x)))
            let py = max(0, min(height - 1, height - 1 - Int(y)))
            return Double(data[(py * width + px) * 4 + 3]) / 255
        }

        var center: CGPoint { CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2) }
    }

    /// Renders the appearance for `style` into a transparent bitmap at 1 pt
    /// per pixel, centred on the canvas.
    private func render(_ style: PointerStyle, pulseScale: CGFloat = 1) -> Canvas {
        render(style.appearance(ink: .red), pulseScale: pulseScale, rotation: 0)
    }

    private func render(_ appearance: PointerAppearance, pulseScale: CGFloat, rotation: CGFloat = 0) -> Canvas {
        let width = canvasSize
        let height = canvasSize
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        PointerHighlightRenderer.draw(
            in: context,
            center: center,
            appearance: appearance,
            pulseScale: pulseScale,
            rotation: rotation
        )
        return Canvas(data: data, width: width, height: height)
    }

    /// Every pixel of the canvas outside `extent` must stay clear.
    private func assertNothingOutsideExtent(_ canvas: Canvas, extent: CGRect, tolerance: Double) {
        var paintedOutside = 0
        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                let relative = CGPoint(
                    x: CGFloat(x) + 0.5 - canvas.center.x,
                    y: CGFloat(y) + 0.5 - canvas.center.y
                )
                guard !extent.contains(relative) else { continue }
                if canvas.alpha(atX: CGFloat(x), atY: CGFloat(y)) > tolerance {
                    paintedOutside += 1
                }
            }
        }
        XCTAssertEqual(paintedOutside, 0, "found \(paintedOutside) painted pixels outside the extent")
    }

    // MARK: - Extent is today's invalidation rect

    // Standard shape: radius 36, glow reach 36 * 1.9 = 68.4, margin +12,
    // exactly what OverlayView.pointerRect computes today.
    func testExtentForStandardStylePinsTodayRectAtScaleOne() {
        let appearance = verifiedStyle().appearance(ink: .red)
        let extent = PointerHighlightRenderer.extent(for: appearance, pulseScale: 1)
        XCTAssertEqual(extent.minX, -80.4, accuracy: 0.001)
        XCTAssertEqual(extent.minY, -80.4, accuracy: 0.001)
        XCTAssertEqual(extent.width, 160.8, accuracy: 0.001)
        XCTAssertEqual(extent.height, 160.8, accuracy: 0.001)
    }

    func testExtentScalesWithPulseScale() {
        let appearance = verifiedStyle().appearance(ink: .red)
        let extent = PointerHighlightRenderer.extent(for: appearance, pulseScale: 1.5)
        // 36 * 1.5 * 1.9 + 12 = 114.6.
        XCTAssertEqual(extent.minX, -114.6, accuracy: 0.001)
        XCTAssertEqual(extent.width, 229.2, accuracy: 0.001)
    }

    // MARK: - Ring

    func testRingLeavesCentreClearPaintsBandAndStaysInsideExtent() {
        let canvas = render(PointerStyle(preset: .ring, size: 72, colorSource: .ink, bandWidth: 0.26, glowIntensity: 1))
        // standard sizes: radius 36, band 9.36, band spans 26.64...36.
        let extent = CGRect(x: -80.4, y: -80.4, width: 160.8, height: 160.8)
        assertNothingOutsideExtent(canvas, extent: extent, tolerance: 0.05)
        XCTAssertLessThan(canvas.alpha(atX: 200, atY: 200), 0.03, "the hole is punched clear")
        XCTAssertGreaterThan(canvas.alpha(atX: 200, atY: 231), 0.4, "the band ring is painted")
        XCTAssertGreaterThan(canvas.alpha(atX: 231, atY: 200), 0.4, "the band ring is painted")
    }

    // MARK: - Squircle

    func testSquircleLeavesCornersOfTheBoundingSquareClear() {
        let canvas = render(PointerStyle(preset: .squircle, size: 72, colorSource: .ink, bandWidth: 0.26, glowIntensity: 0))
        // Corner of the bounding square, well outside the rounded rect whose
        // corner radius is 0.62 * 36 = 22.3: (33.1, 33.1) sits in the corner
        // square but 27.4 away from its corner circle centre.
        for (dx, dy) in [(33, 33), (-33, 33), (33, -33), (-33, -33)] {
            XCTAssertLessThan(
                canvas.alpha(atX: CGFloat(200 + dx), atY: CGFloat(200 + dy)),
                0.03,
                "a rounded rect leaves its corners clear at (\(dx), \(dy))"
            )
        }
        // The straight edges still carry a painted band.
        XCTAssertGreaterThan(canvas.alpha(atX: 200, atY: 231), 0.4)
        XCTAssertGreaterThan(canvas.alpha(atX: 231, atY: 200), 0.4)
    }

    // MARK: - Dot

    func testDotPaintsAFilledDiscWithNoHollowHole() {
        let canvas = render(PointerStyle(preset: .dot, size: 72, colorSource: .ink, glowIntensity: 0))
        XCTAssertGreaterThan(canvas.alpha(atX: 200, atY: 200), 0.4, "the centre is filled")
        XCTAssertGreaterThan(canvas.alpha(atX: 190, atY: 210), 0.4, "no hollow hole")
        XCTAssertGreaterThan(canvas.alpha(atX: 210, atY: 190), 0.4, "no hollow hole")
        XCTAssertLessThan(canvas.alpha(atX: 245, atY: 200), 0.03, "nothing beyond the disc")
    }

    // MARK: - Spotlight

    func testSpotlightFadesMonotonicallyWithNoHardEdgeAtTheRadius() {
        let canvas = render(PointerStyle(preset: .spotlight, size: 72, colorSource: .ink, glowIntensity: 1))
        XCTAssertGreaterThan(canvas.alpha(atX: 200, atY: 200), 0.1, "the centre has glow")
        XCTAssertLessThan(canvas.alpha(atX: 200, atY: 200), 0.35, "the centre stays translucent")

        // Alpha falls monotonically with distance.
        var previous = canvas.alpha(atX: 200, atY: 200)
        for multiplier in [0.25, 0.5, 0.75, 1.0, 1.25, 1.5] {
            let value = canvas.alpha(atX: 200, atY: 200 + 36 * multiplier)
            XCTAssertLessThan(value, previous, "alpha must decrease at \(multiplier)r")
            previous = value
        }

        // No hard edge at the radius (36): just inside and just outside the
        // falloff is continuous because the gradient has no stop there.
        let inside = canvas.alpha(atX: 200, atY: 200 + 35.5)
        let outside = canvas.alpha(atX: 200, atY: 200 + 36.5)
        XCTAssertLessThan(abs(inside - outside), 0.02, "the radius carries no hard edge")
    }

    // MARK: - Rhombus (T14/S9)

    /// The rhombus is the squircle's rounded square rotated 45°: its rounded
    /// vertices point along the axes past the outer circle (≈1.16 × radius)
    /// while its edges touch the circle along the diagonals.
    func testRhombusPaintsAlongItsDiagonalsAndClearsTheSquareCorners() {
        let canvas = render(PointerStyle(preset: .rhombus, size: 72, colorSource: .ink, bandWidth: 0.26, glowIntensity: 0))
        // The band sits along the shape's own diagonals: on the axes between
        // the hole (≈30.8 from the centre) and the vertex (≈41.7).
        XCTAssertGreaterThan(canvas.alpha(atX: 200, atY: 236), 0.4, "the band runs along the vertical diagonal")
        XCTAssertGreaterThan(canvas.alpha(atX: 236, atY: 200), 0.4, "the band runs along the horizontal diagonal")
        XCTAssertGreaterThan(canvas.alpha(atX: 200, atY: 164), 0.4, "the band runs toward the bottom vertex")
        XCTAssertLessThan(canvas.alpha(atX: 200, atY: 200), 0.03, "the hole is punched clear")
        // The shape reaches past the circle along the axes but not at the
        // bounding square's corners: the diagonals only touch the circle (36).
        for (dx, dy) in [(33, 33), (-33, 33), (33, -33), (-33, -33)] {
            XCTAssertLessThan(
                canvas.alpha(atX: CGFloat(200 + dx), atY: CGFloat(200 + dy)),
                0.03,
                "the corner of the bounding square stays clear at (\(dx), \(dy))"
            )
        }
        // Past the vertex along an axis there is nothing either.
        XCTAssertLessThan(canvas.alpha(atX: 200, atY: 246), 0.03, "nothing beyond the vertex")
    }

    /// The rhombus pokes past the circle, so the extent must still cover it —
    /// without growing beyond the formula the other presets share.
    func testRhombusStaysInsideTheSharedExtentWithoutInflatingIt() {
        var style = verifiedStyle()
        style.preset = .rhombus
        let appearance = style.appearance(ink: .red)
        let extent = PointerHighlightRenderer.extent(for: appearance, pulseScale: 1)
        XCTAssertEqual(extent.minX, -80.4, accuracy: 0.001)
        XCTAssertEqual(extent.width, 160.8, accuracy: 0.001)
        let canvas = render(appearance, pulseScale: 1)
        assertNothingOutsideExtent(canvas, extent: extent, tolerance: 0.05)
    }

    // MARK: - The corrected border model (T14 rework)

    /// Samples along the ray at `degrees` for the three sample families of
    /// the corrected border model — the band's middle, the outer boundary
    /// and a point just inside the inner boundary (on the band's side of it)
    /// — (radius 36, band 9.36: the fill spans 26.64...36 and the outer
    /// line sits centred on 36).
    private func borderSamples(_ canvas: Canvas, degrees: Double) -> (fill: Double, inner: Double, outer: Double) {
        func value(_ radius: Double) -> Double {
            let radians = degrees * .pi / 180
            return canvas.alpha(atX: CGFloat(200 + radius * cos(radians)), atY: CGFloat(200 + radius * sin(radians)))
        }
        let fill = max(value(31), value(32))
        let inner = max(value(27), value(28))
        let outer = max(value(35), value(36), value(37))
        return (fill, inner, outer)
    }

    /// The corrected model: the band is a translucent filled ring whose inner
    /// edge is just the fill's own edge, and exactly one bright line runs on
    /// the outer edge. A sample in the middle of the band is the band fill, a
    /// sample just inside the inner boundary is that same fill — the
    /// regression that proves the old inner line is gone — and the outer
    /// boundary is bright.
    func testSolidBorderFillsTheBandWithOneContinuousLineOnTheOuterEdge() {
        var style = PointerStyle(preset: .ring, size: 72, colorSource: .ink, bandWidth: 0.26, glowIntensity: 0)
        style.borderStyle = .solid
        let canvas = render(style)
        for degrees in stride(from: 0.0, to: 360, by: 15) {
            let sample = borderSamples(canvas, degrees: degrees)
            XCTAssertGreaterThan(sample.fill, 0.45, "the band is filled at \(degrees)°")
            XCTAssertLessThan(sample.fill, 0.65, "the middle of the band is the fill, not a line, at \(degrees)°")
            XCTAssertGreaterThan(sample.outer, 0.85, "the outer boundary carries a line at \(degrees)°")
            XCTAssertLessThan(sample.inner, 0.75, "no bright line on the inner boundary at \(degrees)°")
            XCTAssertLessThan(
                abs(sample.inner - sample.fill), 0.15,
                "just inside the inner boundary the pixels are the fill itself at \(degrees)°"
            )
        }
        // Inside the hole and past the outer line nothing is painted.
        XCTAssertLessThan(canvas.alpha(atX: 200, atY: 220), 0.03, "the hole stays clear")
        XCTAssertLessThan(canvas.alpha(atX: 245, atY: 200), 0.03, "nothing beyond the outer line")
    }

    /// The dashed style is the solid one with only the outer boundary line
    /// turned into dashes: the band stays filled under every gap (no hole
    /// shows through), the inner edge keeps being the fill's own edge with no
    /// bright line, and the outer samples alternate bright and not.
    func testDashedBorderKeepsTheBandFilledUnderGapsWithNoInnerLine() {
        var style = PointerStyle(preset: .ring, size: 72, colorSource: .ink, bandWidth: 0.26, glowIntensity: 0)
        style.borderStyle = .dashed
        let canvas = render(style)
        var dashAngles = 0
        var gapAngles = 0
        for degrees in stride(from: 0.0, to: 360, by: 3) {
            let sample = borderSamples(canvas, degrees: degrees)
            XCTAssertGreaterThan(sample.fill, 0.45, "the band fill holds under the outer line at \(degrees)°")
            XCTAssertLessThan(sample.inner, 0.75, "no bright line on the inner boundary at \(degrees)°")
            if sample.outer > 0.8 {
                dashAngles += 1
            } else if sample.outer < 0.7 {
                gapAngles += 1
            }
        }
        XCTAssertGreaterThan(dashAngles, 0, "the outer line carries dashes")
        XCTAssertGreaterThan(gapAngles, 0, "the outer line carries gaps")
    }

    // MARK: - Opacity (T14/S9)

    /// Opacity multiplies every drawn alpha: 1 is today's look, 0.5 roughly
    /// halves the band and visibly dims the glow.
    func testOpacityHalvesTheBandAlphaAndDimsTheGlow() {
        let full = render(PointerStyle(preset: .ring, size: 72, colorSource: .ink, bandWidth: 0.26, glowIntensity: 1, opacity: 1))
        let half = render(PointerStyle(preset: .ring, size: 72, colorSource: .ink, bandWidth: 0.26, glowIntensity: 1, opacity: 0.5))
        let bandFull = full.alpha(atX: 200, atY: 231)
        let bandHalf = half.alpha(atX: 200, atY: 231)
        XCTAssertGreaterThan(bandFull, 0.4, "the band is painted at full opacity")
        XCTAssertGreaterThan(bandHalf, 0.15, "half opacity still paints the band")
        XCTAssertEqual(Double(bandHalf / bandFull), 0.5, accuracy: 0.15)
        let glowFull = full.alpha(atX: 200, atY: 200 + 47)
        let glowHalf = half.alpha(atX: 200, atY: 200 + 47)
        XCTAssertGreaterThan(glowFull, 0.05, "the strong glow paints the halo")
        XCTAssertGreaterThan(glowHalf, 0.005, "half opacity still dims, not kills, the halo")
        XCTAssertLessThan(glowHalf, glowFull, "the halo is dimmer at half opacity")
    }

    // MARK: - Click rotation (T14/S9)

    /// Even the rhombus — the shape that pokes past the circle — stays inside
    /// the shared extent while the pulse rotates it.
    func testRotatedRhombusStaysInsideTheSameExtent() {
        var style = verifiedStyle()
        style.preset = .rhombus
        let appearance = style.appearance(ink: .red)
        let turned = render(appearance, pulseScale: 1, rotation: 0.42)
        let extent = PointerHighlightRenderer.extent(for: appearance, pulseScale: 1)
        assertNothingOutsideExtent(turned, extent: extent, tolerance: 0.05)
    }

    /// The click pulse envelope rotates the shape about its centre without
    /// changing the extent: the same invalidation rect stays valid while the
    /// shape turns. The rhombus carries the proof because it is the last
    /// asymmetric preset — its rounded vertices point along the axes at rest
    /// and a 45° turn carries the paint over to the diagonals.
    func testRotationMovesTheShapeButKeepsTheExtent() {
        let appearance = PointerStyle(preset: .rhombus, size: 72, colorSource: .ink, glowIntensity: 0).appearance(ink: .red)
        let atRest = render(appearance, pulseScale: 1, rotation: 0)
        let halfTurn = render(appearance, pulseScale: 1, rotation: .pi / 4)
        XCTAssertNotEqual(atRest.data, halfTurn.data, "rotation moves pixels")
        // At rest the vertices point along the axes, so the band runs down
        // the vertical axis; a 45° turn carries the vertex away toward the
        // diagonal and the axis sample sits on a tangent edge instead.
        XCTAssertGreaterThan(atRest.alpha(atX: 200, atY: 240), 0.4, "the vertex sits on the axis at rest")
        XCTAssertLessThan(halfTurn.alpha(atX: 200, atY: 240), 0.05, "a 45° turn carries the vertex away")
        XCTAssertGreaterThan(halfTurn.alpha(atX: 228, atY: 228), 0.4, "the vertex arrived on the diagonal")
        // The extent is unchanged: rotation is about the centre of the same
        // reach, so the invalidation rect stays the same rectangle.
        let extent = PointerHighlightRenderer.extent(for: appearance, pulseScale: 1)
        XCTAssertEqual(extent.minX, -80.4, accuracy: 0.001)
        XCTAssertEqual(extent.width, 160.8, accuracy: 0.001)
        assertNothingOutsideExtent(halfTurn, extent: extent, tolerance: 0.05)
    }

    /// The dash rhythm is derived from the border line width, not the band:
    /// each dash is three line widths long and each gap two, so the dashes
    /// read as segments on the thin line instead of dots or blobs. With
    /// today's 2 pt border line that is exactly a 6 pt dash and a 4 pt gap.
    func testDashRhythmIsDerivedFromTheBorderLineWidth() {
        XCTAssertEqual(PointerHighlightRenderer.dashPattern(lineWidth: 2), [6, 4])
        XCTAssertEqual(PointerHighlightRenderer.dashPattern(lineWidth: 3), [9, 6])
    }

    // MARK: - Glow

    func testGlowOffLeavesNothingOutsideTheBand() {
        let canvas = render(PointerStyle(preset: .squircle, size: 72, colorSource: .ink, glowIntensity: 0))
        // Outside the band plus its edges (radius 37) nothing is painted at all.
        XCTAssertLessThan(canvas.alpha(atX: 200, atY: 200 + 43), 0.03, "glow off paints no halo")
        XCTAssertLessThan(canvas.alpha(atX: 200, atY: 200 - 43), 0.03)
        XCTAssertLessThan(canvas.alpha(atX: 200 + 43, atY: 200), 0.03)
    }

    func testWeakerGlowIsDimmerThanStrongerGlow() {
        let weak = render(PointerStyle(preset: .squircle, size: 72, colorSource: .ink, glowIntensity: 0.4))
        let strong = render(PointerStyle(preset: .squircle, size: 72, colorSource: .ink, glowIntensity: 1))
        // Sample in the halo at 1.3r, between the band and the glow reach.
        let weakSample = weak.alpha(atX: 200, atY: 200 + 47)
        let strongSample = strong.alpha(atX: 200, atY: 200 + 47)
        XCTAssertGreaterThan(strongSample, 0.05, "the strong glow paints the halo")
        XCTAssertGreaterThan(weakSample, 0.01, "the weak glow still paints the halo")
        XCTAssertLessThan(weakSample, strongSample, "a weaker glow paints a dimmer halo")
    }

    // MARK: - Fixed preview canvas (T14 second rework)

    /// The Settings preview's tile is a fixed canvas that must never grow with
    /// the style's size. These tests exercise the seam that tells the view how
    /// to draw: 168 pt, matching `PointerPreviewView.tileSide`.
    private let previewCanvasSide = 168.0

    /// Scale output is at most 1, and exactly 1 when the highlight already
    /// fits the canvas.
    func testFitScaleNeverExceedsOneAndIsOneWhenTheHighlightFits() {
        let side = PointerHighlightRenderer
            .extent(for: verifiedStyle().appearance(ink: .red), pulseScale: 1).width
        XCTAssertGreaterThan(side, 0)
        XCTAssertLessThanOrEqual(PointerHighlightRenderer.fitScale(extentSide: side, canvasSide: previewCanvasSide), 1)
        XCTAssertEqual(
            PointerHighlightRenderer.fitScale(extentSide: side, canvasSide: previewCanvasSide),
            1, accuracy: 0.0001,
            "the 72 pt default fits the preview canvas without scaling"
        )
        XCTAssertEqual(PointerHighlightRenderer.fitScale(extentSide: 100, canvasSide: 168), 1)
    }

    /// A 240 pt highlight must scale below 1 while the 72 pt default stays 1,
    /// and the scaled appearance's own extent must then cover exactly the
    /// canvas the fit scale was computed against.
    func test240PtScalesBelowOneWhile72PtStaysAtOne() {
        var big = verifiedStyle()
        big.size = 240
        let bigSide = PointerHighlightRenderer
            .extent(for: big.appearance(ink: .red), pulseScale: 1).width
        let bigScale = PointerHighlightRenderer
            .fitScale(extentSide: bigSide, canvasSide: previewCanvasSide)
        XCTAssertLessThan(bigScale, 1, "240 pt is too large for the fixed canvas")

        let scaledAppearance = big.appearance(ink: .red).scaled(by: bigScale)
        let scaledSide = PointerHighlightRenderer
            .extent(for: scaledAppearance, pulseScale: 1).width
        XCTAssertEqual(scaledSide, previewCanvasSide, accuracy: 0.0001, "the scaled highlight fits the canvas exactly")
    }

    /// Scaling an appearance is a uniform shrink: distances multiply, ratios
    /// and relative stops stay put, so the drawing is identical pixels at a
    /// smaller size.
    func testScaledAppearanceShrinksDistancesAndKeepsRatios() {
        let appearance = verifiedStyle().appearance(ink: .red)
        let scaled = appearance.scaled(by: 0.35)
        XCTAssertEqual(scaled.radius, appearance.radius * 0.35, accuracy: 0.0001)
        XCTAssertEqual(scaled.edgeWidth, appearance.edgeWidth * 0.35, accuracy: 0.0001)
        XCTAssertEqual(scaled.glowMargin, appearance.glowMargin * 0.35, accuracy: 0.0001)
        XCTAssertEqual(scaled.bandWidth, appearance.bandWidth)
        XCTAssertEqual(scaled.bandFillAlpha, appearance.bandFillAlpha, accuracy: 0.0001)
        XCTAssertEqual(scaled.edgeAlpha, appearance.edgeAlpha, accuracy: 0.0001)
        XCTAssertEqual(scaled.glowExtent, appearance.glowExtent)
        XCTAssertEqual(scaled.glowStops.count, appearance.glowStops.count)
        XCTAssertEqual(scaled.geometry, appearance.geometry)
        XCTAssertEqual(scaled.cornerRadiusFactor, appearance.cornerRadiusFactor)
        // The extent — the invalidation surface — scales by the same factor:
        let originalSide = PointerHighlightRenderer.extent(for: appearance, pulseScale: 1).width
        let scaledSide = PointerHighlightRenderer.extent(for: scaled, pulseScale: 1).width
        XCTAssertEqual(scaledSide, originalSide * 0.35, accuracy: 0.0001)
    }

    /// The caption never lies about what it shows: a scaled-down highlight
    /// names the percentage and the real size, and one drawn full size says
    /// exactly that.
    func testPreviewCaptionReportsTheScaleAndTheRealSize() {
        XCTAssertEqual(
            PointerHighlightRenderer.previewFitCaption(scale: 0.35, size: 240),
            "Shown at 35 % · 240 pt"
        )
        XCTAssertEqual(
            PointerHighlightRenderer.previewFitCaption(scale: 1, size: 72),
            "Shown at real size · 72 pt"
        )
        // The percentage the caption carries comes from the same scale the
        // view draws with:
        var big = verifiedStyle()
        big.size = 240
        let bigScale = PointerHighlightRenderer.fitScale(
            extentSide: PointerHighlightRenderer
                .extent(for: big.appearance(ink: .red), pulseScale: 1).width,
            canvasSide: previewCanvasSide
        )
        XCTAssertEqual(
            PointerHighlightRenderer.previewFitCaption(scale: bigScale, size: big.size),
            "Shown at 35 % · 240 pt"
        )
    }
}
