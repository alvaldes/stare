import CoreGraphics
import XCTest

import StareCore

/// Independent probes derived from the whiteboard-2 request (S1, S4, S5, S6),
/// written by the verifier, not the writer. Each probe states the spec item it
/// covers and asserts only on public StareCore behaviour.
final class BoardNavigationProbeTests: XCTestCase {
    // MARK: - Helpers

    private func solid(_ w: Int, _ h: Int, _ colour: CGColor) -> CGImage {
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(colour)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// Reads a pixel with the origin at the top-left (the overlay's space).
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(
            data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let o = (y * image.width + x) * 4
        return (data[o], data[o + 1], data[o + 2])
    }

    private func close(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 1e-6) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    // MARK: - S5: page <-> view mapping round-trips everywhere

    func testP1PageViewMappingRoundTripsAtEveryZoomAndOffset() {
        let zooms: [CGFloat] = [BoardTransform.minZoom, 0.3, 0.5, 1, 1.25, 2, 3.75, BoardTransform.maxZoom]
        let offsets: [CGSize] = [
            .zero,
            CGSize(width: 123.5, height: -77.25),
            CGSize(width: -1920, height: 1080),
            CGSize(width: 960, height: 540),
        ]
        let points = [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 960, y: 540),
            CGPoint(x: 1920, y: 1080), CGPoint(x: -300.5, y: 42.75),
        ]
        for zoom in zooms {
            for offset in offsets {
                let t = BoardTransform(offset: offset, zoom: zoom)
                for p in points {
                    let round = t.point(toPage: t.point(fromPage: p))
                    XCTAssertTrue(
                        close(round, p, 1e-6),
                        "S5 round trip zoom=\(zoom) offset=\(offset) point=\(p) came back \(round)"
                    )
                }
                let rect = CGRect(x: 12.5, y: -40, width: 300, height: 175)
                let viewRect = t.rect(fromPage: rect)
                let backRect = t.rect(toPage: viewRect)
                XCTAssertEqual(backRect.minX, rect.minX, accuracy: 1e-6, "S5 rect round trip x zoom=\(zoom)")
                XCTAssertEqual(backRect.minY, rect.minY, accuracy: 1e-6, "S5 rect round trip y zoom=\(zoom)")
                XCTAssertEqual(backRect.width, rect.width, accuracy: 1e-6, "S5 rect round trip w zoom=\(zoom)")
                XCTAssertEqual(backRect.height, rect.height, accuracy: 1e-6, "S5 rect round trip h zoom=\(zoom)")
                // A view length is its page length times the zoom, both ways.
                XCTAssertEqual(t.length(fromPage: 12), 12 * zoom, accuracy: 1e-6)
                XCTAssertEqual(t.pageLength(t.length(fromPage: 12)), 12, accuracy: 1e-6)
                // Zoom scales both axes by the same factor: a square stays square.
                let a = t.rect(fromPage: CGRect(x: 0, y: 0, width: 10, height: 10))
                XCTAssertEqual(a.width, a.height, accuracy: 1e-6, "S5 the zoom must not skew zoom=\(zoom)")
            }
        }
        // The identity really is the old translation-only rule.
        let identity = BoardTransform.identity
        XCTAssertEqual(identity.point(fromPage: CGPoint(x: 40, y: 25)), CGPoint(x: 40, y: 25))
        XCTAssertEqual(identity.zoom, 1)
    }

    // MARK: - S5: anchored zoom, both ends of the range

