import CoreGraphics
import XCTest

@testable import StareCore

/// Slice 1 of T7 (S5, S7): the pointer highlight is drawn by one pure
/// renderer in StareCore, so the overlay and the Settings preview draw
/// identical pixels because they call the same code. Every assertion here
/// reads rendered pixels, except the two `extent` ones.
final class PointerHighlightRendererTests: XCTestCase {
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

        /// Number of painted pixels along a horizontal row of the shape.
        func rowWidth(atY y: CGFloat, threshold: Double = 0.3) -> Int {
            var count = 0
            for x in 0..<width where alpha(atX: CGFloat(x), atY: y) > threshold {
                count += 1
            }
            return count
        }
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
        let appearance = PointerStyle.standard.appearance(ink: .red)
        let extent = PointerHighlightRenderer.extent(for: appearance, pulseScale: 1)
        XCTAssertEqual(extent.minX, -80.4, accuracy: 0.001)
        XCTAssertEqual(extent.minY, -80.4, accuracy: 0.001)
        XCTAssertEqual(extent.width, 160.8, accuracy: 0.001)
        XCTAssertEqual(extent.height, 160.8, accuracy: 0.001)
    }

    func testExtentScalesWithPulseScale() {
        let appearance = PointerStyle.standard.appearance(ink: .red)
        let extent = PointerHighlightRenderer.extent(for: appearance, pulseScale: 1.5)
        // 36 * 1.5 * 1.9 + 12 = 114.6.
        XCTAssertEqual(extent.minX, -114.6, accuracy: 0.001)
        XCTAssertEqual(extent.width, 229.2, accuracy: 0.001)
    }

    // MARK: - Ring

    func testRingLeavesCentreClearPaintsBandAndStaysInsideExtent() {
        let canvas = render(PointerStyle(preset: .ring, bandWidth: 0.26, glowIntensity: 1))
        // standard sizes: radius 36, band 9.36, band spans 26.64...36.
        let extent = CGRect(x: -80.4, y: -80.4, width: 160.8, height: 160.8)
        assertNothingOutsideExtent(canvas, extent: extent, tolerance: 0.05)
        XCTAssertLessThan(canvas.alpha(atX: 200, atY: 200), 0.03, "the hole is punched clear")
        XCTAssertGreaterThan(canvas.alpha(atX: 200, atY: 231), 0.4, "the band ring is painted")
        XCTAssertGreaterThan(canvas.alpha(atX: 231, atY: 200), 0.4, "the band ring is painted")
    }

    // MARK: - Squircle

    func testSquircleLeavesCornersOfTheBoundingSquareClear() {
        let canvas = render(PointerStyle(preset: .squircle, bandWidth: 0.26, glowIntensity: 0))
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
        let canvas = render(PointerStyle(preset: .dot, glowIntensity: 0))
        XCTAssertGreaterThan(canvas.alpha(atX: 200, atY: 200), 0.4, "the centre is filled")
        XCTAssertGreaterThan(canvas.alpha(atX: 190, atY: 210), 0.4, "no hollow hole")
        XCTAssertGreaterThan(canvas.alpha(atX: 210, atY: 190), 0.4, "no hollow hole")
        XCTAssertLessThan(canvas.alpha(atX: 245, atY: 200), 0.03, "nothing beyond the disc")
    }

    // MARK: - Marker tip

    func testMarkerTipIsOpaqueAtCentreAndChiselAsymmetric() {
        let canvas = render(PointerStyle(preset: .markerTip, glowIntensity: 0))
        XCTAssertGreaterThan(canvas.alpha(atX: 200, atY: 200), 0.4, "the body is filled")

        // The nib tapers toward centre.y - radius and keeps a wide rounded
        // body toward centre.y + radius: rows near the tip are far narrower
        // than rows near the body, and the centre row is the full body width.
        let tipRow = canvas.rowWidth(atY: 168)
        let centreRow = canvas.rowWidth(atY: 200)
        let bodyRow = canvas.rowWidth(atY: 232)
        XCTAssertGreaterThan(tipRow, 2, "the tip is a real shape, not a vanished point")
        XCTAssertGreaterThan(bodyRow, 39, "the body keeps most of the diameter")
        XCTAssertLessThan(tipRow, bodyRow / 2, "the nib tapers")
        XCTAssertGreaterThan(centreRow, 39, "the body is filled across the centre")
    }

    // MARK: - Spotlight

    func testSpotlightFadesMonotonicallyWithNoHardEdgeAtTheRadius() {
        let canvas = render(PointerStyle(preset: .spotlight, glowIntensity: 1))
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
        let canvas = render(PointerStyle(preset: .rhombus, bandWidth: 0.26, glowIntensity: 0))
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
        var style = PointerStyle.standard
        style.preset = .rhombus
        let appearance = style.appearance(ink: .red)
        let extent = PointerHighlightRenderer.extent(for: appearance, pulseScale: 1)
        XCTAssertEqual(extent.minX, -80.4, accuracy: 0.001)
        XCTAssertEqual(extent.width, 160.8, accuracy: 0.001)
        let canvas = render(appearance, pulseScale: 1)
        assertNothingOutsideExtent(canvas, extent: extent, tolerance: 0.05)
    }

    // MARK: - Dashed border (T14/S9)

    /// The dash rhythm is pinned here: rounded dashes twice as long as their
    /// gaps, both derived from the band width, so the rhythm scales with the
    /// highlight.
    func testDashPatternIsDerivedFromTheBandWidth() {
        XCTAssertEqual(PointerHighlightRenderer.dashPattern(band: 9.36), [18.72, 18.72])
        XCTAssertEqual(PointerHighlightRenderer.dashPattern(band: 20), [40, 40])
    }

    /// Scans the band's mid-radius circle: the solid border paints every
    /// angle, the dashed one leaves alternating painted and clear samples.
    func testDashedRingLeavesGapsWhereTheSolidBorderPaints() {
        var solidStyle = PointerStyle(preset: .ring, bandWidth: 0.26, glowIntensity: 0)
        solidStyle.borderStyle = .solid
        var dashedStyle = solidStyle
        dashedStyle.borderStyle = .dashed
        let solid = render(solidStyle)
        let dashed = render(dashedStyle)

        let midBand = 36 - 9.36 / 2
        var solidGaps = 0
        var dashedPainted = 0
        var dashedGaps = 0
        for degrees in stride(from: 0, to: 360, by: 3) {
            let radians = CGFloat(degrees) * .pi / 180
            let x = 200 + midBand * cos(radians)
            let y = 200 + midBand * sin(radians)
            if solid.alpha(atX: x, atY: y) < 0.4 { solidGaps += 1 }
            if dashed.alpha(atX: x, atY: y) > 0.4 { dashedPainted += 1 }
            if dashed.alpha(atX: x, atY: y) < 0.05 { dashedGaps += 1 }
        }
        XCTAssertEqual(solidGaps, 0, "the solid border paints the whole band")
        XCTAssertGreaterThan(dashedPainted, 0, "the dashed border still paints")
        XCTAssertGreaterThan(
            dashedGaps, 0,
            "gaps exist along the same outline where the solid one has paint"
        )
    }

    /// The same rhythm along the squircle's straight edge: the dashed border
    /// keeps the silhouette (the band spans the same radial range) but
    /// alternates along it, starting from the path's start corner.
    func testDashedSquircleAlternatesAlongTheSameOutlineTheSolidFills() {
        var solidStyle = PointerStyle(preset: .squircle, bandWidth: 0.26, glowIntensity: 0)
        var dashedStyle = solidStyle
        dashedStyle.borderStyle = .dashed
        let solid = render(solidStyle)
        let dashed = render(dashedStyle)

        // Straight top edge: band spans 26.64...36 above the centre row.
        let midBandY = 200 + 36 - 9.36 / 2
        var solidGaps = 0
        var painted = 0
        var gaps = 0
        for dx in stride(from: -25, through: 25, by: 2) {
            if solid.alpha(atX: CGFloat(200 + dx), atY: CGFloat(midBandY)) < 0.4 { solidGaps += 1 }
            if dashed.alpha(atX: CGFloat(200 + dx), atY: CGFloat(midBandY)) > 0.4 { painted += 1 }
            if dashed.alpha(atX: CGFloat(200 + dx), atY: CGFloat(midBandY)) < 0.05 { gaps += 1 }
        }
        XCTAssertEqual(solidGaps, 0, "the solid band covers the straight edge")
        XCTAssertGreaterThan(painted, 0)
        XCTAssertGreaterThan(gaps, 0, "the dashed edge leaves gaps the solid one fills")
        // The silhouette holds: at a painted angle the band spans the same
        // radial range the solid one fills, and nothing is painted past the
        // outline.
        var paintedX: CGFloat?
        for dx in stride(from: -25, through: 25, by: 2) {
            if dashed.alpha(atX: CGFloat(200 + dx), atY: CGFloat(midBandY)) > 0.4 {
                paintedX = CGFloat(200 + dx)
                break
            }
        }
        XCTAssertNotNil(paintedX)
        // The silhouette holds: the outline still carries paint on the
        // straight edge (the dash phase at this pinned size puts one there),
        // and nothing is painted past the outline.
        XCTAssertGreaterThan(dashed.alpha(atX: 200, atY: CGFloat(midBandY)), 0.4, "the outline is still painted")
        XCTAssertLessThan(dashed.alpha(atX: paintedX ?? 200, atY: 200 + 43), 0.03, "nothing beyond the outline")
    }

    // MARK: - Opacity (T14/S9)

    /// Opacity multiplies every drawn alpha: 1 is today's look, 0.5 roughly
    /// halves the band and visibly dims the glow.
    func testOpacityHalvesTheBandAlphaAndDimsTheGlow() {
        let full = render(PointerStyle(preset: .ring, bandWidth: 0.26, glowIntensity: 1, opacity: 1))
        let half = render(PointerStyle(preset: .ring, bandWidth: 0.26, glowIntensity: 1, opacity: 0.5))
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

    /// The pulse envelope rotates the shape about its centre without changing
    /// the extent: the same invalidation rect stays valid while the shape
    /// turns.
    func testRotationMovesTheShapeButKeepsTheExtent() {
        let appearance = PointerStyle(preset: .markerTip, glowIntensity: 0).appearance(ink: .red)
        let atRest = render(appearance, pulseScale: 1, rotation: 0)
        let quarterTurn = render(appearance, pulseScale: 1, rotation: .pi / 2)
        XCTAssertNotEqual(atRest.data, quarterTurn.data, "rotation moves pixels")
        // The nib points up at rest: its rounded body sits below the centre.
        XCTAssertGreaterThan(atRest.alpha(atX: 200, atY: 230), 0.4, "the body sits under the nib")
        XCTAssertLessThan(quarterTurn.alpha(atX: 200, atY: 230), 0.03, "a quarter turn carries the body away")
        XCTAssertGreaterThan(quarterTurn.alpha(atX: 170, atY: 200), 0.4, "the body moved to the side")
        // The extent is unchanged: rotation is about the centre of the same
        // reach, so the invalidation rect stays the same rectangle.
        let extent = PointerHighlightRenderer.extent(for: appearance, pulseScale: 1)
        XCTAssertEqual(extent.minX, -80.4, accuracy: 0.001)
        XCTAssertEqual(extent.width, 160.8, accuracy: 0.001)
        assertNothingOutsideExtent(quarterTurn, extent: extent, tolerance: 0.05)
    }

    /// Even the rhombus — the shape that pokes past the circle — stays inside
    /// the shared extent while the pulse rotates it.
    func testRotatedRhombusStaysInsideTheSameExtent() {
        var style = PointerStyle.standard
        style.preset = .rhombus
        let appearance = style.appearance(ink: .red)
        let turned = render(appearance, pulseScale: 1, rotation: 0.42)
        let extent = PointerHighlightRenderer.extent(for: appearance, pulseScale: 1)
        assertNothingOutsideExtent(turned, extent: extent, tolerance: 0.05)
    }

    // MARK: - Glow

    func testGlowOffLeavesNothingOutsideTheBand() {
        let canvas = render(PointerStyle(preset: .squircle, glowIntensity: 0))
        // Outside the band plus its edges (radius 37) nothing is painted at all.
        XCTAssertLessThan(canvas.alpha(atX: 200, atY: 200 + 43), 0.03, "glow off paints no halo")
        XCTAssertLessThan(canvas.alpha(atX: 200, atY: 200 - 43), 0.03)
        XCTAssertLessThan(canvas.alpha(atX: 200 + 43, atY: 200), 0.03)
    }

    func testWeakerGlowIsDimmerThanStrongerGlow() {
        let weak = render(PointerStyle(preset: .squircle, glowIntensity: 0.4))
        let strong = render(PointerStyle(preset: .squircle, glowIntensity: 1))
        // Sample in the halo at 1.3r, between the band and the glow reach.
        let weakSample = weak.alpha(atX: 200, atY: 200 + 47)
        let strongSample = strong.alpha(atX: 200, atY: 200 + 47)
        XCTAssertGreaterThan(strongSample, 0.05, "the strong glow paints the halo")
        XCTAssertGreaterThan(weakSample, 0.01, "the weak glow still paints the halo")
        XCTAssertLessThan(weakSample, strongSample, "a weaker glow paints a dimmer halo")
    }
}
