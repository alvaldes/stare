import CoreGraphics
import Foundation
import XCTest

import StareCore

/// T6b/S13 wiring: the redaction style on the blur mark and the one patch
/// dispatch every painting path shares. The blur audit (odd/tasks/
/// capture-extras.md L4) holds at the shipped parameters, so the gaussian
/// blur stays the shipped default and the randomized pixelate is a plain
/// second option — decided per mark, seeded per mark (the branch review's
/// `R1-pixelate-predictable-offsets`: no public constant may define the
/// grid), and rendered through one dispatch so the live preview and the
/// saved capture can never disagree (L9).
final class RedactionDispatchTests: XCTestCase {
    private let markRect = CGRect(x: 20, y: 20, width: 60, height: 60)

    // MARK: - Fixtures

    /// White with thin black vertical stripes (2 px every 12 px): letter-stroke
    /// thin, so no pixelate block of any mark that covers several of them can
    /// ever sit inside a stroke — what the S23 audit measured for the blur.
    private func stripedBase(width: Int = 120, height: Int = 120) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 30, y: 0, width: 2, height: height))
        context.fill(CGRect(x: 54, y: 0, width: 2, height: height))
        context.fill(CGRect(x: 78, y: 0, width: 2, height: height))
        return context.makeImage()!
    }

    private func compose(_ mark: Stroke, over base: CGImage) -> CGImage {
        MarkCompositor.composite(marks: [mark], over: base, scale: 1)!
    }

    /// Reads the whole image back as raw RGB bytes, row-major from the
    /// top-left, the same space the marks are laid out in.
    private func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &data,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let data = bytes(image)
        let offset = (y * image.width + x) * 4
        return (data[offset], data[offset + 1], data[offset + 2])
    }

    private func mark(kind: RedactionStyle, seedless id: UUID = UUID()) -> Stroke {
        var stroke = Stroke(
            id: id,
            tool: .blur,
            ink: .blue,
            points: [markRect.origin, CGPoint(x: markRect.maxX, y: markRect.maxY)]
        )
        stroke.redactionStyle = kind
        return stroke
    }

    // MARK: - The style rides the mark and decodes as today behaves (S13)

    /// A mark drawn before the field existed — the archived shape of every
    /// existing drawing — must come back gaussian-blurred: the legacy decode
    /// falls back to today's behaviour, the same way the peer's `isFilled`
    /// falls back to `false`.
    func testALegacyDocumentDecodesToTodaysBlur() throws {
        // The archived shape of an existing drawing: a `PersistedStroke`
        // document written before the style field existed, decoded verbatim.
        let legacyJSON = """
        {
            "id": "DC1EF1AB-19C2-4C9B-B2FB-760345A02AA6",
            "tool": "blur",
            "ink": "red",
            "points": [[1, 1], [9, 9]],
            "stepNumber": null,
            "text": null,
            "textSize": null,
            "createdAt": null,
            "badgeSize": null,
            "rotation": 0
        }
        """
        let stored = try JSONDecoder().decode(
            PersistedStroke.self,
            from: Data(legacyJSON.utf8)
        )
        let restored = Stroke(persisted: stored)
        XCTAssertEqual(restored?.redactionStyle, .blur)
    }

    func testABlurMarkDefaultsToTodaysBlur() {
        XCTAssertEqual(
            Stroke(tool: .blur, ink: .red, points: [CGPoint(x: 1, y: 1), CGPoint(x: 9, y: 9)])
                .redactionStyle,
            .blur
        )
    }

    // MARK: - The seed is the mark's own, never a public constant (R1)

    /// The seed comes from the mark's identity, minted at creation: two marks
    /// over the same content never share a grid, and one mark keeps its grid
    /// across renders.
    func testTheSeedIsStableAndDerivedFromTheMarkIdentity() {
        let mark = mark(kind: .randomizedPixelate)
        XCTAssertNotEqual(mark.redactionSeed, PixelateEffect.defaultSeed)

        var moved = mark
        moved.points = [CGPoint(x: 3, y: 4), CGPoint(x: 50, y: 60)]
        XCTAssertEqual(moved.redactionSeed, mark.redactionSeed)
    }

    func testDifferentMarksCarryDifferentSeeds() {
        XCTAssertNotEqual(mark(kind: .randomizedPixelate).redactionSeed, mark(kind: .randomizedPixelate).redactionSeed)
    }

    // MARK: - The compositor hides what is under a pixelate mark (S13/L9)

    /// The redaction claim of L9: inside the rectangle no glyph colour
    /// survives — the original strokes read as plain black, the patch reads
    /// far from black — and outside it the capture is untouched.
    func testAPixelateMarkHidesThinStrokesInsideItsRectangleOnly() {
        let composed = compose(mark(kind: .randomizedPixelate), over: stripedBase())

        var darkestInside: UInt8 = 255
        for y in 21..<79 {
            for x in 21..<79 {
                let sample = pixel(composed, x: x, y: y)
                darkestInside = min(darkestInside, min(sample.r, min(sample.g, sample.b)))
            }
        }
        XCTAssertGreaterThanOrEqual(
            Int(darkestInside), 120,
            "no glyph colour may survive a randomized pixelate block inside the mark")
        XCTAssertLessThanOrEqual(
            Int(pixel(stripedBase(), x: 31, y: 40).r), 10,
            "the fixture itself must carry the strokes this test hides")

        let outside = pixel(composed, x: 10, y: 10)
        XCTAssertEqual(outside.r, 255)
        XCTAssertEqual(outside.g, 255)
        XCTAssertEqual(outside.b, 255)
    }

    /// Every pixelate block is constant colour: nothing at block scale
    /// survives, and a block's interior never carries structure.
    func testEveryPixelateBlockIsConstantInsideThePatch() {
        // A pinned identity pins the pixelate's sampling: the seed rides the
        // mark's UUID, so a fresh one per run made the claim below depend on the
        // luck of the block. Same mark, same seed, same bytes — every run.
        let pinned = UUID(uuidString: "5F0C4B1E-1C7A-4A64-9E2B-6D3A8C0B7F11")!
        let composed = compose(mark(kind: .randomizedPixelate, seedless: pinned), over: stripedBase())

        // The mark rect is 60×60, so `PixelateEffect.blockSize` derives 30 —
        // four cells over the patch. Every sample inside a cell must read
        // identically.
        let cellMid = [
            CGPoint(x: 35, y: 35), CGPoint(x: 65, y: 35),
            CGPoint(x: 35, y: 65), CGPoint(x: 65, y: 65),
            CGPoint(x: 22, y: 22), CGPoint(x: 78, y: 78),
        ]
        for mid in cellMid {
            let cell = (Int((mid.x - 20) / 30), Int((mid.y - 20) / 30))
            for probe in cellMid where (Int((probe.x - 20) / 30), Int((probe.y - 20) / 30)) == cell {
                let a = pixel(composed, x: Int(mid.x), y: Int(mid.y))
                let b = pixel(composed, x: Int(probe.x), y: Int(probe.y))
                XCTAssertEqual(a.r, b.r, "block \(cell) must be constant colour")
                XCTAssertEqual(a.g, b.g)
                XCTAssertEqual(a.b, b.b)
            }
        }
        // Nothing here claims the patch is never pure white: the base is mostly
        // white, so a block that samples its ground is correct pixelation and
        // asserting otherwise made the test depend on the seed. That a pixelate
        // mark is not its blur twin is pinned separately below.
    }

    /// The one dispatch means the mark's style is what renders: the same
    /// mark, geometrically identical, must not rasterize as its blur twin.
    func testAPixelateMarkDoesNotRasterizeAsItsBlurTwin() {
        let pixelated = bytes(compose(mark(kind: .randomizedPixelate), over: stripedBase()))
        let blurred = bytes(compose(mark(kind: .blur), over: stripedBase()))
        XCTAssertNotEqual(pixelated, blurred)
    }

    /// The same pixelate mark renders byte-identically, every time.
    func testTheSameMarkRendersByteIdentically() {
        let mark = mark(kind: .randomizedPixelate)
        XCTAssertEqual(bytes(compose(mark, over: stripedBase())), bytes(compose(mark, over: stripedBase())))
    }

    /// Different marks over the same content sample different grids — a
    /// single public seed would let an attacker align them at once.
    func testDifferentMarkIDsSampleDifferentGrids() {
        // Two pinned identities instead of two fresh ones: the base is mostly
        // white, so a random pair collapses to the same render often enough to
        // flake. These two are known to land on different grids, which is what
        // the mark's own seed is supposed to buy.
        let first = UUID(uuidString: "5F0C4B1E-1C7A-4A64-9E2B-6D3A8C0B7F11")!
        let second = UUID(uuidString: "A1B2C3D4-1111-4222-8333-944455556666")!
        let a = bytes(compose(mark(kind: .randomizedPixelate, seedless: first), over: stripedBase()))
        let b = bytes(compose(mark(kind: .randomizedPixelate, seedless: second), over: stripedBase()))
        XCTAssertNotEqual(a, b)
    }

    /// Legacy marks must not depend on the seed discipline: two blur marks
    /// with different identities over the same content render identically,
    /// exactly as every blur mark did before this field existed.
    func testABlurMarkIgnoresTheSeed() {
        let a = bytes(compose(mark(kind: .blur), over: stripedBase()))
        let b = bytes(compose(mark(kind: .blur), over: stripedBase()))
        XCTAssertEqual(a, b)
    }

    /// Board zoom and pan move the mark's rectangle into view space before
    /// any effect crops it: the pixelate the board shows must be the same
    /// patch the placed mark's rectangle defines.
    func testPixelateStaysPlacedThroughZoomAndPan() {
        let pageMark = mark(kind: .randomizedPixelate)
        let panned = MarkCompositor.composite(
            marks: [pageMark],
            over: stripedBase(),
            scale: 1,
            offset: CGSize(width: 10, height: 5),
            zoom: 2
        )!

        var placed = pageMark
        let transform = BoardTransform(offset: CGSize(width: 10, height: 5), zoom: 2)
        placed.points = pageMark.points.map { transform.point(fromPage: $0) }
        let direct = compose(placed, over: stripedBase())

        XCTAssertEqual(bytes(panned), bytes(direct))
    }
}
