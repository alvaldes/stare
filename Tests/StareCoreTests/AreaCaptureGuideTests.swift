import CoreGraphics
import XCTest

@testable import StareCore

/// The area drag's dotted guides (S4): the POINTER carries the crosshair —
/// one vertical and one horizontal rule through the pointer, out to THIS
/// display's edges — present from the moment area mode arms and throughout
/// the drag. Exactly one rule per axis, always the pointer's: the selection's
/// edges are never ruled, so during a drag the origin's rules cannot exist.
/// Pure geometry, decided once — the view only paints it, exactly like
/// `AreaCaptureLoupe`'s plan/paint split.
final class AreaCaptureGuideTests: XCTestCase {
    /// A display in view space (top-left origin).
    private let display = CGRect(x: 0, y: 0, width: 1000, height: 700)

    // MARK: The pointer's crosshair

    /// A pointer in the open: exactly two rules, the vertical and the
    /// horizontal through the pointer, each spanning the whole display out
    /// to its edges.
    func testThePointerCrosshairIsExactlyTwoRulesThroughThePoint() {
        let guides = AreaCaptureGuides.guides(at: CGPoint(x: 400, y: 300), bounds: display)
        XCTAssertEqual(guides.count, 2)
        // The vertical rule through the pointer runs the display's full
        // height; the horizontal its full width.
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 400, y: 0, width: 0, height: 700))))
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 0, y: 300, width: 1000, height: 0))))
        for guide in guides {
            XCTAssertTrue(display.insetBy(dx: -0.5, dy: -0.5).contains(guide.line), "every rule lives inside the display")
        }
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

    // MARK: No pointer, no room

    /// No pointer (armed before the first move lands a point), or an empty
    /// display: nothing to rule.
    func testNoPointerOrEmptyDisplayMeansNoGuides() {
        XCTAssertTrue(AreaCaptureGuides.guides(at: nil, bounds: display).isEmpty)
        XCTAssertTrue(AreaCaptureGuides.guides(
            at: CGPoint(x: 400, y: 300), bounds: CGRect.zero).isEmpty)
    }

    // MARK: The clipping (never an edge outside the display)

    /// A pointer outside the display draws nothing: both rules would sit
    /// away from the display, so neither exists.
    func testAPointerOutsideTheDisplayDrawsNothing() {
        XCTAssertTrue(AreaCaptureGuides.guides(
            at: CGPoint(x: 1500, y: 1600), bounds: display).isEmpty)
        XCTAssertTrue(AreaCaptureGuides.guides(
            at: CGPoint(x: -150, y: -160), bounds: display).isEmpty)
    }

    /// A pointer sitting exactly on a display edge drops ONLY the rule that
    /// would run along that edge: the display's own edge already says where
    /// the screen ends, and a rule there could only imply a farther edge
    /// that does not exist. The perpendicular rule keeps its place.
    func testAPointerOnADisplayEdgeDropsOnlyThatAxisRule() {
        // On the display's left edge: the vertical rule would sit exactly on
        // the boundary, so only the horizontal rule through the pointer is
        // drawn.
        let onLeft = AreaCaptureGuides.guides(at: CGPoint(x: 0, y: 300), bounds: display)
        XCTAssertEqual(onLeft.count, 1)
        XCTAssertTrue(onLeft.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 0, y: 300, width: 1000, height: 0))))
        XCTAssertFalse(onLeft.contains { $0.isVertical },
            "no vertical rule may run along the display's left edge")
        // On the display's top edge: symmetric.
        let onTop = AreaCaptureGuides.guides(at: CGPoint(x: 500, y: 0), bounds: display)
        XCTAssertEqual(onTop.count, 1)
        XCTAssertTrue(onTop.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 500, y: 0, width: 0, height: 700))))
        XCTAssertFalse(onTop.contains { $0.isHorizontal },
            "no horizontal rule may run along the display's top edge")
    }

    /// A display whose origin is not zero (a display above or left of the
    /// primary): the rules extend to THAT display's edges, never past — on a
    /// multi-display Mac there is no cross-canvas geometry.
    func testRulesRunToTheDisplay_sOwnEdgesOnAnOffOriginDisplay() {
        let offOrigin = CGRect(x: 1200, y: -300, width: 1000, height: 700)
        let guides = AreaCaptureGuides.guides(at: CGPoint(x: 1300, y: -200), bounds: offOrigin)
        XCTAssertEqual(guides.count, 2)
        // The vertical rule reaches exactly the display's top and bottom
        // edges; the horizontal its left and right.
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 1300, y: -300, width: 0, height: 700))))
        XCTAssertTrue(guides.contains(AreaCaptureGuides.Guide(
            line: CGRect(x: 1200, y: -200, width: 1000, height: 0))))
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
