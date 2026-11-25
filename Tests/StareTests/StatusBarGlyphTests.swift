import AppKit
import XCTest
@testable import Stare

/// Spec S1 of batch A: the menu bar glyph reads small next to the system
/// items ("el tamanno del icono en el menu de la mac ... se ve pequenno").
/// The glyph's canvas side is the one named constant that governs its size,
/// and the ink it actually paints is pinned here by rendering the real glyph
/// and scanning the bitmap for the ink box — so a silent revert to the small
/// canvas cannot pass.
///
/// The shape itself is approved: the outline, the holes and the template
/// behaviour stay as they are. Only the weight changes.
final class StatusBarGlyphTests: XCTestCase {
    /// The canvas the glyph is drawn on, in points — the named constant the
    /// size lives in.
    private static let canvas = StatusBarController.menuBarGlyphSidePoints

    /// The painted ink must reach system weight: system status items carry
    /// roughly 16–18 pt of ink in the bar. The 18 pt canvas with the fixed
    /// 87 % inset painted only ~7.0 × 10.25 pt (the rotated nib covers little
    /// of the design box); the 22 pt canvas with the fitted 0.80 coverage
    /// claims an ink box of at least 15.5 pt tall and 10 pt wide, measured.
    private static let minimumInkHeight: CGFloat = 15.5
    private static let minimumInkWidth: CGFloat = 10.0

    func testInkBoxReadsAtSystemWeight() throws {
        let image = StatusBarController.menuBarGlyph()
        XCTAssertEqual(image.size.width, Self.canvas, accuracy: 0.01)
        XCTAssertEqual(image.size.height, Self.canvas, accuracy: 0.01)

        let ink = try Self.paintedBounds(of: image)
        XCTAssertGreaterThanOrEqual(
            ink.height, Self.minimumInkHeight,
            "the glyph's ink is too small to sit with the system items: measured height \(ink.height) pt"
        )
        XCTAssertGreaterThanOrEqual(
            ink.width, Self.minimumInkWidth,
            "the glyph's ink is too small to sit with the system items: measured width \(ink.width) pt"
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
