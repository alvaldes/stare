import CoreGraphics
import XCTest

import StareCore

/// S2/S3 with S4's revision: the spotlight stops being only round, but now
/// offers exactly the two shapes the owner wants — the ellipse and the
/// rounded rectangle — picked from the spotlight's own button through a
/// context menu (the control a user can find, pinned over the real bar in
/// `CaptureSpotlightShapeTests`). The shape is a property of the mark itself
/// (the `redactionStyle` persistence discipline: appended last, lenient
/// decode to the current ellipse default, explicit encode). The plain
/// rectangle is withdrawn from the offer but kept as data: its raw value
/// decodes and its silhouette renders exactly as it always did. The dimming
/// and the blending the ellipse keeps exactly as shipped; the flat shapes
/// cut the same weight of dim along their own silhouettes, so a sampled row
/// and a sampled column tell the shapes apart.
final class SpotlightShapeTests: XCTestCase {
    // MARK: - Pixel harness

    /// Renders at most one mark into a flat white RGBA bitmap of `canvas`'s
    /// size (top-left origin in point space, exactly like the overlay and the
    /// compositor lay marks out) at 2 px per point and answers the colour at
    /// `point`. The scale keeps every probe well past the anti-aliasing of a
    /// boundary it is not probing.
    private func colour(
        of stroke: Stroke,
        canvas: CGRect,
        at point: CGPoint,
        phase: MarkRenderer.Phase = .committed
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let size = CGSize(width: canvas.width, height: canvas.height)
        let scale: CGFloat = 2
        let width = Int(size.width * scale), height = Int(size.height * scale)
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        MarkRenderer.draw(strokes: [stroke], in: ctx, canvas: canvas, phase: phase)
        let image = ctx.makeImage()!
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let reader = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        reader.draw(image, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))
        let x = min(width - 1, max(0, Int(point.x * scale)))
        // Bottom-left origin in the raw buffer; the point space is top-left.
        let y = min(height - 1, max(0, Int((size.height - point.y) * scale)))
        let index = (y * width + x) * 4
        return (
            CGFloat(bytes[index]) / 255,
            CGFloat(bytes[index + 1]) / 255,
            CGFloat(bytes[index + 2]) / 255
        )
    }

    /// Renders one mark at 2 px per point and answers the raw raster bytes,
    /// for equality between two marks that must draw identically.
    private func raster(of stroke: Stroke, canvas: CGRect) -> [UInt8] {
        let scale: CGFloat = 2
        let width = Int(canvas.width * scale), height = Int(canvas.height * scale)
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: canvas.size))
        MarkRenderer.draw(strokes: [stroke], in: ctx, canvas: canvas)
        let image = ctx.makeImage()!
        return Array((image.dataProvider!.data! as Data))
    }

    private static let canvas = CGRect(x: 0, y: 0, width: 160, height: 120)
    private static let region = (from: CGPoint(x: 40, y: 30), to: CGPoint(x: 120, y: 90))

    private func spotlightStroke(_ shape: SpotlightShape) -> Stroke {
        Stroke(
            tool: .spotlight,
            ink: .black,
            points: [Self.region.from, Self.region.to],
            spotlightShape: shape
        )
    }

    /// Black at the shipped dim weight over white — 1 − 0.55.
    private var dimmedWhite: CGFloat { 0.45 }

    private func assertClear(
        _ pixel: (red: CGFloat, green: CGFloat, blue: CGFloat),
        _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(pixel.red, 0.97, message, file: file, line: line)
        XCTAssertGreaterThanOrEqual(pixel.green, 0.97, message, file: file, line: line)
        XCTAssertGreaterThanOrEqual(pixel.blue, 0.97, message, file: file, line: line)
    }

    /// The flat silhouettes' dim is exact at the shipped weight.
    private func assertDimmed(
        _ pixel: (red: CGFloat, green: CGFloat, blue: CGFloat),
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for channel in [pixel.red, pixel.green, pixel.blue] {
            XCTAssertEqual(channel, dimmedWhite, accuracy: 0.03, "the shipped dim weighs 0.45 here",
                           file: file, line: line)
        }
    }

    /// The ellipse's feathered ramp at a probe placed past the boundary: the
    /// dim has begun (the eased curve starts with zero slope — never full
    /// white) but never reached the deepest weight a flat silhouette cuts.
    private func assertSlightlyDimmed(
        _ pixel: (red: CGFloat, green: CGFloat, blue: CGFloat),
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertLessThan(pixel.red, 0.97, "some dim must have begun", file: file, line: line)
        XCTAssertGreaterThan(pixel.red, 0.6, "the weight must not be the deepest one yet", file: file, line: line)
        XCTAssertEqual(pixel.red, pixel.green, accuracy: 0.02, "colourless dim", file: file, line: line)
        XCTAssertEqual(pixel.red, pixel.blue, accuracy: 0.02, "colourless dim", file: file, line: line)
    }

    // MARK: - The offer and the withdrawn shape (S4)

    /// S4: the control offers exactly the two shapes the owner wants — the
    /// ellipse first, the rounded rectangle beside it — and the plain
    /// rectangle is no longer offered. The three-shape ⌥-click cycle pin of
    /// the last round is re-derived by this test and by the rectangle's
    /// survivorship test below.
    func testTheControlOffersExactlyTheTwoShapesTheOwnerWants() {
        XCTAssertEqual(SpotlightShape.menuChoices, [.ellipse, .roundedRectangle])
        XCTAssertFalse(
            SpotlightShape.menuChoices.contains(.rectangle),
            "the plain rectangle is withdrawn from the offer")
    }

    /// S4: the withdrawn plain rectangle is data, not an option. A mark drawn
    /// with it (the last build offered the ⌥-click cycle over three shapes)
    /// keeps decoding and rendering as the rectangle it was drawn as.
    func testAMarkPersistedWithThePlainRectangleStillDecodesAndRenders() throws {
        let stroke = spotlightStroke(.rectangle)
        let data = try JSONEncoder().encode(stroke.persisted)
        let restored = try JSONDecoder().decode(PersistedStroke.self, from: data)
        let mark = try XCTUnwrap(Stroke(persisted: restored))
        XCTAssertEqual(
            SpotlightShape(rawValue: "rectangle"), .rectangle,
            "the withdrawn raw value stays decodable")
        XCTAssertEqual(mark.spotlightShape, .rectangle)
        XCTAssertEqual(
            raster(of: mark, canvas: Self.canvas),
            raster(of: spotlightStroke(.rectangle), canvas: Self.canvas),
            "a rectangle mark renders exactly as it always did")
    }

    func testTheShapeRawValuesDecode() {
        XCTAssertEqual(SpotlightShape(rawValue: "rectangle"), .rectangle)
        XCTAssertEqual(SpotlightShape(rawValue: "ellipse"), .ellipse)
        XCTAssertEqual(SpotlightShape(rawValue: "roundedRectangle"), .roundedRectangle)
        XCTAssertEqual(SpotlightShape.allCases, [.rectangle, .ellipse, .roundedRectangle])
    }

    // MARK: - The shape is a property of the mark

    func testTheDrawingSessionStampsTheArmedShapeOnSpotlightMarks() {
        var session = DrawingSession()
        session.begin(at: Self.region.from, tool: .spotlight, ink: .red, spotlightShape: .rectangle)
        session.extend(to: Self.region.to)
        session.commit()
        XCTAssertEqual(session.strokes.first?.spotlightShape, .rectangle)

        // The shipped default is today's ellipse, so a mark minted without a
        // shape carries the look the spotlight has always had.
        var plain = DrawingSession()
        plain.begin(at: Self.region.from, tool: .spotlight, ink: .red)
        plain.extend(to: Self.region.to)
        plain.commit()
        XCTAssertEqual(plain.strokes.first?.spotlightShape, .ellipse)
    }

    /// The style keys' discipline held (S15): only the tool a property belongs
    /// to stores it — a rectangle never carries a spotlight shape.
    func testOnlyTheSpotlightCarriesItsShape() {
        var session = DrawingSession()
        session.begin(at: Self.region.from, tool: .rectangle, ink: .blue, spotlightShape: .roundedRectangle)
        session.extend(to: Self.region.to)
        session.commit()
        XCTAssertEqual(session.strokes.first?.spotlightShape, .ellipse)
    }

    // MARK: - Persistence: the `redactionStyle` discipline, exactly (S2/S3)

    func testTheShapeSurvivesSaveAndRestore() throws {
        let stroke = spotlightStroke(.roundedRectangle)
        let data = try JSONEncoder().encode(stroke.persisted)
        let restored = try JSONDecoder().decode(PersistedStroke.self, from: data)
        let mark = try XCTUnwrap(Stroke(persisted: restored))
        XCTAssertEqual(mark.spotlightShape, .roundedRectangle, "the shape the mark was drawn with survives")
        XCTAssertEqual(mark.points, stroke.points)
    }

    /// A document written before the field existed carries nothing: it decodes
    /// as the current default, the ellipse — and renders exactly as it always
    /// has.
    func testALegacyMarkDecodesAndRendersUnchanged() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","tool":"spotlight","ink":"red","points":[[40,30],[120,90]],"rotation":0}
        """.data(using: .utf8)!
        let persisted = try JSONDecoder().decode(PersistedStroke.self, from: json)
        XCTAssertNil(persisted.spotlightShape, "a legacy document names no shape")
        let mark = try XCTUnwrap(Stroke(persisted: persisted))
        XCTAssertEqual(mark.spotlightShape, .ellipse)
        XCTAssertEqual(
            raster(of: mark, canvas: Self.canvas),
            raster(of: spotlightStroke(.ellipse), canvas: Self.canvas),
            "a legacy spotlight renders unchanged")
    }

    /// An unknown raw value falls back to the current default, the same rule
    /// the redaction style keeps.
    func testAnUnknownStoredShapeFallsBackToTheEllipse() throws {
        var persisted = spotlightStroke(.ellipse).persisted
        persisted.spotlightShape = "triangle"
        let mark = try XCTUnwrap(Stroke(persisted: persisted))
        XCTAssertEqual(mark.spotlightShape, .ellipse)
    }

    // MARK: - The three shapes in render (S2): sampled row and column

    private static let litCentre = CGPoint(x: 80, y: 60)
    /// Far outside the region, past every shape's reach: the shipped weight.
    private static let farCorner = CGPoint(x: 150, y: 15)
    /// The lit centre's row, just left of the region.
    private static let rowProbe = CGPoint(x: 30, y: 60)
    /// A column through the region, above it.
    private static let columnProbe = CGPoint(x: 60, y: 15)
    /// Inside the dragged rectangle but outside its inscribed ellipse: the
    /// corner where the light stops being round.
    private static let rectCorner = CGPoint(x: 42, y: 32)
    /// Inside the dragged rectangle yet outside the rounded rectangle's dish —
    /// the corner edge the third shape rounds off.
    private static let roundedDish = CGPoint(x: 42, y: 34)
    /// Inside the rounded dish: the corner the rectangle keeps at full light
    /// and the rounded rectangle still lights.
    private static let roundedInsideCorner = CGPoint(x: 46, y: 36)
    /// A point only the ellipse's curve sweeps: half a radius out diagonally,
    /// well clear of both flat edges and of the rounded's own arc.
    private static let ellipseCurveProbe = CGPoint(x: 52, y: 39)

    func testEveryShapeLeavesItsLitInteriorClearAndDimsPastTheReach() {
        for shape in SpotlightShape.allCases {
            assertClear(
                colour(of: spotlightStroke(shape), canvas: Self.canvas, at: Self.litCentre),
                "the \(shape.rawValue) interior stays clear")
            assertDimmed(colour(of: spotlightStroke(shape), canvas: Self.canvas, at: Self.farCorner))
        }
    }

    func testTheRectangleCutsTheDimAtItsOwnSilhouette() {
        assertDimmed(colour(of: spotlightStroke(.rectangle), canvas: Self.canvas, at: Self.rowProbe))
        assertDimmed(colour(of: spotlightStroke(.rectangle), canvas: Self.canvas, at: Self.columnProbe))
        // The dragged rectangle's corner is lit — the point where the light
        // stops being round: the ellipse has already dimmed there.
        assertClear(
            colour(of: spotlightStroke(.rectangle), canvas: Self.canvas, at: Self.rectCorner),
            "a rectangle reaches into its own corner")
    }

    func testTheRoundedRectangleCutsTheDimAtItsOwnSilhouette() {
        assertDimmed(colour(of: spotlightStroke(.roundedRectangle), canvas: Self.canvas, at: Self.rowProbe))
        assertDimmed(colour(of: spotlightStroke(.roundedRectangle), canvas: Self.canvas, at: Self.columnProbe))
        // Inside the dish the corner may still light; just past the dish's own
        // boundary the dim cuts — the two samples that set the third shape
        // apart from both siblings.
        assertClear(
            colour(of: spotlightStroke(.roundedRectangle), canvas: Self.canvas, at: Self.roundedInsideCorner),
            "a rounded rectangle keeps its shallow corner lit")
        assertDimmed(
            colour(of: spotlightStroke(.roundedRectangle), canvas: Self.canvas, at: Self.roundedDish))
    }

    /// The unchanged ellipse: the feathered ramp it has always drawn. Past the
    /// boundary the ramp is partway, and the corner the rectangles light must
    /// cut — or nothing changed at all.
    func testTheEllipseKeepsItsFeatheredRamp() {
        assertSlightlyDimmed(colour(of: spotlightStroke(.ellipse), canvas: Self.canvas, at: Self.rowProbe))
        assertSlightlyDimmed(colour(of: spotlightStroke(.ellipse), canvas: Self.canvas, at: Self.rectCorner))
        assertDimmed(colour(of: spotlightStroke(.ellipse), canvas: Self.canvas, at: Self.farCorner))
        XCTAssertLessThan(
            colour(of: spotlightStroke(.ellipse), canvas: Self.canvas, at: Self.roundedInsideCorner).red,
            0.985,
            "the ellipse's boundary must run through the corner the rectangles light")
    }

    // MARK: - The in-progress preview shows the shape it will draw

    /// T8b's split holds per shape: while the mark is in hand no shape dims
    /// (T8b's own tests pin the ellipse branch byte for byte; the draw route
    /// does not change), and each shape's outline runs its own curve.
    func testTheInProgressPreviewNeverDimsAndCarriesItsOwnSilhouette() {
        for shape in SpotlightShape.allCases {
            assertClear(
                colour(
                    of: spotlightStroke(shape), canvas: Self.canvas,
                    at: Self.litCentre, phase: .inProgress),
                "the in-progress \(shape.rawValue) never dims")
        }
        // The ellipse's preview curve sweeps through the diagonal probe; the
        // flat shapes' outlines (their left-top corner dishes refused) do not.
        XCTAssertLessThan(
            colour(of: spotlightStroke(.ellipse), canvas: Self.canvas, at: Self.ellipseCurveProbe,
                   phase: .inProgress).red,
            0.9,
            "the in-progress ellipse's own curve runs through the diagonal probe")
        for shape in [SpotlightShape.rectangle, .roundedRectangle] {
            assertClear(
                colour(of: spotlightStroke(shape), canvas: Self.canvas,
                       at: Self.ellipseCurveProbe, phase: .inProgress),
                "the in-progress \(shape.rawValue) outline keeps clear of the diagonal probe")
        }
    }
}
