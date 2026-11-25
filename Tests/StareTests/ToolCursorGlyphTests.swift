import AppKit
import XCTest

@testable import Stare
import StareCore

/// Spec S3 of batch A: the tools' own cursors ("los cursores personalizados
/// de los tools .. y no todos son diferentes"). The four shapes the owner
/// named are pinned where a test can see them: the cursors are rendered into
/// a bitmap and the alpha channel is scanned, so "filled", "empty" and
/// "two rings" are measured pixel facts, not intentions.
///
/// Every glyph is drawn on the same 16-pt canvas with the hotspot at the
/// exact centre, so distances below are measured from the hotspot.
@MainActor
final class ToolCursorGlyphTests: XCTestCase {
    /// The rendered alpha at a point, in the cursor's own point coordinates
    /// (the flipped drawing space the glyphs are built in). 2× sampling.
    private func alpha(of cursor: NSCursor, at point: NSPoint) throws -> CGFloat {
        try Self.alphaTable(of: cursor.image).sample(at: point)
    }

    /// The painted bounding box of a cursor's image, in points.
    private func paintedBounds(of cursor: NSCursor) throws -> CGRect {
        try Self.paintedBounds(of: cursor.image)
    }

    // MARK: the four shapes the owner named

    /// "el cursor de pen debe ser un dot o algo asi" — a FILLED dot at the
    /// hotspot: the centre and a ring of points around it all paint, and the
    /// ink stays a small square-ish dot, not a line or a big icon.
    func testPenShowsAFilledDot() throws {
        let cursor = OverlayView.cursor(for: .penDot)
        for point in [NSPoint(x: 8, y: 8), NSPoint(x: 7, y: 8), NSPoint(x: 9, y: 8),
            NSPoint(x: 8, y: 7), NSPoint(x: 8, y: 9)] {
            try XCTAssertGreaterThan(
                alpha(of: cursor, at: point), 0.5,
                "the pen's dot must be filled at \(point) — an outline or an off-centre shape fails")
        }
        let box = try paintedBounds(of: cursor)
        XCTAssertLessThanOrEqual(max(box.width, box.height), 7.5, "the pen's dot stays small: \(box)")
        XCTAssertGreaterThanOrEqual(min(box.width, box.height), 3.0, "the pen's dot stays visible: \(box)")
        XCTAssertLessThanOrEqual(abs(box.width - box.height), 1.5, "the pen's dot is round, not a bar: \(box)")
    }

    /// "el cursor de highligh debe ser el cursor bloque fill" — a FILLED
    /// block with flat edges: the interior paints continuously across the
    /// centre row, and the block is wider than tall (a beam, not the
    /// rectangle's square frame).
    func testHighlighterShowsAFilledBeam() throws {
        let cursor = OverlayView.cursor(for: .markerBeam)
        for point in [NSPoint(x: 8, y: 8), NSPoint(x: 6.5, y: 8), NSPoint(x: 9.5, y: 8),
            NSPoint(x: 8, y: 7), NSPoint(x: 8, y: 9)] {
            try XCTAssertGreaterThan(
                alpha(of: cursor, at: point), 0.5,
                "the highlighter's beam must be filled at \(point) — an outline-only chisel fails")
        }
        let box = try paintedBounds(of: cursor)
        XCTAssertGreaterThanOrEqual(
            box.width - box.height, 2.0,
            "the highlighter's beam reads wide (a swab), not square (the rectangle's frame): \(box)")
    }

    /// "el erase un circulo sin relleno solo borde" — an EMPTY circle: the
    /// centre must be transparent (no fill at all) while a ring of ink sits
    /// out at the border.
    func testEraserShowsAnEmptyCircleBorderOnly() throws {
        let cursor = OverlayView.cursor(for: .eraserRing)
        try XCTAssertLessThanOrEqual(
            alpha(of: cursor, at: NSPoint(x: 8, y: 8)), 0.01,
            "the eraser's circle must stay EMPTY at the centre — a filled block fails")
        try XCTAssertLessThanOrEqual(
            alpha(of: cursor, at: NSPoint(x: 8.8, y: 8.8)), 0.01,
            "the eraser's interior stays clear away from the rim")
        for point in [NSPoint(x: 13, y: 8), NSPoint(x: 3, y: 8), NSPoint(x: 8, y: 3), NSPoint(x: 8, y: 13)] {
            try XCTAssertGreaterThan(
                alpha(of: cursor, at: point), 0.5,
                "the eraser's ink must sit on the border ring at \(point)")
        }
        let box = try paintedBounds(of: cursor)
        XCTAssertLessThanOrEqual(abs(box.width - box.height), 1.5, "the eraser's ring is a circle: \(box)")
        XCTAssertGreaterThanOrEqual(box.width, 9.0, "the eraser's ring reads at 16 pt: \(box)")
    }

