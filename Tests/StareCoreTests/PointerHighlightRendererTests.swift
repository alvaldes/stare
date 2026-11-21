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
        render(style.appearance(ink: .red), pulseScale: pulseScale)
    }

    private func render(_ appearance: PointerAppearance, pulseScale: CGFloat) -> Canvas {
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
            pulseScale: pulseScale
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