    func testP2AnchoredZoomKeepsItsPagePointAndClampsAtBothEnds() {
        let anchor = CGPoint(x: 300, y: 200)
        let start = BoardTransform(offset: CGSize(width: 40, height: -15), zoom: 1)
        let pageUnderAnchor = start.point(toPage: anchor)

        let zoomedIn = start.zoomed(to: 8, anchoredAt: anchor)
        XCTAssertEqual(zoomedIn.zoom, 8, accuracy: 1e-9)
        XCTAssertTrue(
            close(zoomedIn.point(toPage: anchor), pageUnderAnchor, 1e-6),
            "S5 the page point under the anchor must not move when zooming in"
        )

        // At the ceiling another zoom-in changes nothing at all (no oscillation).
        XCTAssertEqual(zoomedIn.zoomed(to: 64, anchoredAt: anchor), zoomedIn, "S5 zoom above 8x must be refused")
        XCTAssertEqual(zoomedIn.zoomed(to: 8, anchoredAt: anchor), zoomedIn, "S5 a zoom that changes nothing must be a no-op")

        let zoomedOut = start.zoomed(to: 0.01, anchoredAt: anchor)
        XCTAssertEqual(zoomedOut.zoom, BoardTransform.minZoom, accuracy: 1e-9)
        XCTAssertTrue(
            close(zoomedOut.point(toPage: anchor), pageUnderAnchor, 1e-6),
            "S5 the page point under the anchor must not move when zooming out"
        )
        let floor = BoardTransform(offset: .zero, zoom: BoardTransform.minZoom)
        XCTAssertEqual(floor.zoomed(to: 0.0001, anchoredAt: anchor), floor, "S5 zoom below 0.25x must be refused")

        // Repeated steps land exactly on the two ends and never past them.
        var inSteps = BoardTransform.identity
        for _ in 0..<20 { inSteps = inSteps.zoomed(to: inSteps.zoom * BoardTransform.zoomStep, anchoredAt: anchor) }
        XCTAssertEqual(inSteps.zoom, BoardTransform.maxZoom, accuracy: 1e-9)
        var outSteps = BoardTransform.identity
        for _ in 0..<20 { outSteps = outSteps.zoomed(to: outSteps.zoom / BoardTransform.zoomStep, anchoredAt: anchor) }
        XCTAssertEqual(outSteps.zoom, BoardTransform.minZoom, accuracy: 1e-9)

        // And through the page model: a refused zoom leaves the page untouched.
        let pages = WhiteboardPages()
        pages.setOffset(CGSize(width: 17, height: 23))
        XCTAssertTrue(pages.zoom(to: 8, anchoredAt: anchor))
        let offsetAtCeiling = pages.currentPage.offset
        XCTAssertFalse(pages.zoom(to: 100, anchoredAt: anchor), "S5 a clamped zoom reports no change")
        XCTAssertEqual(pages.currentPage.zoom, 8, accuracy: 1e-9)
        XCTAssertEqual(pages.currentPage.offset, offsetAtCeiling, "S5 a refused zoom must not move the pan")
    }

    // MARK: - S5: pan at maximum zoom, reset with both off default

