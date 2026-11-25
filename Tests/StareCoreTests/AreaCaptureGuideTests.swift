import CoreGraphics
import XCTest

@testable import StareCore

/// The area drag's dotted guides (S1): each of the selection's four edges
/// extends out to THE DISPLAY'S edges as a thin dotted rule, so the eye can
/// follow a line to the edge before committing. Pure geometry, decided once —
/// the view only paints it, exactly like `AreaCaptureLoupe`'s plan/paint
/// split. Everything computes from the selection's own rect alone (S3): the
/// rect `selectionRect` holds at mouse-up is what the capture crops with, so
/// the guides can never promise an edge the capture does not take.
final class AreaCaptureGuideTests: XCTestCase {
    /// A display in view space (top-left origin).
    private let display = CGRect(x: 0, y: 0, width: 1000, height: 700)

    // MARK: Which edges get a rule

    /// A selection in the open: each of its four edges yields the two rays on
    /// either side of it, out to the display's edges — eight rules in all.
    func testEachOfTheSelectionsFourEdgesExtendsToTheDisplayEdges() {
        let rect = CGRect(x: 100, y: 100, width: 300, height: 200)
        let guides = AreaCaptureGuides.guides(for: rect, bounds: display)
        XCTAssertEqual(guides.count, 8)
        // The left edge's ray above and below the selection.
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 100, y: 0, width: 0, height: 100))))
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 100, y: 300, width: 0, height: 400))))
        // The right edge's rays.
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 400, y: 0, width: 0, height: 100))))
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 400, y: 300, width: 0, height: 400))))
        // The top edge's rays, left and right of the selection.
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 0, y: 100, width: 100, height: 0))))
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 400, y: 100, width: 600, height: 0))))
        // The bottom edge's rays.
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 0, y: 300, width: 100, height: 0))))
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 400, y: 300, width: 600, height: 0))))
    }

    /// The type answers the painter's shape questions directly: a rule is
    /// vertical or horizontal, never both, never neither.
    func testARuleKnowsItsOrientation() {
        let vertical = AreaCaptureGuides.Guide(line: CGRect(x: 7, y: 0, width: 0, height: 50))
        let horizontal = AreaCaptureGuides.Guide(line: CGRect(x: 0, y: 7, width: 50, height: 0))
        XCTAssertTrue(vertical.isVertical)
        XCTAssertFalse(vertical.isHorizontal)
        XCTAssertTrue(horizontal.isHorizontal)
        XCTAssertFalse(horizontal.isVertical)
    }

    // MARK: Before a rect exists

    /// The guides never follow the pointer before a rect exists: a pointer
    /// without a selection edge has nothing to extend, and a line not tied to
    /// `selectionRect` could promise an edge the capture never takes (S3).
    /// `nil` (no drag yet drawn) and the degenerate empty rect (mouse down
    /// before the first move) both answer no guides.
    func testNoRectMeansNoGuides() {
        XCTAssertTrue(AreaCaptureGuides.guides(for: nil, bounds: display).isEmpty)
        XCTAssertTrue(AreaCaptureGuides.guides(for: CGRect.zero, bounds: display).isEmpty)
        XCTAssertTrue(AreaCaptureGuides.guides(
            for: CGRect(x: 100, y: 100, width: 0, height: 0), bounds: display
        ).isEmpty)
    }

    // MARK: The clipping (never an edge outside the display)

    /// An edge coincident with a display edge gets no rule: the display's own
    /// edge already says where the capture ends, and a rule there would imply
    /// a farther edge that does not exist. The other edges keep theirs.
    func testAnEdgeOnTheDisplayEdgeGetsNoRule() {
        let flushLeft = CGRect(x: 0, y: 100, width: 300, height: 200)
        let guides = AreaCaptureGuides.guides(for: flushLeft, bounds: display)
        XCTAssertEqual(guides.count, 4, "the three off-display-edge edges keep their room-side rays; five zero-length or edge-coincident rays drop out")
        XCTAssertFalse(
            guides.contains { $0.line.minX == 0 },
            "no vertical rule may run along the display's left edge")
        for guide in guides {
            XCTAssertTrue(display.insetBy(dx: -0.5, dy: -0.5).contains(guide.line), "every rule lives inside the display")
        }
    }

    /// A rect that covers the whole display has no room left for a rule: the
    /// guides degenerate to nothing instead of painting over the bezel.
    func testAWholeDisplaySelectionDrawsNothing() {
        XCTAssertTrue(AreaCaptureGuides.guides(for: display, bounds: display).isEmpty)
    }

    /// A stray drag event can land a hair outside the display; the guides are
    /// computed from the rect CLIPPED to the display, so a rule can never run
    /// past it and imply an edge outside.
    func testASelectionOverhangingTheDisplayIsClippedToIt() {
        let overhanging = CGRect(x: 40, y: -50, width: 300, height: 400)
        let guides = AreaCaptureGuides.guides(for: overhanging, bounds: display)
        // Clipped to (40, 0, 300, 350): the left and right edges have no room
        // above the display's top (their upper rays degenerate), so only their
        // lower rays and the bottom edge's rays remain — four rules in all.
        XCTAssertEqual(guides.count, 4)
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 40, y: 350, width: 0, height: 350))))
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 340, y: 350, width: 0, height: 350))))
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 0, y: 350, width: 40, height: 0))))
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 340, y: 350, width: 660, height: 0))))
        // Not one rule leaves the display.
        for guide in guides {
            XCTAssertTrue(display.insetBy(dx: -0.5, dy: -0.5).contains(guide.line), "every rule lives inside the display")
        }
    }

    /// A rect missing the display entirely has nothing to draw.
    func testASelectionMissingTheDisplayDrawsNothing() {
        XCTAssertTrue(AreaCaptureGuides.guides(
            for: CGRect(x: 1500, y: 100, width: 50, height: 50), bounds: display
        ).isEmpty)
    }

    /// A display whose origin is not zero (a display above or left of the
    /// primary): the rules extend to THAT display's edges, never past — on a
    /// multi-display Mac there is no cross-canvas geometry.
    func testRulesRunToTheDisplay_sOwnEdgesOnAnOffOriginDisplay() {
        let offOrigin = CGRect(x: 1200, y: -300, width: 1000, height: 700)
        let rect = CGRect(x: 1300, y: -200, width: 300, height: 200)
        let guides = AreaCaptureGuides.guides(for: rect, bounds: offOrigin)
        XCTAssertEqual(guides.count, 8)
        // The left edge's upper ray reaches exactly the display's top edge.
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 1300, y: -300, width: 0, height: 100))))
        // And no rule ever leaves the display.
        for guide in guides {
            XCTAssertTrue(offOrigin.insetBy(dx: -0.5, dy: -0.5).contains(guide.line))
        }
    }

    // MARK: The paint constants the view strokes with

    func testThePaintConstantsStaySubdued() {
        XCTAssertEqual(AreaCaptureGuides.lineWidth, 1)
        XCTAssertEqual(AreaCaptureGuides.dotLength, 1)
        XCTAssertEqual(AreaCaptureGuides.gapLength, 3)
    }
}
