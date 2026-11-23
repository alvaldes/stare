import CoreGraphics
import XCTest
@testable import StareCore

/// T12/S19, slice 1 (the model and the geometry, nothing user-visible):
/// the canvas is componible — a base capture plus zero or more added layers,
/// each with its own placement — as a pure value in StareCore, beside the
/// crop space rather than duplicating it.
///
/// The space a layer's placement lives in is the capture's pixel space, the
/// same space `EditorCropSpace.coverage` cuts from: top-left origin, image
/// pixels. The editor maps it to the view through `EditorCropSpace` and the
/// viewport composes view placement on top, so **no view coordinates enter
/// the model** — the zoom that looks at a layer never moves what it saves.
///
/// The placement clamps (`CanvasComposition.clampedPlacement`) keep a layer
/// loseable-proof and grabbable, per axis:
///
/// - the scaled length is capped at the canvas length (a layer can never be
///   larger than the canvas) and floored at `min(minimumGrabSide,
///   canvasLength)` (it can never shrink below a grabbable side; when the
///   canvas itself is smaller, the canvas is the floor);
/// - the origin is clamped so at least `min(length, minimumGrabSide)` canvas
///   units of the layer stay over the canvas on that axis: a layer can hang
///   off an edge but a grabbable strip of it always remains, and a layer
///   smaller than the grab side stays fully inside. An intersection exactly
///   the length of the strip is legal — the clamp itself pins the boundary.
///
/// Identity is the layer's `UUID`, never its contents: two layers with the
/// same image and the same placement are distinct, and removing one must
/// leave exactly the other. The twin tests below are written with the input
/// that makes identity breakage *visible* — identical pixels and identical
/// placement, so a removal or reorder implemented by content or by index
/// picks the wrong layer and the surviving `id` betrays it.
final class CanvasCompositionTests: XCTestCase {
    private let canvas = CGRect(x: 0, y: 0, width: 300, height: 200)