    /// "el count debe ser un circulo dentro de otro circulo" — two
    /// concentric rings: ink at the inner ring's radius, a clear gap between
    /// the rings, ink at the outer ring's radius, and a hollow centre.
    func testNumberShowsACircleInsideACircle() throws {
        let cursor = OverlayView.cursor(for: .numberRings)
        try XCTAssertLessThanOrEqual(
            alpha(of: cursor, at: NSPoint(x: 8, y: 8)), 0.01,
            "the number's inner circle keeps its own hollow interior — a filled dot fails")
        try XCTAssertGreaterThan(
            alpha(of: cursor, at: NSPoint(x: 8 + 2.7, y: 8)), 0.5,
            "the INNER circle's ring must paint")
        try XCTAssertLessThanOrEqual(
            alpha(of: cursor, at: NSPoint(x: 8 + 4.3, y: 8)), 0.01,
            "there must be a clear GAP between the two circles")
        try XCTAssertGreaterThan(
            alpha(of: cursor, at: NSPoint(x: 8 + 5.9, y: 8)), 0.5,
            "the OUTER circle's ring must paint")
    }

    /// The audit's one real collision, fixed: the owner's eraser circle would
    /// have read exactly like the ellipse's cursor, which used to be drawn as
    /// a circle too. The ellipse keeps its role but is drawn as a TRUE OVAL
    /// (wider than tall) so the two rings never merge into one read.
    func testEllipseStaysAnOvalSoItNeverReadsAsTheEraserSCircle() throws {
        let cursor = OverlayView.cursor(for: .ellipseRing)
        try XCTAssertLessThanOrEqual(alpha(of: cursor, at: NSPoint(x: 8, y: 8)), 0.01, "the oval stays empty")
        let box = try paintedBounds(of: cursor)
        XCTAssertGreaterThanOrEqual(
            box.width - box.height, 2.0,
            "the ellipse's cursor must be an oval, not the eraser's circle: \(box)")
    }

    // MARK: the neighbour roles keep the reads they already had

    /// PRESERVE: the rectangle's frame stays an empty square outline and the
    /// spotlight keeps its ring around a FILLED dot — neither may drift into
    /// the eraser's empty circle or the number's rings.
    func testSpotlightAndRectangleKeepTheirEstablishedReads() throws {
        let frame = OverlayView.cursor(for: .rectangleFrame)
        try XCTAssertLessThanOrEqual(alpha(of: frame, at: NSPoint(x: 8, y: 8)), 0.01, "the frame stays empty")
        let frameBox = try paintedBounds(of: frame)
        XCTAssertLessThanOrEqual(abs(frameBox.width - frameBox.height), 1.5, "the frame stays square: \(frameBox)")

        let beam = OverlayView.cursor(for: .spotlightBeam)
        try XCTAssertGreaterThan(alpha(of: beam, at: NSPoint(x: 8, y: 8)), 0.5, "the spotlight keeps its filled source dot")
        try XCTAssertGreaterThan(alpha(of: beam, at: NSPoint(x: 8 + 4.6, y: 8)), 0.5, "the spotlight keeps its ring")
    }

    // MARK: the whole drawn set keeps its contract

    /// The system roles answer the exact AppKit cursor by identity; every
    /// other role builds a 16-pt glyph with the hotspot at the centre (so the
    /// mark still lands under the pointer) and never silently falls back to a
    /// system cursor.
    func testEveryDrawnRoleBuildsAFullSizeCentredGlyph() throws {
        let system: [ToolCursor: NSCursor] = [
            .editArrow: .arrow, .textIBeam: .iBeam, .lineCrosshair: .crosshair,
        ]
        for role in ToolCursor.allCases {
            let cursor = OverlayView.cursor(for: role)
            if let expected = system[role] {
                XCTAssertTrue(cursor === expected, "\(role) must be the system cursor")
            } else {
                XCTAssertEqual(cursor.image.size.width, 16, "\(role) glyph width")
                XCTAssertEqual(cursor.image.size.height, 16, "\(role) glyph height")
                XCTAssertEqual(cursor.hotSpot.x, 8, "\(role) hotspot x")
                XCTAssertEqual(cursor.hotSpot.y, 8, "\(role) hotspot y")
                for (_, systemCursor) in system {
                    XCTAssertTrue(cursor !== systemCursor, "\(role) fell back to a system cursor")
                }
            }
        }
    }

    // MARK: bitmap plumbing

    private struct AlphaTable {
        let bitmap: NSBitmapImageRep
        let scale: CGFloat

        func sample(at point: NSPoint) -> CGFloat {
            let x = min(max(Int(floor(point.x * scale)), 0), bitmap.pixelsWide - 1)
            let y = min(max(Int(floor(point.y * scale)), 0), bitmap.pixelsHigh - 1)
            return bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
        }
    }

    private static func alphaTable(of image: NSImage) throws -> AlphaTable {
        let scale: CGFloat = 2
        let width = Int(image.size.width * scale)
        let height = Int(image.size.height * scale)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return AlphaTable(bitmap: bitmap, scale: scale)
    }

    private static func paintedBounds(of image: NSImage) throws -> CGRect {
        let table = try alphaTable(of: image)
        var minX = table.bitmap.pixelsWide, minY = table.bitmap.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<table.bitmap.pixelsHigh {
            for x in 0..<table.bitmap.pixelsWide {
                guard (table.bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return .null }
        return CGRect(
            x: CGFloat(minX) / table.scale, y: CGFloat(minY) / table.scale,
            width: CGFloat(maxX - minX + 1) / table.scale, height: CGFloat(maxY - minY + 1) / table.scale
        )
    }
}
