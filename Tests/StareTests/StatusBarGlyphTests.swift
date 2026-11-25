import AppKit
import XCTest
@testable import Stare

/// Spec S1 of batch A sized the glyph up; spec S5 asked for one step back down
/// ("el icono bajale un tilin al tamanno") and for the tilt to agree with the
/// app's own logo instead of mirroring it ("esta inclinado en la direccion
/// contraria al logo original").
///
/// The glyph's canvas side is the named constant that governs its size, and
/// the ink it actually paints is pinned by rendering the real glyph and
/// scanning the bitmap for the ink box — and now for the ink's axis as well.
/// The tilt pin is honest the same way: the axis the glyph draws is compared
/// against the axis measured from the app's own artwork pixels
/// (`Resources/AppIcon.icns`), not against an assumption.
final class StatusBarGlyphTests: XCTestCase {
    /// The canvas the glyph is drawn on, in points — the named constant the
    /// size lives in.
    private static let canvas = StatusBarController.menuBarGlyphSidePoints

    /// The painted ink band after the S5 reduction: the 22 pt canvas painted
    /// 11.0 × 16.0 pt (measured); one step down to a 20 pt canvas paints
    /// ~10.0 × 14.6. The band's UPPER bound is what makes the undo of the
    /// reduction detectable: at the old 22 pt canvas the ink (16.0 × 11.0)
    /// breaches it from both ends.
    private static let inkHeightBand: ClosedRange<CGFloat> = 14.0...15.0
    private static let inkWidthBand: ClosedRange<CGFloat> = 9.4...10.6

    func testInkBoxReadsAtTheReducedSystemWeight() throws {
        let image = StatusBarController.menuBarGlyph()
        XCTAssertEqual(image.size.width, Self.canvas, accuracy: 0.01)
        XCTAssertEqual(image.size.height, Self.canvas, accuracy: 0.01)

        let ink = try Self.paintedBounds(of: image)
        XCTAssertGreaterThanOrEqual(
            ink.height, Self.inkHeightBand.lowerBound,
            "the glyph's ink is too small for the reduced step: measured height \(ink.height) pt"
        )
        XCTAssertLessThanOrEqual(
            ink.height, Self.inkHeightBand.upperBound,
            "the glyph's ink grew past the reduced step: measured height \(ink.height) pt"
        )
        XCTAssertGreaterThanOrEqual(
            ink.width, Self.inkWidthBand.lowerBound,
            "the glyph's ink is too small for the reduced step: measured width \(ink.width) pt"
        )
        XCTAssertLessThanOrEqual(
            ink.width, Self.inkWidthBand.upperBound,
            "the glyph's ink grew past the reduced step: measured width \(ink.width) pt"
        )
        XCTAssertLessThanOrEqual(
            max(ink.width, ink.height), Self.canvas + 0.01,
            "the ink may not exceed its canvas: measured \(max(ink.width, ink.height)) pt"
        )
    }

    /// The glyph must keep actually painting. A PDF/bitmap representation was
    /// an earlier attempt recorded as broken — AppKit got an empty
    /// `NSPDFImageRep` and the status item drew nothing — so the drawn
    /// CG-path representation stays and must produce real ink.
    func testGlyphPaintsInkInsteadOfNothing() throws {
        let ink = try Self.paintedBounds(of: StatusBarController.menuBarGlyph())
        XCTAssertFalse(ink.isNull, "the glyph painted nothing")
        XCTAssertGreaterThan(ink.width, 0)
        XCTAssertGreaterThan(ink.height, 0)
    }