    private func solid(_ colour: CGColor, width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(colour)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private var red: CGColor { CGColor(red: 1, green: 0, blue: 0, alpha: 1) }
    private var blue: CGColor { CGColor(red: 0, green: 0, blue: 1, alpha: 1) }
    private var green: CGColor { CGColor(red: 0, green: 1, blue: 0, alpha: 1) }
    private var white: CGColor { CGColor(red: 1, green: 1, blue: 1, alpha: 1) }

    /// A base that is not a flat colour, so a flip or a stale draw is visible.
    /// Lazy: one instance, so the no-resample pin can assert `===` against it.
    private lazy var base = solid(red, width: 300, height: 200)
    private lazy var greenSquare = solid(green, width: 50, height: 50)

    private struct RGB: Equatable {
        let r: UInt8, g: UInt8, b: UInt8
        static let red = RGB(r: 255, g: 0, b: 0)
        static let blue = RGB(r: 0, g: 0, b: 255)
        static let green = RGB(r: 0, g: 255, b: 0)
    }

    /// The read y is top-left, the space placements are written in — the
    /// byte buffer's first row is the image's top row, the same reader
    /// convention `MarkCompositorTests` documents. The image is re-rendered
    /// 1:1 at its own size, no scaling, so the sample is exact.
    /// Swatch colours come back through this same reader, so assertions pin
    /// position (exact) and colour (as the pipeline itself renders the
    /// swatch), not colour-management byte trivia.
    private func reference(_ colour: CGColor) -> RGB {
        pixel(solid(colour, width: 8, height: 8), x: 4, y: 4)
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> RGB {
        let line = image.width * 4
        let data = bytes(of: image)
        let base = y * line + x * 4
        return RGB(r: data[base], g: data[base + 1], b: data[base + 2])
    }

    private func bytes(of image: CGImage) -> [UInt8] {
        let context = CGContext(
            data: nil,
            width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let data = context.data else { return [] }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    // MARK: - The model: append, remove, reorder, move are value operations

    func testAppendAddsALayerWithItsOwnIdentityAndClampedPlacement() {
        var composition = CanvasComposition(base: base)
        let layer = composition.append(solid(green, width: 40, height: 40), at: CGRect(x: -100, y: 50, width: 500, height: 40))
        XCTAssertEqual(composition.layers, [layer], "the layer list holds exactly what append returned")
        XCTAssertEqual(
            layer.placement,
            CanvasComposition.clampedPlacement(CGRect(x: -100, y: 50, width: 500, height: 40), in: canvas),
            "append clamps a request that would hang fully off the canvas")
        XCTAssertNotEqual(layer.id, composition.append(solid(blue, width: 40, height: 40), at: CGRect(x: 10, y: 10, width: 40, height: 40)).id,
            "every appended layer gets its own identity")
        XCTAssertEqual(composition.pixelSize, CGSize(width: 300, height: 200), "the base's pixel size is the canvas")
    }

    func testRemoveDeletesExactlyTheLayerWithThatID() {
        var composition = CanvasComposition(base: base)
        let first = composition.append(solid(red, width: 40, height: 40), at: CGRect(x: 0, y: 0, width: 40, height: 40))
        let second = composition.append(solid(blue, width: 40, height: 40), at: CGRect(x: 60, y: 0, width: 40, height: 40))
        let third = composition.append(solid(green, width: 40, height: 40), at: CGRect(x: 120, y: 0, width: 40, height: 40))
        let removed = composition.remove(id: second.id)
        XCTAssertEqual(removed?.id, second.id)
        XCTAssertEqual(composition.layers.map(\.id), [first.id, third.id],
            "removing one layer leaves the others in their z-order")
        XCTAssertNil(composition.remove(id: second.id), "a removed identity no longer removes anything")
    }

    /// The identity pin: the two layers have the same image and the same
    /// placement, so nothing but `id` distinguishes them. A removal (or a
    /// reorder) implemented by content equality or by index would touch the
    /// wrong layer, and the surviving layers' ids — not their values —
    /// expose it. This input exists because this branch has already caught
    /// two bugs that passed on the one input where the defect is invisible.
    func testTwoLayersWithTheSameImageAndPlacementAreDistinctAndRemovingOneLeavesTheOther() {
        var composition = CanvasComposition(base: base)
        let placement = CGRect(x: 10, y: 10, width: 50, height: 50)
        let image = greenSquare
        let first = composition.append(image, at: placement)
        let twin = composition.append(image, at: placement)
        XCTAssertNotEqual(first.id, twin.id)
        XCTAssertEqual(first.image, twin.image)
        XCTAssertEqual(first.placement, twin.placement)

        composition.remove(id: twin.id)
        XCTAssertEqual(composition.layers.count, 1, "removing one of the twins removes exactly one")
        XCTAssertEqual(
            composition.layers.first?.id, first.id,
            "the survivor must be the layer that was NOT removed — a content- or index-based removal would leave the wrong twin and its id would betray it")
    }

    func testReorderMovesALayerInZOrderByItsIdentity() {
        var composition = CanvasComposition(base: base)
        let first = composition.append(solid(red, width: 40, height: 40), at: CGRect(x: 0, y: 0, width: 40, height: 40))
        let second = composition.append(solid(blue, width: 40, height: 40), at: CGRect(x: 60, y: 0, width: 40, height: 40))
        let third = composition.append(solid(green, width: 40, height: 40), at: CGRect(x: 120, y: 0, width: 40, height: 40))

        composition.reorder(id: third.id, to: 0)
        XCTAssertEqual(composition.layers.map(\.id), [third.id, first.id, second.id],
            "index 0 is the bottom of the z-order (drawn first)")

        composition.reorder(id: third.id, to: 99)
        XCTAssertEqual(composition.layers.map(\.id), [first.id, second.id, third.id],
            "an index beyond the top is clamped to the top")

        composition.reorder(id: third.id, to: -1)
        XCTAssertEqual(composition.layers.map(\.id), [third.id, first.id, second.id],
            "a negative index is clamped to the bottom")
    }

    /// The reorder twin pin: same input trick as the removal — identical
    /// layers, so only ids can tell whether the right one moved. Two twins
    /// cannot distinguish a content-based reorder (with one survivor, every
    /// placement of it looks the same), so three make the wrong pick visible:
    /// a removal-by-content leaves a duplicated twin behind.
    func testReorderMovesTheRequestedLayerEvenAmongIdenticalTwins() {
        var composition = CanvasComposition(base: base)
        let placement = CGRect(x: 10, y: 10, width: 50, height: 50)
        let image = greenSquare
        let first = composition.append(image, at: placement)
        let second = composition.append(image, at: placement)
        let third = composition.append(image, at: placement)
        composition.reorder(id: second.id, to: 0)
        XCTAssertEqual(
            composition.layers.map(\.id), [second.id, first.id, third.id],
            "the layer moved must be the one whose id was asked; a content-based reorder picks the first look-alike and a duplicate betrays it")
    }

    func testMoveShiftsOnlyTheTargetLayerAndClampsIt() {
        var composition = CanvasComposition(base: base)
        _ = composition.append(solid(red, width: 40, height: 40), at: CGRect(x: 0, y: 0, width: 40, height: 40))
        _ = composition.append(solid(blue, width: 40, height: 40), at: CGRect(x: 60, y: 0, width: 40, height: 40))
        let second = composition.layers[1]

        composition.move(id: second.id, by: CGSize(width: 300, height: -500))
        XCTAssertEqual(composition.layers[0].placement, CGRect(x: 0, y: 0, width: 40, height: 40),
            "a move touches only the layer moved")
        let moved = composition.layer(withID: second.id)?.placement
        XCTAssertEqual(
            moved,
            CanvasComposition.clampedPlacement(CGRect(x: 360, y: -500, width: 40, height: 40), in: canvas),
            "a move clamps the destination like append does")
        let strip = moved!.intersection(canvas)
        XCTAssertEqual(strip.width, CanvasComposition.minimumGrabSide,
            "after a move a grabbable strip of the layer stays on the canvas")
        XCTAssertEqual(composition.move(id: UUID(), by: CGSize(width: 10, height: 10)), nil,
            "moving an unknown identity changes nothing")
    }

    func testPlaceReplacesTheTargetPlacementClamped() {
        var composition = CanvasComposition(base: base)
        let layer = composition.append(solid(red, width: 40, height: 40), at: CGRect(x: 0, y: 0, width: 40, height: 40))
        composition.place(id: layer.id, at: CGRect(x: -1000, y: 50, width: 10, height: 10))
        XCTAssertEqual(
            composition.layer(withID: layer.id)?.placement,
            CanvasComposition.clampedPlacement(CGRect(x: -1000, y: 50, width: 10, height: 10), in: canvas),
            "placing clamps exactly like the pure function")
        composition.place(id: UUID(), at: CGRect(x: 5, y: 5, width: 40, height: 40))
        XCTAssertEqual(composition.layers.count, 1, "placing an unknown identity changes nothing")
    }

    // MARK: - Placement geometry: the clamps and their boundaries

    func testALayerNeverBecomesLargerThanTheCanvas() {
        let clamped = CanvasComposition.clampedPlacement(
            CGRect(x: -100, y: 50, width: 500, height: 100), in: canvas)
        XCTAssertEqual(clamped.width, canvas.width, "the scaled length is capped at the canvas length")
        XCTAssertEqual(clamped.height, 100)
        let exactlyTheCanvas = CanvasComposition.clampedPlacement(
            CGRect(x: 0, y: 50, width: 300, height: 100), in: canvas)
        XCTAssertEqual(exactlyTheCanvas, CGRect(x: 0, y: 50, width: 300, height: 100),
            "exactly canvas-sized is legal — the boundary itself")
    }

    func testALayerNeverShrinksBelowTheGrabbableSide() {
        let tiny = CanvasComposition.clampedPlacement(CGRect(x: 0, y: 0, width: 1, height: 2), in: canvas)
        XCTAssertEqual(tiny.width, CanvasComposition.minimumGrabSide)
        XCTAssertEqual(tiny.height, CanvasComposition.minimumGrabSide,
            "the smaller axis is floored at the grab side too — both sides must stay grabbable")
        let boundary = CanvasComposition.clampedPlacement(
            CGRect(x: 10, y: 10, width: CanvasComposition.minimumGrabSide, height: CanvasComposition.minimumGrabSide),
            in: canvas)
        XCTAssertEqual(boundary, CGRect(x: 10, y: 10, width: CanvasComposition.minimumGrabSide, height: CanvasComposition.minimumGrabSide),
            "exactly the grab side is legal — the boundary itself")
        let smallCanvas = CGRect(x: 0, y: 0, width: 8, height: 8)
        XCTAssertEqual(
            CanvasComposition.clampedPlacement(CGRect(x: 0, y: 0, width: 8, height: 8), in: smallCanvas),
            CGRect(x: 0, y: 0, width: 8, height: 8),
            "when the canvas is smaller than the grab side, the canvas is the floor and the layer fills it exactly")
    }

    func testALayerLostOffCanvasKeepsAGrabbableStripOnCanvas() {
        let pushedLeft = CanvasComposition.clampedPlacement(
            CGRect(x: -500, y: 50, width: 100, height: 100), in: canvas)
        XCTAssertEqual(pushedLeft.minX, canvas.minX - 100 + CanvasComposition.minimumGrabSide,
            "the clamped origin leaves exactly a grabbable strip on the canvas — never less")
        XCTAssertEqual(pushedLeft.maxX - canvas.minX, CanvasComposition.minimumGrabSide,
            "the strip's length is exactly minimumGrabSide: the boundary itself is legal")
        let pushedRight = CanvasComposition.clampedPlacement(
            CGRect(x: 500, y: 50, width: 100, height: 100), in: canvas)
        XCTAssertEqual(canvas.maxX - pushedRight.minX, CanvasComposition.minimumGrabSide)
        let strip = pushedLeft.intersection(canvas)
        XCTAssertEqual(strip.width, CanvasComposition.minimumGrabSide)
        XCTAssertTrue(strip.contains(CGRect(x: strip.midX, y: pushedLeft.midY, width: 1, height: 1)))
    }

    func testALayerSmallerThanTheGrabSideStaysFullyInside() {
        let clamped = CanvasComposition.clampedPlacement(
            CGRect(x: -100, y: 50, width: 10, height: 10), in: canvas)
        XCTAssertEqual(clamped, CGRect(x: 0, y: 50, width: CanvasComposition.minimumGrabSide, height: CanvasComposition.minimumGrabSide),
            "a layer floored to the grab side is clamped fully inside: it must never even hang half off the canvas")
        XCTAssertTrue(canvas.contains(clamped))
    }

    func testTheClampIsAFixedPointOfItself() {
        let rect = CGRect(x: -500, y: -500, width: 5000, height: 5000)
        let once = CanvasComposition.clampedPlacement(rect, in: canvas)
        XCTAssertEqual(CanvasComposition.clampedPlacement(once, in: canvas), once,
            "clamping a clamped placement returns it unchanged — the clamp is idempotent like the viewport's")
        // And the model's operations produce already-clamped placements.
        var composition = CanvasComposition(base: base)
        let layer = composition.append(greenSquare, at: rect)
        XCTAssertEqual(layer.placement, once)
    }

    // MARK: - Flattening

    /// "No layers means today's image": with zero layers the base's pixels
    /// must not be resampled — the flattened answer is the base itself, the
    /// same instance, and byte-identical when re-read. This protects every
    /// existing capture: an empty composition must degrade to exactly what
    /// the save path produced before this slice.
    func testFlatteningWithNoLayersReturnsTheBasePixelsUnresampled() {
        let composition = CanvasComposition(base: base)
        let flattened = composition.flattened()
        XCTAssertNotNil(flattened)
        XCTAssertTrue(flattened === base, "no layers means the base image itself, untouched — no re-render, no resample")
        XCTAssertEqual(composition.pixelSize, CGSize(width: base.width, height: base.height))
        XCTAssertEqual(bytes(of: flattened!), bytes(of: base),
            "the pixels are byte-for-byte today's image")
    }

    func testFlatteningCompositesTheLayersAtTheirPlacements() {
        var composition = CanvasComposition(base: base)
        composition.append(
            solid(green, width: 50, height: 50),
            at: CGRect(x: 250, y: 50, width: 50, height: 50)  // hanging half off the right edge
        )
        let flattened = composition.flattened()
        XCTAssertNotNil(flattened)
        XCTAssertEqual(flattened!.width, 300, "a layer hanging off the edge is clipped, never enlarges the output")
        XCTAssertEqual(flattened!.height, 200)
        XCTAssertEqual(pixel(flattened!, x: 275, y: 75), reference(green), "the layer's colour where it covers")
        XCTAssertEqual(pixel(flattened!, x: 50, y: 150), reference(red), "the base's colour where it does not")
    }

    func testFlatteningDrawsLayersInZOrder() {
        var composition = CanvasComposition(base: base)
        let bottom = composition.append(solid(red, width: 70, height: 70), at: CGRect(x: 0, y: 0, width: 100, height: 100))
        let top = composition.append(solid(blue, width: 70, height: 70), at: CGRect(x: 50, y: 50, width: 100, height: 100))
        let flattened = composition.flattened()!
        // The layers overlap at top-left (75, 75).
        XCTAssertEqual(pixel(flattened, x: 75, y: 75), reference(blue), "the later layer draws on top")
        composition.reorder(id: top.id, to: 0)
        XCTAssertEqual(
            pixel(composition.flattened()!, x: 75, y: 75), reference(red),
            "reordering the z-order is observable in the flattened pixels")
        XCTAssertEqual(composition.layers.map(\.id), [top.id, bottom.id])
    }
}