    func testP3PanAtMaximumZoomKeepsTheScreenDeltaAndResetClearsBoth() {
        for zoom in [BoardTransform.maxZoom, BoardTransform.minZoom, CGFloat(2)] {
            var t = BoardTransform(offset: CGSize(width: 50, height: 60), zoom: zoom)
            let p = CGPoint(x: 400, y: 300)
            let before = t.point(fromPage: p)
            // What the view does for a pointer drag: the offset moves by the
            // screen delta divided by the zoom.
            let delta = CGSize(width: 120, height: -40)
            t.offset = CGSize(
                width: t.offset.width - delta.width / t.zoom,
                height: t.offset.height - delta.height / t.zoom
            )
            let after = t.point(fromPage: p)
            XCTAssertEqual(after.x - before.x, delta.width, accuracy: 1e-6, "S5 pan must follow the pointer at zoom \(zoom)")
            XCTAssertEqual(after.y - before.y, delta.height, accuracy: 1e-6, "S5 pan must follow the pointer at zoom \(zoom)")
        }

        let pages = WhiteboardPages()
        pages.pan(by: CGSize(width: -80, height: -50))
        XCTAssertTrue(pages.zoom(to: 4, anchoredAt: CGPoint(x: 400, y: 300)))
        XCTAssertNotEqual(pages.currentPage.offset, .zero)
        XCTAssertNotEqual(pages.currentPage.zoom, 1)
        pages.resetView()
        XCTAssertEqual(pages.currentPage.transform, BoardTransform.identity, "S5 reset must clear pan and zoom together")
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.currentIndex, 0)
    }

    // MARK: - S5: the zoom belongs to its page

    func testP4ZoomAndPanBelongToTheirPage() {
        let pages = WhiteboardPages(background: .system)
        XCTAssertTrue(pages.zoom(to: 4, anchoredAt: .zero))
        pages.pan(by: CGSize(width: 11, height: 22))
        let firstZoom = pages.currentPage.zoom
        let firstOffset = pages.currentPage.offset

        XCTAssertTrue(pages.selectNext(), "S5/S6 a page past the last is created")
        XCTAssertEqual(pages.currentPage.zoom, 1, accuracy: 1e-9, "S5 a fresh page opens unzoomed")
        XCTAssertEqual(pages.currentPage.offset, .zero)
        XCTAssertEqual(pages.currentPage.background, .system, "S4 a new page inherits the system choice")

        XCTAssertTrue(pages.selectPrevious())
        XCTAssertEqual(pages.currentPage.zoom, firstZoom, accuracy: 1e-9)
        XCTAssertEqual(pages.currentPage.offset, firstOffset)
        XCTAssertEqual(pages.currentPage.transform, BoardTransform(offset: firstOffset, zoom: firstZoom))

        // ⌘B flips only the page you are on.
        pages.toggleBackground(isDark: true)
        XCTAssertEqual(pages.currentPage.background, .white, "S4 a dark-mode system page flips to explicit white")
        _ = pages.selectNext()
        XCTAssertEqual(pages.currentPage.background, .system, "S4 ⌘B must not touch the other page")
    }

    // MARK: - S6: the dot grid

    func testP5DotGridPitchIsReadableAtBothEndsAndCoversTheRect() {
        // Pitch in page points, and the screen pitch it produces.
        XCTAssertEqual(DotGrid.pageSpacing(atZoom: BoardTransform.minZoom) * BoardTransform.minZoom,
                       DotGrid.minimumScreenSpacing, accuracy: 1e-9, "S6 the pitch must stay readable at 0.25x")
        XCTAssertEqual(DotGrid.pageSpacing(atZoom: 1), DotGrid.spacing, accuracy: 1e-9)
        let pitchAtMax = DotGrid.pageSpacing(atZoom: BoardTransform.maxZoom)
        XCTAssertEqual(pitchAtMax * BoardTransform.maxZoom, DotGrid.spacing * BoardTransform.maxZoom, accuracy: 1e-9)
        XCTAssertLessThan(pitchAtMax, DotGrid.spacing * 2, "S6 the coarsening must not keep doubling at 8x")

        // Every zoom in range keeps a readable pitch and never grows the count.
        var zoom = BoardTransform.minZoom
        while zoom <= BoardTransform.maxZoom {
            let pitch = DotGrid.pageSpacing(atZoom: zoom)
            XCTAssertGreaterThanOrEqual(pitch * zoom, DotGrid.minimumScreenSpacing - 1e-9, "S6 mush at zoom \(zoom)")
            var ratio = pitch / DotGrid.spacing
            while ratio > 1.001 { XCTAssertEqual(ratio.truncatingRemainder(dividingBy: 2), 0, accuracy: 1e-9, "S6 pitch must double"); ratio /= 2 }
            zoom *= 1.1
        }
        // A 900x600pt rect of page space at the coarse end: the count follows
        // the pitch the coarsening chose, never more.
        let pageRect = CGRect(x: 0, y: 0, width: 900, height: 600)
        let coarse = DotGrid.dots(in: pageRect, zoom: BoardTransform.minZoom)
        let fine = DotGrid.dots(in: pageRect, zoom: BoardTransform.maxZoom)
        XCTAssertEqual(coarse.count, 19 * 13, "S6 900x600pt on the 48pt pitch at 0.25x: 19x13 dots")
        XCTAssertEqual(fine.count, 38 * 25, "S6 900x600pt on the 24pt pitch: 38x25 dots (the max edge is excluded)")

        // Dots sit on the page-space pitch anchored at the page origin, inside the rect.
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let dots = DotGrid.dots(in: rect, spacing: 24)
        XCTAssertEqual(dots.count, 16, "S6 a 100x100pt rect on a 24pt pitch holds 16 dots (100/24: 100,124,148,172)")
        for dot in dots {
            XCTAssertEqual(dot.x.truncatingRemainder(dividingBy: 24), 0, accuracy: 1e-9)
            XCTAssertEqual(dot.y.truncatingRemainder(dividingBy: 24), 0, accuracy: 1e-9)
            XCTAssertTrue(rect.contains(dot), "S6 a dot outside the rect would smear the paint")
        }
        // A dot pans and zooms with the content: the same page dot moves in the view.
        let t = BoardTransform(offset: CGSize(width: 30, height: 20), zoom: 2)
        let dot = dots[0]
        XCTAssertEqual(t.point(fromPage: dot).x, (dot.x - 30) * 2, accuracy: 1e-9)

        // Degenerate inputs paint nothing rather than crashing or looping.
        XCTAssertTrue(DotGrid.dots(in: CGRect(x: 0, y: 0, width: 0, height: 0), spacing: 24).isEmpty)
        XCTAssertTrue(DotGrid.dots(in: rect, spacing: 0).isEmpty)
        XCTAssertTrue(DotGrid.dots(in: rect, spacing: .nan).isEmpty)
        XCTAssertTrue(DotGrid.dots(in: rect, spacing: -24).isEmpty)
        XCTAssertEqual(DotGrid.pageSpacing(atZoom: 0), DotGrid.spacing, "S6 zoom 0 falls back to the base pitch")
        XCTAssertEqual(DotGrid.pageSpacing(atZoom: .nan), DotGrid.spacing)
        XCTAssertEqual(DotGrid.pageSpacing(atZoom: -1), DotGrid.spacing)
    }

    // MARK: - S1: the board's blur diffs the board's own content

    /// A solid block of black ink: one opaque pen stroke (3pt wide) sweeping
    /// horizontally across the patch area at 0.5pt spacing, so a sample in the
    /// middle is unambiguously ink and not page at any zoom.
    private func inkBlock(from: CGFloat, to: CGFloat) -> Stroke {
        var points: [CGPoint] = []
        var y: CGFloat = 60
        while y <= 140 { points.append(CGPoint(x: from, y: y)); points.append(CGPoint(x: to, y: y)); y += 0.5 }
        return Stroke(tool: .pen, ink: .black, points: points)
    }

    func testP6BoardBlurDiffusesTheMarksPaintedBeforeItAndNothingElse() {
        let page = solid(200, 200, CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let cover = inkBlock(from: 10, to: 190)
        let blur = Stroke(tool: .blur, ink: .red, points: [CGPoint(x: 60, y: 80), CGPoint(x: 140, y: 120)])

        // Board path: the patch diffuses the ink block painted before it.
        let board = MarkCompositor.composite(marks: [cover, blur], over: page, scale: 1, diffusesContent: true)!
        let inside = pixel(board, 100, 100)
        XCTAssertLessThan(inside.r, 120, "S1 the patch must diffuse the block painted before it, got \(inside)")
        XCTAssertLessThan(inside.g, 120, "S1 the patch must diffuse the block painted before it, got \(inside)")

        // Drawing-overlay path (no `diffusesContent`): the same marks crop the
        // base instead, so the patch is the page colour — the real screen
        // pixels — and the ink block is not in it.
        let overlay = MarkCompositor.composite(marks: [cover, blur], over: page, scale: 1)!
        let overlayInside = pixel(overlay, 100, 100)
        XCTAssertGreaterThan(overlayInside.r, 240, "S1 the drawing overlay must still crop the base, got \(overlayInside)")

        // A mark painted after the blur stays sharp over the patch.
        let after = Stroke(tool: .pen, ink: .blue, points: [CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100)])
        let board2 = MarkCompositor.composite(marks: [cover, blur, after], over: page, scale: 1, diffusesContent: true)!
        let sharp = pixel(board2, 100, 100)
        XCTAssertLessThan(sharp.r, 60, "S1 a mark painted after the blur stays sharp, got \(sharp)")
        XCTAssertGreaterThan(sharp.b, 200, "S1 a mark painted after the blur keeps its ink, got \(sharp)")

        // No mark beneath: the patch is the page colour diffused — never a
        // frame, never the desk (the compositor has no frame parameter at all).
        let empty = MarkCompositor.composite(marks: [blur], over: page, scale: 1, diffusesContent: true)!
        let plain = pixel(empty, 100, 100)
        XCTAssertGreaterThan(plain.r, 240, "S1 a blur over empty page diffuses the page colour, got \(plain)")

        // On a zoomed, panned page the patch lands where the board shows it.
        let big = solid(600, 600, CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let t = BoardTransform(offset: CGSize(width: 40, height: 20), zoom: 4)
        let panned = MarkCompositor.composite(
            marks: [cover, blur], over: big, scale: 1, diffusesContent: true,
            offset: t.offset, zoom: t.zoom
        )!
        let viewCentre = t.point(fromPage: CGPoint(x: 100, y: 100))
        let atView = pixel(panned, Int(viewCentre.x), Int(viewCentre.y))
        XCTAssertLessThan(atView.r, 120, "S1 the diffused patch must be where the view shows it, got \(atView)")
        // ... and not at its untransformed page position.
        let atPage = pixel(panned, 100, 100)
        XCTAssertGreaterThan(atPage.r, 240, "S1 the patch must not stay at its stored page point, got \(atPage)")
    }

    // MARK: - S5: the selection chrome keeps its screen size

    func testP7SelectionHandlesKeepSheetSizeAtEveryZoom() {
        let stroke = Stroke(
            tool: .rectangle, ink: .red,
            points: [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200)]
        )
        let selection = MarkSelection(stroke: stroke)
        for zoom in [BoardTransform.minZoom, 0.5, 1, 2, BoardTransform.maxZoom] {
            let handleSize = MarkSelection.defaultHandleSize / zoom   // what the view passes
            // The drawn chrome takes its corner from the mark's own bounds.
            let corner = selection.handlePoints(
                rotationHandleOffset: MarkSelection.defaultRotationHandleOffset
            )[.bottomRight]!
            XCTAssertEqual(
                selection.handle(at: corner, handleSize: handleSize), .bottomRight,
                "S5 the drawn corner must be grabbable at zoom \(zoom)"
            )
            // The reach is the drawn size in screen points: 7 screen points
            // outside the corner (7/zoom in page units) is no longer the corner.
            let outside = selection.handle(
                at: CGPoint(x: corner.x + 7 / zoom, y: corner.y), handleSize: handleSize
            )
            XCTAssertNotEqual(outside, .bottomRight, "S5 the reach must be screen-sized at zoom \(zoom)")
            // The rotation knob sits where the view draws it (page offset 20),
            // so a click there turns the mark at every zoom.
            let knob = selection.handlePoints(rotationHandleOffset: MarkSelection.defaultRotationHandleOffset)[.rotation]!
            XCTAssertEqual(selection.handle(at: knob, handleSize: handleSize), .rotation,
                           "S5 the rotation knob must turn the mark at zoom \(zoom)")
            // Characterisation of the geometry the view draws: the knob's
            // distance from the box is NOT divided by the zoom (the draw call
            // passes the unscaled default), so its on-screen distance grows
            // with the zoom.
            let screenDistance = (selection.unrotatedBounds.minY - knob.y) * zoom
            print("PROBE rotation-knob screen distance at zoom \(zoom): \(screenDistance)pt")
        }
    }

    // MARK: - S4: the system page colour

    func testP8SystemBackgroundFollowsTheAppearanceEverywhere() {
        XCTAssertEqual(BoardBackground.system.resolved(isDark: false), .white)
        XCTAssertEqual(BoardBackground.system.resolved(isDark: true), .black)
        XCTAssertEqual(BoardBackground.white.resolved(isDark: true), .white)
        XCTAssertEqual(BoardBackground.black.resolved(isDark: false), .black)

        // The capture base follows the appearance too — never transparent.
        let dark = BoardBackground.system.captureBase(width: 8, height: 8, isDark: true)!
        let light = BoardBackground.system.captureBase(width: 8, height: 8, isDark: false)!
        XCTAssertEqual(pixel(dark, 4, 4).r, 0, "S4 a dark system page captures black")
        XCTAssertEqual(pixel(light, 4, 4).r, 255, "S4 a light system page captures white")

        // ⌘B from a system page lands on an explicit colour from either appearance.
        let lightPages = WhiteboardPages(background: .system)
        lightPages.toggleBackground(isDark: false)
        XCTAssertEqual(lightPages.currentPage.background, .black, "S4 ⌘B on a light system page lands on black")
        XCTAssertEqual(WhiteboardPages(background: .system).currentPage.background, .system)

        let darkPages = WhiteboardPages(background: .system)
        darkPages.toggleBackground(isDark: true)
        XCTAssertEqual(darkPages.currentPage.background, .white, "S4 ⌘B on a dark system page lands on white")
        darkPages.toggleBackground(isDark: true)
        XCTAssertEqual(darkPages.currentPage.background, .black, "S4 an explicit page just flips")

        // The stored value stays what the user chose.
        XCTAssertEqual(BoardBackground(rawValue: BoardBackground.system.rawValue), .system)
        XCTAssertEqual(BoardBackground.system.displayName, "Follow the system")
    }
}