    /// S5: the glyph's tilt must agree with the app's own artwork, not mirror
    /// it. Measured, not asserted from a sign: the mask pieces of (a) the
    /// glyph as drawn and (b) the white nib inside the real
    /// `Resources/AppIcon.icns` are both put through the same axis probe
    /// (principal axis + tail-side tip detection), and the test pins that the
    /// glyph's axis leans the artwork's own way — same tip side (bottom-left
    /// in display space, the artwork's measured lean ≈ 32° from vertical)
    /// and the same angle within rasterisation tolerance.
    func testGlyphTiltAgreesWithTheArtworkAxis() throws {
        let artwork = try Self.axisFacts(
            points: Self.artworkNibMask(),
            context: "the app's own icns artwork"
        )
        let glyph = try Self.axisFacts(
            points: Self.glyphMask(),
            context: "the drawn menu bar glyph"
        )

        XCTAssertGreaterThan(artwork.pixels, 10_000, "the artwork's nib mask is implausibly small — the measurement is meaningless")
        XCTAssertGreaterThan(glyph.pixels, 100, "the glyph's ink mask is implausibly small — the measurement is meaningless")

        XCTAssertEqual(
            artwork.leanDegrees, 32.0,
            accuracy: 2.0,
            "the artwork itself no longer leans ~32°: re-measure before trusting this pin (measured \(artwork.leanDegrees)°)"
        )
        XCTAssertTrue(
            artwork.tipTowardBottomLeft,
            "the artwork's nib now tips bottom-right in display space — the S5 reference direction is gone"
        )

        XCTAssertEqual(
            glyph.leanDegrees, artwork.leanDegrees,
            accuracy: 2.5,
            "the glyph's axis no longer leans the artwork's angle: glyph \(glyph.leanDegrees)° vs artwork \(artwork.leanDegrees)°"
        )
        XCTAssertEqual(
            glyph.tipTowardBottomLeft, artwork.tipTowardBottomLeft,
            "the glyph tips the opposite way to the logo — the mirrored-tilt bug is back (glyph tip bottom-\(glyph.tipTowardBottomLeft ? "left" : "right"))"
        )
    }

    // MARK: - Measurements

    private struct AxisFacts {
        let leanDegrees: Double
        let tipTowardBottomLeft: Bool
        let pixels: Int
    }

    /// Principal axis of a 2-D point cloud (y-down bitmap coordinates), with
    /// the nib's tip resolved from the axis ends: the tip end carries the
    /// thin tail — far fewer pixels in its outer 20 % band than the round
    /// back of the nib carries.
    private static func axisFacts(points: [(Double, Double)], context: String) throws -> AxisFacts {
        guard !points.isEmpty else {
            XCTFail("\(context) produced an empty mask")
            return AxisFacts(leanDegrees: 0, tipTowardBottomLeft: false, pixels: 0)
        }
        let n = Double(points.count)
        let cx = points.reduce(0.0) { $0 + $1.0 } / n
        let cy = points.reduce(0.0) { $0 + $1.1 } / n
        let cxx = points.reduce(0.0) { $0 + ($1.0 - cx) * ($1.0 - cx) } / n
        let cxy = points.reduce(0.0) { $0 + ($1.0 - cx) * ($1.1 - cy) } / n
        let cyy = points.reduce(0.0) { $0 + ($1.1 - cy) * ($1.1 - cy) } / n

        let trace = cxx + cyy
        let halfDisc = max(0.0, trace * trace / 4 - (cxx * cyy - cxy * cxy)).squareRoot()
        let l1 = trace / 2 + halfDisc
        var vx = cxy
        var vy = l1 - cxx
        if abs(cxy) < 1e-9 {
            vx = 0; vy = 1 // the axis is vertical to within the mask's resolution
        }
        var projections = [Double]()
        projections.reserveCapacity(points.count)
        var minProjection = Double.greatestFiniteMagnitude
        var maxProjection = -Double.greatestFiniteMagnitude
        for point in points {
            let p = point.0 * vx + point.1 * vy
            projections.append(p)
            minProjection = min(minProjection, p)
            maxProjection = max(maxProjection, p)
        }
        let length = maxProjection - minProjection
        guard length > 0 else {
            XCTFail("\(context) projects onto a single point — the mask is degenerate")
            return AxisFacts(leanDegrees: 0, tipTowardBottomLeft: false, pixels: points.count)
        }
        func populationInOuterBand(_ side: Double) -> Int {
            projections.reduce(0) { count, p in
                let fraction = (p - minProjection) / length
                if side > 0 ? fraction > 0.8 : fraction < 0.2 { return count + 1 }
                return count
            }
        }
        let tipSide = populationInOuterBand(+1) < populationInOuterBand(-1) ? 1.0 : -1.0

        // A tip pixel: the extreme point on the tip's end of the axis.
        var tipX = 0.0
        var tipY = 0.0
        var extreme = tipSide > 0 ? -Double.greatestFiniteMagnitude : Double.greatestFiniteMagnitude
        for point in points {
            let p = point.0 * vx + point.1 * vy
            let isFurther = tipSide > 0 ? p > extreme : p < extreme
            if isFurther {
                extreme = p
                tipX = point.0
                tipY = point.1
            }
        }

        let leanDegrees = atan(abs(vx) / max(abs(vy), 1e-9)) * 180 / .pi
        let tipTowardBottomLeft = tipX < cx && tipY > cy
        return AxisFacts(
            leanDegrees: leanDegrees,
            tipTowardBottomLeft: tipTowardBottomLeft,
            pixels: points.count
        )
    }

