import AppKit
import XCTest

@testable import Stare
import StareCore

/// Spec S3 of batch A: the tools' own cursors ("los cursores personalizados
/// de los tools .. y no todos son diferentes"). The four shapes the owner
/// named are pinned where a test can see them: the cursors are rendered into
/// a bitmap and the alpha channel is scanned, so "filled", "empty" and
/// "two rings" are measured pixel facts, not intentions. S7 sharpens the
/// table: the highlighter's beam turns vertical, and the drafting tools
/// (arrow, rectangle, ellipse) join line on the system crosshair, answered
/// by identity instead of drawn art.
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

    /// "el cursor de highligh debe ser el cursor bloque fill", turned
    /// vertical by S7 — a FILLED block with flat edges: the interior paints
    /// continuously down the centre column, and the block is taller than
    /// wide.
    func testHighlighterShowsAFilledVerticalBeam() throws {
        let cursor = OverlayView.cursor(for: .markerBeam)
        for point in [NSPoint(x: 8, y: 8), NSPoint(x: 8, y: 6.5), NSPoint(x: 8, y: 9.5),
            NSPoint(x: 7, y: 8), NSPoint(x: 9, y: 8)] {
            try XCTAssertGreaterThan(
                alpha(of: cursor, at: point), 0.5,
                "the highlighter's beam must be filled at \(point) — an outline-only chisel fails")
        }
        let box = try paintedBounds(of: cursor)
        XCTAssertGreaterThanOrEqual(
            box.height - box.width, 2.0,
            "the highlighter's beam reads vertical, not horizontal and not square: \(box)")
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

    /// S7: "la elipse, el rect y arrow pasan a ser cursor cruz como la
    /// linea" — the three shape tools answer the system crosshair BY
    /// IDENTITY, the way line already does, and no drawn glyph is built for
    /// them any more (after S7 the drawn set was seven; S1 retires two
    /// more shapes — the blur's dot grid and the spotlight's beam — and it
    /// is five).
    func testTheShapeToolsAnswerTheCrosshairByIdentity() throws {
        for role in [ToolCursor.lineCrosshair, .arrowCrosshair, .rectangleCrosshair, .ellipseCrosshair] {
            let cursor = OverlayView.cursor(for: role)
            XCTAssertTrue(cursor === NSCursor.crosshair, "\(role) must be the system crosshair")
        }
    }

    /// S1: "los cursores del blur y el spotlight deben ser la cruz" — the
    /// blur and the spotlight stop owning drawn glyphs and answer the
    /// system crosshair BY IDENTITY through their own roles, the way the
    /// shape tools do. No drawn glyph may claim them either: the retired
    /// dot grid and beam art must never come back under the crosshair
    /// roles.
    func testBlurAndSpotlightAnswerTheCrosshairByIdentity() throws {
        for tool in [Tool.blur, .spotlight] {
            let cursor = OverlayView.cursor(for: tool.cursor)
            XCTAssertTrue(
                cursor === NSCursor.crosshair,
                "S1: \(tool.rawValue) must answer the drafting crosshair by identity, not a drawn glyph")
        }
        for role in [ToolCursor.blurCrosshair, .spotlightCrosshair] {
            XCTAssertFalse(
                OverlayView.isGlyphServed(role),
                "S1: \(role) must not be served by a drawn glyph — the crosshair answers it")
        }
    }

    /// S1's contract pin: EVERY cursor role is answered by exactly one of
    /// the two serving halves, pinned role by role — so the contract cannot
    /// silently lose one, and the mapping's `?? .crosshair` fallback can
    /// never dress a lost role as served. No role variable is ever iterated
    /// or compared with `==`: this suite's runtimes have shown equality on
    /// `ToolCursor` collapsing the cases, so these pins go through pointer
    /// identity (`===`) and count checks — literal per-role code neither
    /// bug can fool. This test absorbs the old per-role shape contract the
    /// withdrawn `testEveryDrawnRoleBuildsAFullSizeCentredGlyph` pinned.
    func testTheContractCoversEveryRoleExactlyOnceAndServesEachRightly() throws {
        // The vocabulary is exactly the tool set: a fourteenth or twelfth
        // role fails the count, and a new role fails to compile the pins
        // below until it is pinned to one half.
        XCTAssertEqual(ToolCursor.allCases.count, Tool.allCases.count, "one role per tool")
        XCTAssertEqual(ToolCursor.allCases.count, 13, "the vocabulary is exactly the tool set")

        // Identity-served (8): the exact system cursor, by pointer identity.
        XCTAssertTrue(OverlayView.cursor(for: .editArrow) === NSCursor.arrow, "editArrow must be the system arrow")
        XCTAssertTrue(OverlayView.cursor(for: .textIBeam) === NSCursor.iBeam, "textIBeam must be the system I-beam")
        XCTAssertTrue(OverlayView.cursor(for: .lineCrosshair) === NSCursor.crosshair, "lineCrosshair must be the system crosshair")
        XCTAssertTrue(OverlayView.cursor(for: .arrowCrosshair) === NSCursor.crosshair, "arrowCrosshair must be the system crosshair")
        XCTAssertTrue(OverlayView.cursor(for: .rectangleCrosshair) === NSCursor.crosshair, "rectangleCrosshair must be the system crosshair")
        XCTAssertTrue(OverlayView.cursor(for: .ellipseCrosshair) === NSCursor.crosshair, "ellipseCrosshair must be the system crosshair")
        XCTAssertTrue(OverlayView.cursor(for: .blurCrosshair) === NSCursor.crosshair, "S1: blurCrosshair must be the system crosshair")
        XCTAssertTrue(OverlayView.cursor(for: .spotlightCrosshair) === NSCursor.crosshair, "S1: spotlightCrosshair must be the system crosshair")

        // Drawn-served (5): a 16-pt glyph centred on the hotspot, never a
        // silent fallback onto a system cursor. The cursors are built from
        // literal roles and then checked as VALUES, so no equality on the
        // enum is ever consulted.
        for (name, cursor) in [("penDot", OverlayView.cursor(for: .penDot)),
            ("markerBeam", OverlayView.cursor(for: .markerBeam)),
            ("numberRings", OverlayView.cursor(for: .numberRings)),
            ("laserSpark", OverlayView.cursor(for: .laserSpark)),
            ("eraserRing", OverlayView.cursor(for: .eraserRing))] {
            XCTAssertEqual(cursor.image.size.width, 16, "\(name) glyph width — 16-pt canvas")
            XCTAssertEqual(cursor.image.size.height, 16, "\(name) glyph height — 16-pt canvas")
            XCTAssertEqual(cursor.hotSpot.x, 8, "\(name) hotspot centred on x")
            XCTAssertEqual(cursor.hotSpot.y, 8, "\(name) hotspot centred on y")
            for (systemName, system) in [("arrow", NSCursor.arrow), ("iBeam", NSCursor.iBeam), ("crosshair", NSCursor.crosshair)] {
                XCTAssertFalse(cursor === system, "\(name) must never silently fall back onto the \(systemName) cursor")
            }
        }
    }

    /// S9: the armed area-drag crosshair (`answeredCursor()`) must never
    /// survive past area mode. Every disarm path was traced — the drag's
    /// mouse up, Esc (`cancelAreaSelection`), Return
    /// (`confirmPreloadedArea`) — and all three restore the tool's cursor;
    /// the leak that WAS live is `clear()`: the palette's Clear button and
    /// the deactivation clear run while the view stays alive, and the armed
    /// mode survived them, keeping the crosshair and the armed shroud on a
    /// session that no longer existed. The clear now disarms through the
    /// same path a cancelled drag uses.
    func testTheArmedAreaCrosshairDoesNotSurviveAClear() throws {
        let state = EditorState()
        state.tool = .pen
        let view = OverlayView(
            frame: CGRect(origin: .zero, size: CGSize(width: 300, height: 200)),
            state: state, onEscape: {})
        view.onAreaSelectionFrame = {}

        view.beginAreaSelection()
        XCTAssertTrue(
            view.answeredCursor() === NSCursor.crosshair,
            "armed area mode answers the crosshair, as before")
        // The armed shroud is on screen too: armed with no drag yet, the
        // whole bounds dim (α 0.18).
        let whileArmed = try Self.alphaRep(of: view)
        let armedPixel = try XCTUnwrap(whileArmed.colorAt(x: 150, y: 100))
        XCTAssertGreaterThan(
            armedPixel.alphaComponent, 0.1,
            "while armed, the shroud is on screen")

        // The clear (the palette's Clear button path): the crosshair and
        // the shroud must both go, and the tool's own cursor must answer
        // again through the same path a cancelled drag uses.
        view.clear()
        XCTAssertTrue(
            view.answeredCursor() === OverlayView.cursor(for: .penDot),
            "S9: after a clear of an armed session, the pen's own cursor answers — the crosshair must not stick")
        let afterClear = try Self.alphaRep(of: view)
        let clearedPixel = try XCTUnwrap(afterClear.colorAt(x: 150, y: 100))
        XCTAssertEqual(
            clearedPixel.alphaComponent, 0, accuracy: 0.01,
            "S9: the armed shroud must not survive the clear")
    }

    /// PRESERVE: withdrawn with S1 — the role it pinned (`.spotlightBeam`)
    /// is retired; the spotlight's cursor read is re-derived by S1 in
    /// `testBlurAndSpotlightAnswerTheCrosshairByIdentity` above.

    // MARK: the whole drawn set keeps its contract

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

    /// S9: renders a view through its own draw path, the way the freeze and
    /// guides tests read pixels off the real render.
    private static func alphaRep(of view: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
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
