import XCTest
import CoreGraphics
@testable import Stare
import StareCore

/// S7/T11: the pure geometry of the re-editable crop. A region is a rect in
/// the ORIGINAL capture's pixel space, so applying a crop again never cuts
/// from an already-cropped bitmap, and the crop's own journal makes undo
/// return exactly the previous region. The AppKit canvas wires gestures and
/// the palette to these rules; the rules themselves are what the tests pin.
final class CaptureCropTests: XCTestCase {

    /// The original capture, 800×600 pixels, top-left-origin pixel space.
    private let imageBounds = CGRect(x: 0, y: 0, width: 800, height: 600)

    // MARK: - Helpers

    /// The region every committed crop must satisfy: inside the image and
    /// never smaller than the minimum side, so a drag can never invert it.
    private func assertValid(
        _ region: CGRect,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            imageBounds.contains(region),
            "\(message): \(region) must stay inside \(imageBounds)",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            region.width, EditorCropRule.minimumSide,
            "\(message): \(region) must keep the minimum width",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            region.height, EditorCropRule.minimumSide,
            "\(message): \(region) must keep the minimum height",
            file: file,
            line: line
        )
    }

    // MARK: - Marquee

    func testMarqueeIsTheNormalizedRectBetweenTwoPointerPositions() {
        let forward = EditorCropRule.marquee(between: CGPoint(x: 60, y: 30), and: CGPoint(x: 120, y: 90))
        let backward = EditorCropRule.marquee(between: CGPoint(x: 120, y: 90), and: CGPoint(x: 60, y: 30))
        XCTAssertEqual(forward, CGRect(x: 60, y: 30, width: 60, height: 60))
        XCTAssertEqual(backward, forward, "the drag direction must not matter")
    }

    func testAMarqueeBelowTheMinimumSideIsNotTakeable() {
        // The old rule: a scratch drag applies no crop at all.
        let tiny = EditorCropRule.marquee(between: .zero, and: CGPoint(x: 5, y: 5))
        XCTAssertFalse(EditorCropRule.isTakeable(tiny))
        XCTAssertFalse(EditorCropRule.isTakeable(CGRect(x: 0, y: 0, width: 400, height: 4)))
        XCTAssertTrue(EditorCropRule.isTakeable(CGRect(x: 0, y: 0, width: 400, height: 300)))
    }

    // MARK: - Adjusting the applied region

    func testDraggingEachEdgeShrinksAndNeverInverts() {
        let start = CGRect(x: 100, y: 100, width: 400, height: 300)
        // Drag each edge far past its opposite side: the region must clamp to
        // the minimum instead of crossing over.
        let cases: [(CropHandle, CGPoint)] = [
            (.left, CGPoint(x: 700, y: 200)),
            (.right, CGPoint(x: 20, y: 200)),
            (.top, CGPoint(x: 300, y: 500)),
            (.bottom, CGPoint(x: 300, y: 20)),
        ]
        for (handle, pointer) in cases {
            let region = EditorCropRule.region(from: start, dragging: handle, to: pointer, in: imageBounds)
            assertValid(region, "dragging \(handle) past the opposite edge")
            if case .left = handle {
                XCTAssertEqual(region.maxX, start.maxX, "the opposite edge must not move")
            }
            if case .right = handle {
                XCTAssertEqual(region.minX, start.minX, "the opposite edge must not move")
            }
        }
    }

    func testDraggingEachEdgeGrowsClampedAtTheImageBorder() {
        let start = CGRect(x: 100, y: 100, width: 400, height: 300)
        let cases: [(CropHandle, CGPoint, CGRect)] = [
            (.left, CGPoint(x: -50, y: 200), CGRect(x: 0, y: 100, width: 500, height: 300)),
            (.right, CGPoint(x: 900, y: 200), CGRect(x: 100, y: 100, width: 700, height: 300)),
            (.top, CGPoint(x: 300, y: -50), CGRect(x: 100, y: 0, width: 400, height: 400)),
            (.bottom, CGPoint(x: 300, y: 900), CGRect(x: 100, y: 100, width: 400, height: 500)),
        ]
        for (handle, pointer, expected) in cases {
            let region = EditorCropRule.region(from: start, dragging: handle, to: pointer, in: imageBounds)
            XCTAssertEqual(region, expected, "dragging \(handle) must stop at the image border")
        }
    }

    func testDraggingEachCornerAdjustsBothSidesAndNeverInverts() {
        let start = CGRect(x: 100, y: 100, width: 400, height: 300)
        let cases: [(CropHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: -80, y: -80)),
            (.topRight, CGPoint(x: 900, y: -80)),
            (.bottomLeft, CGPoint(x: -80, y: 900)),
            (.bottomRight, CGPoint(x: 900, y: 900)),
        ]
        for (handle, pointer) in cases {
            let region = EditorCropRule.region(from: start, dragging: handle, to: pointer, in: imageBounds)
            assertValid(region, "dragging corner \(handle) outside the image")
        }
        // The opposite corner never moves.
        let topLeftDrag = EditorCropRule.region(
            from: start, dragging: .topLeft, to: CGPoint(x: -80, y: -80), in: imageBounds)
        XCTAssertEqual(topLeftDrag.maxX, start.maxX)
        XCTAssertEqual(topLeftDrag.maxY, start.maxY)
    }

    func testDraggingIntoTheInteriorRespectsTheMinimumSide() {
        let start = CGRect(x: 100, y: 100, width: 400, height: 300)
        let region = EditorCropRule.region(
            from: start, dragging: .right, to: CGPoint(x: 100 + 2, y: 200), in: imageBounds)
        XCTAssertEqual(region.width, EditorCropRule.minimumSide, "the edge stops at the minimum side")
        XCTAssertEqual(region.minX, start.minX, "the opposite edge must not move")
    }

    // MARK: - Moving the applied region

    func testMovingKeepsTheSizeAndClampsInsideTheImage() {
        let start = CGRect(x: 100, y: 100, width: 200, height: 150)
        let moved = EditorCropRule.region(from: start, movedBy: CGPoint(x: 1000, y: -800), in: imageBounds)
        XCTAssertEqual(moved, CGRect(x: 800 - 200, y: 0, width: 200, height: 150))
        assertValid(moved, "moving the region far beyond the image")
    }

    // MARK: - Clamping and snapping

    func testClampingKeepsTheRegionInsideTheImage() {
        let hanging = CGRect(x: -30, y: -30, width: 500, height: 400)
        XCTAssertEqual(EditorCropRule.clamped(hanging, in: imageBounds), CGRect(x: 0, y: 0, width: 470, height: 370))
    }

    func testSnappingKeepsTheRegionIntegralAndInsideTheImage() {
        let sloppy = CGRect(x: 10.4, y: 9.6, width: 99.6, height: 51.2)
        let snapped = EditorCropRule.snapped(sloppy, in: imageBounds)
        XCTAssertEqual(snapped, snapped.integral, "the committed region is integral pixels")
        XCTAssertTrue(imageBounds.contains(snapped))
        // A region touching the right edge must not grow past it.
        let atEdge = EditorCropRule.snapped(CGRect(x: 0, y: 0, width: 799.7, height: 600), in: imageBounds)
        XCTAssertTrue(imageBounds.contains(atEdge), "\(atEdge) grew past the image")
        XCTAssertEqual(atEdge.width, 800)
    }

    /// A6: the snap re-applies the smallest side itself, so a region the
    /// clamp squeezed below the minimum comes back takeable and in bounds
    /// — the next caller can trust it without pre-clamping.
    func testSnappingReappliesTheMinimumSideToATinyRegion() {
        let tiny = EditorCropRule.snapped(CGRect(x: 10, y: 10, width: 5, height: 5), in: imageBounds)
        XCTAssertTrue(EditorCropRule.isTakeable(tiny), "the snapped region stays takeable")
        XCTAssertTrue(imageBounds.contains(tiny))
        XCTAssertEqual(tiny, CGRect(x: 10, y: 10, width: 8, height: 8))
    }

    /// A6: a region hanging past the borders gets clamped to less than the
    /// minimum; the snap must grow it back without leaving the image.
    func testSnappingGrowsAClampSqueezedRegionBackToTheMinimumInsideTheImage() {
        let squeezed = EditorCropRule.snapped(CGRect(x: 795, y: 595, width: 30, height: 30), in: imageBounds)
        XCTAssertTrue(EditorCropRule.isTakeable(squeezed))
        XCTAssertTrue(imageBounds.contains(squeezed), "\(squeezed) must stay inside \(imageBounds)")
        XCTAssertEqual(squeezed, CGRect(x: 792, y: 592, width: 8, height: 8))
    }

    // MARK: - Handle hit-testing (view space)

    func testHandleHitFindsCornersEdgesAndNothingFarAway() {
        let region = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(
            EditorCropRule.handle(at: CGPoint(x: 100, y: 100), on: region), .topLeft)
        XCTAssertEqual(
            EditorCropRule.handle(at: CGPoint(x: 500, y: 400), on: region), .bottomRight)
        XCTAssertEqual(
            EditorCropRule.handle(at: CGPoint(x: 300, y: 100), on: region), .top)
        XCTAssertEqual(
            EditorCropRule.handle(at: CGPoint(x: 100, y: 250), on: region), .left)
        XCTAssertNil(
            EditorCropRule.handle(at: CGPoint(x: 300, y: 250), on: region),
            "the interior is not a grip: dragging there moves the region instead")
        XCTAssertNil(
            EditorCropRule.handle(at: CGPoint(x: 300, y: 20), on: region),
            "far away from every edge there is nothing to grab")
    }

    // MARK: - The mapping view ⇄ original pixels

    private let bigSpace = EditorCropSpace(
        display: CGRect(x: 10, y: 20, width: 400, height: 300),
        coverage: CGRect(x: 0, y: 0, width: 800, height: 600))
    private let smallerCropSpace = EditorCropSpace(
        display: CGRect(x: 5, y: 5, width: 400, height: 300),
        coverage: CGRect(x: 100, y: 50, width: 400, height: 300))

    func testAFittedSpaceShowsExactlyItsPixelCoverage() {
        let fitted = EditorCropSpace.fitted(coverage: smallerCropSpace.coverage, inCanvas: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(fitted.coverage, smallerCropSpace.coverage)
        XCTAssertEqual(fitted.viewRect(fromPixel: fitted.coverage), fitted.display)
        XCTAssertTrue(fitted.display.width <= 800 && fitted.display.height <= 600)
        // The aspect ratio is kept.
        XCTAssertEqual(
            fitted.display.width / fitted.display.height,
            smallerCropSpace.coverage.width / smallerCropSpace.coverage.height,
            accuracy: 0.0001)
    }

    func testPixelAndViewPointsAreExactInverses() {
        let view = CGPoint(x: 200.5, y: 130.25)
        let pixel = bigSpace.pixelPoint(fromView: view)
        // View (200.5, 130.25) sits 190.5/110.25 points into the display, so
        // at 2 px/pt it lands at (381, 220.5) in the coverage's pixels.
        XCTAssertEqual(pixel.x, 381, accuracy: 0.0001)
        XCTAssertEqual(pixel.y, 220.5, accuracy: 0.0001)
        XCTAssertEqual(bigSpace.viewPoint(fromPixel: pixel), view)
    }

    /// The rule the owner asked for: applying a crop again must cut from the
    /// original, never from the already-cropped bitmap. The canvas maps every
    /// gesture through the armed space whose coverage is the WHOLE original, so
    /// the same view marquee lands on the same original pixels no matter what
    /// the previous crop was — or how big the window is.
    func testEveryCropGestureCutsFromTheOriginalPixels() {
        let full = CGRect(x: 0, y: 0, width: 800, height: 600)
        let inSmallWindow = EditorCropSpace.fitted(coverage: full, inCanvas: CGRect(x: 0, y: 0, width: 400, height: 300))
        let inWideWindow = EditorCropSpace.fitted(coverage: full, inCanvas: CGRect(x: 0, y: 0, width: 1200, height: 500))
        // The same original region drawn as a view marquee in both windows.
        let target = CGRect(x: 200, y: 150, width: 300, height: 200)
        let smallMarquee = inSmallWindow.viewRect(fromPixel: target)
        let wideMarquee = inWideWindow.viewRect(fromPixel: target)
        func assertClose(_ actual: CGRect, _ expected: CGRect, _ message: String) {
            XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, message)
            XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, message)
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, message)
            XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, message)
        }
        assertClose(inSmallWindow.pixelRect(fromView: smallMarquee), target, "")
        assertClose(inWideWindow.pixelRect(fromView: wideMarquee), target,
                    "the window size never moves where the crop lands")
    }

    // MARK: - Marks follow their pixels

    func testAMarkRecordedInTheOldSpaceConvertsIntoTheNewRegionSpace() {
        // The mark was drawn when the view showed the whole 800×600 image at
        // 2 px per point; now the view shows a 400×300 region at 1 px/point.
        let stroke = Stroke(
            tool: .pen,
            ink: .red,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)],
            textSize: nil)
        var withSizes = stroke
        withSizes.textSize = CGSize(width: 20, height: 24)
        withSizes.badgeSize = 26
        withSizes.rotation = 0.5

        let converted = smallerCropSpace.convert(withSizes, from: bigSpace)
        // (0,0) sits at pixel (−20,−40) through the big space, which the
        // small region's view places 100 and 50 pixels before its own
        // top-left corner.
        XCTAssertEqual(converted.points[0].x, -115, accuracy: 0.0001)
        XCTAssertEqual(converted.points[0].y, -85, accuracy: 0.0001)
        XCTAssertEqual(converted.points[1].x, 85, accuracy: 0.0001)
        XCTAssertEqual(converted.points[1].y, 15, accuracy: 0.0001)
        XCTAssertEqual(converted.textSize?.width ?? 0, 40, accuracy: 0.0001, "the text box scales with the mark")
        XCTAssertEqual(converted.badgeSize ?? 0, 52, accuracy: 0.0001, "the badge scales with the mark")
        XCTAssertEqual(converted.rotation, 0.5, "rotation is metadata and stays")
        XCTAssertEqual(converted.tool, .pen)
        XCTAssertEqual(converted.ink, .red)
    }

    func testUndoingAnEmptyHistoryLeavesNothingToRoute() {
        var record = EditorCropRecord()
        XCTAssertNil(record.undo(), "nothing applied means the marks own ⌘Z")
        XCTAssertNil(record.redo())
    }

    // MARK: - The canvas really places marks where they were drawn

    /// Behavior pin behind the mapping: a mark drawn at a view point is
    /// painted at that view point, whatever inset the fitted display has.
    /// The old pipeline double-translated by the display's origin, so this is
    /// the regression guard its fix needed.
    @MainActor
    func testAMarkLandsWhereItWasDrawnWhateverTheWindowDoes() throws {
        let image = try XCTUnwrap(Self.solidImage(width: 100, height: 100))
        let canvas = CaptureEditorCanvas(image: image)
        // A 100×100 capture in a 300×200 window fits at (50, 0, 200, 200):
        // the display is inset 50 pt, exactly the offset the old rendering
        // used to shift freshly drawn marks by.
        canvas.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        let mark = Stroke(tool: .pen, ink: .red, points: [CGPoint(x: 100, y: 100), CGPoint(x: 106, y: 100)])
        canvas.seedMarks([mark])

        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 300,
            pixelsHigh: 200,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.current = context
        // AppKit pre-flips the context for a flipped view before draw(_:) is
        // called; calling draw directly has to supply that flip itself.
        context.cgContext.translateBy(x: 0, y: 200)
        context.cgContext.scaleBy(x: 1, y: -1)
        canvas.draw(canvas.bounds)
        NSGraphicsContext.restoreGraphicsState()

        func pixel(_ x: Int, _ y: Int) throws -> NSColor {
            // Bitmap rows are bottom-up; the view is top-left.
            try XCTUnwrap(rep.colorAt(x: x, y: 200 - 1 - y))
        }
        // The ink is the system red (255, 59, 48), so the stroke pixel must
        // match the ink's own components exactly.
        let stroke = try XCTUnwrap(pixel(102, 100).usingColorSpace(.deviceRGB))
        let ink = try XCTUnwrap(NSColor(cgColor: Ink.red.cgColor())?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(stroke.redComponent, ink.redComponent, accuracy: 0.05)
        XCTAssertEqual(stroke.greenComponent, ink.greenComponent, accuracy: 0.05)
        XCTAssertEqual(stroke.blueComponent, ink.blueComponent, accuracy: 0.05)
        // And 25 pt to the right of the stroke there is nothing but capture.
        let beside = try XCTUnwrap(pixel(131, 100).usingColorSpace(.deviceRGB))
        XCTAssertEqual(beside.redComponent, 1, accuracy: 0.05)
        XCTAssertEqual(beside.greenComponent, 1, accuracy: 0.05)
        XCTAssertEqual(beside.blueComponent, 1, accuracy: 0.05)
    }

    private static func solidImage(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - The crop's own undo journal

    func testUndoRestoresThePreviousRegion() {
        var record = EditorCropRecord()
        XCTAssertFalse(record.canUndo)
        record.crop(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        record.crop(to: CGRect(x: 50, y: 50, width: 200, height: 150))
        XCTAssertEqual(record.region, CGRect(x: 50, y: 50, width: 200, height: 150))

        XCTAssertTrue(record.undo() != nil, "the newest crop undoes first")
        XCTAssertEqual(record.region, CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertTrue(record.undo() != nil)
        XCTAssertNil(record.region, "undoing the first crop returns to the uncropped capture")
        XCTAssertFalse(record.canUndo)
    }

    func testRedoReappliesTheCropTheUndoTookAway() {
        var record = EditorCropRecord()
        record.crop(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        record.crop(to: CGRect(x: 50, y: 50, width: 200, height: 150))
        record.undo()
        record.undo()
        XCTAssertEqual(record.region, nil)

        XCTAssertTrue(record.redo() != nil)
        XCTAssertEqual(record.region, CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertTrue(record.redo() != nil)
        XCTAssertEqual(record.region, CGRect(x: 50, y: 50, width: 200, height: 150))
        XCTAssertFalse(record.canRedo)
    }

    func testDrawingAMarkForksTheCropRedo() {
        var record = EditorCropRecord()
        record.crop(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        record.undo()
        XCTAssertTrue(record.canRedo)
        record.noteMark()
        XCTAssertFalse(record.canRedo, "a new mark is an edit: the crop stays undone")
        XCTAssertNil(record.region)
    }

    func testClearingMarksKeepsTheCropHistory() {
        var record = EditorCropRecord()
        record.crop(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        record.noteMark()
        record.crop(to: CGRect(x: 50, y: 50, width: 200, height: 150))
        record.undo()
        record.clearMarkHistory()

        XCTAssertTrue(record.canUndo, "the crops survive the mark clear")
        XCTAssertEqual(record.region, CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertTrue(record.undo() != nil)
        XCTAssertNil(record.region)
    }

    /// A2: `redoTargets` is aligned with the crop entries of `undone` in
    /// order, never with the position in `undone` — mark steps shift that.
    /// Clearing a mixed journal must keep every crop's own redo target and
    /// never index past the array.
    func testClearingAMixedJournalKeepsEachCropItsOwnRedoTarget() {
        var record = EditorCropRecord()
        let first = CGRect(x: 0, y: 0, width: 400, height: 300)
        let second = CGRect(x: 50, y: 50, width: 200, height: 150)
        record.crop(to: first)
        record.noteMark()
        record.crop(to: second)
        record.noteMark()
        // Undo past both journal entries: the newest mark, the newest crop,
        // then the older mark — undone = [marks, crop(second), marks].
        record.undo()
        record.undo()
        record.undo()
        XCTAssertEqual(record.region, first)

        record.clearMarkHistory()
        XCTAssertEqual(record.region, first, "the crops keep their place through the clear")

        // Redo replays the surviving crop with ITS OWN target.
        guard case .crop = record.redo() else {
            return XCTFail("the crop step survives the clear, so redo must replay one")
        }
        XCTAssertEqual(record.region, second, "the surviving crop replays at its own region, never a shifted target")
        XCTAssertFalse(record.canRedo)

        // And the reverse walk re-routes them the same way, never trapping.
        guard case .crop = record.undo() else {
            return XCTFail("the replayed crop is undoable again")
        }
        XCTAssertEqual(record.region, first, "it restores the region its step names")
        guard case .crop = record.redo() else {
            return XCTFail("the crop is redoable again too")
        }
        XCTAssertEqual(record.region, second, "the round trip is stable after the clear")
        guard case .crop = record.undo() else {
            return XCTFail("the replayed crop is undoable again")
        }
        XCTAssertEqual(record.region, first)
        guard case .crop = record.undo() else {
            return XCTFail("the first crop is the oldest applied step")
        }
        XCTAssertNil(record.region, "undoing the first crop returns to the uncropped capture")
        XCTAssertFalse(record.canUndo)
    }

    /// A2, the other order: undoing into a cleared mixed journal must never
    /// trap either, and redo from there still lands every crop where its own
    /// step names.
    func testClearingAMixedJournalSurvivesUndoBeforeRedoInEveryOrder() {
        var record = EditorCropRecord()
        let first = CGRect(x: 0, y: 0, width: 400, height: 300)
        let second = CGRect(x: 50, y: 50, width: 200, height: 150)
        record.crop(to: first)
        record.noteMark()
        record.crop(to: second)
        record.noteMark()
        record.undo()
        record.undo()
        XCTAssertEqual(record.region, first)
        record.clearMarkHistory()

        // Undo the surviving step (the clear took the marks out of the way):
        // the second crop step sits on the redo side, so the newest applied
        // crop is the FIRST one — ⌘Z returns to the uncropped capture.
        guard case .crop = record.undo() else {
            return XCTFail("the surviving first crop is the newest applied step")
        }
        XCTAssertNil(record.region, "the first crop restores the uncropped capture")
        XCTAssertTrue(record.canRedo)

        // Redo from here replays the first crop at its own region, then the
        // round trip is stable.
        guard case .crop = record.redo() else {
            return XCTFail("the cleared journal still holds the crop on the redo side")
        }
        XCTAssertEqual(record.region, first, "the first crop replays at its own region")
        record.undo()
        record.redo()
        XCTAssertEqual(record.region, first, "the round trip is stable after the clear")

        // And the crop the clear left on the redo side replays at its OWN
        // region too, never a shifted target.
        guard case .crop = record.redo() else {
            return XCTFail("the cleared journal keeps the other crop redoable")
        }
        XCTAssertEqual(record.region, second, "the redo-side crop replays at its own region")
        XCTAssertFalse(record.canRedo)
    }
}