    /// The white nib pixels inside the app's own icns. The repository's
    /// `Resources/` is reached by path because the test target ships no
    /// bundle resources. The threshold isolates pure-white pixels: the
    /// nib is the only near-white area inside the tile (the sheen gradient
    /// tops out well below it), so the mask is the nib and nothing else.
    private static func artworkNibMask() throws -> [(Double, Double)] {
        var resources = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { resources.deleteLastPathComponent() }
        let icnsURL = resources.appendingPathComponent("Resources").appendingPathComponent("AppIcon.icns")
        let image = try XCTUnwrap(NSImage(contentsOf: icnsURL), "the repo's AppIcon.icns must decode")
        return try maskPoints(
            of: image,
            samplingScale: 2,
            isInMask: { colour in
                colour.alphaComponent >= 0.9
                    && colour.redComponent >= 0.96
                    && colour.greenComponent >= 0.96
                    && colour.blueComponent >= 0.96
            }
        )
    }

    /// The glyph's ink pixels: black ink on transparent ground, so alpha is
    /// the mask. 4× sampling over the 20 pt canvas gives the axis enough
    /// resolution to lean out of rasterisation noise.
    private static func glyphMask() throws -> [(Double, Double)] {
        try maskPoints(
            of: StatusBarController.menuBarGlyph(),
            samplingScale: 4,
            isInMask: { $0.alphaComponent > 0.5 }
        )
    }

    private static func maskPoints(
        of image: NSImage,
        samplingScale: CGFloat,
        isInMask: (NSColor) -> Bool
    ) throws -> [(Double, Double)] {
        let size = image.size
        let width = Int(size.width * samplingScale)
        let height = Int(size.height * samplingScale)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )
        let bitmap = try XCTUnwrap(rep, "the test bitmap must allocate")
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        var points = [(Double, Double)]()
        for y in 0..<height {
            for x in 0..<width {
                guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                if isInMask(colour) {
                    points.append((Double(x), Double(y)))
                }
            }
        }
        return points
    }

    /// Renders the image into a bitmap and returns the bounding box, in
    /// points, of every pixel the glyph paints. The glyph is drawn as black
    /// ink on transparent ground, so alpha is the ink measure regardless of
    /// the menu bar's template tinting.
    private static func paintedBounds(of image: NSImage) throws -> CGRect {
        let size = image.size
        let scale: CGFloat = 2 // retina sampling so the ink box is measured finely
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )
        XCTAssertNotNil(rep, "the test bitmap must allocate")
        let bitmap = try XCTUnwrap(rep)
        bitmap.size = image.size // 2× pixels over the same point size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                guard alpha > 0.5 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return .null }
        // Pixel bounds to points: the painted edge pixel's far side is included.
        let points = CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
        return points
    }
}
