import CoreGraphics
import XCTest
@testable import StareCore

/// The area drag's magnifier (S11, T2b slice B): where the loupe sits around
/// the pointer — never covering the pixel being chosen, flipping to the other
/// side near a display edge, clamped inside the display — and which pixels of
/// the frozen frame it magnifies. Pure decisions; the view only paints them.
final class AreaCaptureLoupeTests: XCTestCase {
    /// A display in view space (top-left origin), big enough that the shipped
    /// loupe fits comfortably.
    private let display = CGRect(x: 0, y: 0, width: 1000, height: 700)
    /// The frozen frame is a native capture: two pixels per view point.
    private let framePixels = CGSize(width: 2000, height: 1400)
    private let pixelsPerPoint: CGFloat = 2

    // MARK: Placement

    func testTheLoupeHangsBelowRightOfThePointerWithoutCoveringIt() {
        let frame = AreaCaptureLoupe.frame(
            around: CGPoint(x: 500, y: 350), bounds: display)
        XCTAssertEqual(frame, CGRect(x: 524, y: 374, width: 120, height: 120))
        XCTAssertFalse(
            frame.contains(CGPoint(x: 500, y: 350)),
            "the loupe must never cover the pixel being chosen")
    }

    func testNearTheRightEdgeItFlipsToTheLeft() {
        let frame = AreaCaptureLoupe.frame(
            around: CGPoint(x: 990, y: 350), bounds: display)
        XCTAssertEqual(frame, CGRect(x: 846, y: 374, width: 120, height: 120))
        XCTAssertLessThanOrEqual(frame.maxX, display.maxX, "still inside the display")
    }

    func testNearTheBottomEdgeItFlipsAbove() {
        let frame = AreaCaptureLoupe.frame(
            around: CGPoint(x: 500, y: 690), bounds: display)
        XCTAssertEqual(frame, CGRect(x: 524, y: 546, width: 120, height: 120))
        XCTAssertLessThanOrEqual(frame.maxY, display.maxY, "still inside the display")
    }

    func testNearTheBottomRightCornerItFlipsBothAxes() {
        let frame = AreaCaptureLoupe.frame(
            around: CGPoint(x: 990, y: 690), bounds: display)
        XCTAssertEqual(frame, CGRect(x: 846, y: 546, width: 120, height: 120))
    }

    func testWhenNeitherSideFitsTheLoupeIsClampedInsideTheDisplay() {
        let narrow = CGRect(x: 0, y: 0, width: 130, height: 700)
        let frame = AreaCaptureLoupe.frame(
            around: CGPoint(x: 65, y: 350), bounds: narrow)
        XCTAssertEqual(frame, CGRect(x: 0, y: 374, width: 120, height: 120))
        XCTAssertTrue(narrow.contains(frame), "clamped, never outside")
    }

    func testALoupeSideLargerThanTheDisplayShrinksToFit() {
        let tiny = CGRect(x: 0, y: 0, width: 80, height: 80)
        let frame = AreaCaptureLoupe.frame(
            around: CGPoint(x: 40, y: 40), bounds: tiny)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 80, height: 80))
    }

    // MARK: Source and projection

    func testAPointerInTheOpenMagnifiesTheSquareAroundItCentredInTheLoupe() {
        let plan = AreaCaptureLoupe.plan(
            at: CGPoint(x: 500, y: 350),
            bounds: display,
            framePixelSize: framePixels,
            pixelsPerPoint: pixelsPerPoint
        )
        let planValue = try! XCTUnwrap(plan)
        // The loupe sits below-right with the shipped gap.
        XCTAssertEqual(planValue.frame, CGRect(x: 524, y: 374, width: 120, height: 120))
        // Source: `side / magnification` points centred on the pointer, in
        // frame pixel coordinates (bottom-left origin): 30 pt around
        // (500, 350) → pixels (970, 670, 60, 60).
        XCTAssertEqual(planValue.source, CGRect(x: 970, y: 670, width: 60, height: 60))
        // Unclamped, the source lands exactly on the loupe.
        XCTAssertEqual(planValue.destination, planValue.frame)
        // The pointer's pixel sits at the loupe's centre, where the crosshair
        // marks the exact edge being chosen.
        XCTAssertEqual(planValue.crosshair, CGPoint(x: 584, y: 434))
    }

    func testNearTheRightEdgeTheSourceClampsToTheFrameAndTheLoupeStaysUnstretched() {
        let plan = try! XCTUnwrap(AreaCaptureLoupe.plan(
            at: CGPoint(x: 995, y: 350),
            bounds: display,
            framePixelSize: framePixels,
            pixelsPerPoint: pixelsPerPoint
        ))
        // The loupe flips left of the pointer.
        XCTAssertEqual(plan.frame, CGRect(x: 851, y: 374, width: 120, height: 120))
        // The source reaches the frame's right edge and no further.
        XCTAssertEqual(plan.source, CGRect(x: 1960, y: 670, width: 40, height: 60))
        // Only the pixels that exist are magnified (80 pt wide, never
        // stretched over the full loupe); the pointer stays centred.
        XCTAssertEqual(plan.destination, CGRect(x: 851, y: 374, width: 80, height: 120))
        XCTAssertEqual(plan.crosshair, CGPoint(x: 911, y: 434))
    }

    func testNearTheLeftEdgeTheEmptySideIsOnTheLeft() {
        let plan = try! XCTUnwrap(AreaCaptureLoupe.plan(
            at: CGPoint(x: 8, y: 350),
            bounds: display,
            framePixelSize: framePixels,
            pixelsPerPoint: pixelsPerPoint
        ))
        XCTAssertEqual(plan.frame, CGRect(x: 32, y: 374, width: 120, height: 120))
        XCTAssertEqual(plan.source, CGRect(x: 0, y: 670, width: 46, height: 60))
        XCTAssertEqual(plan.destination, CGRect(x: 60, y: 374, width: 92, height: 120))
        XCTAssertEqual(plan.crosshair, CGPoint(x: 92, y: 434))
    }

    func testAPointerTooFarOutsideTheDisplayHasNoPlan() {
        XCTAssertNil(AreaCaptureLoupe.plan(
            at: CGPoint(x: 1200, y: 350),
            bounds: display,
            framePixelSize: framePixels,
            pixelsPerPoint: pixelsPerPoint
        ))
        XCTAssertNil(AreaCaptureLoupe.plan(
            at: CGPoint(x: 500, y: -50),
            bounds: display,
            framePixelSize: framePixels,
            pixelsPerPoint: pixelsPerPoint
        ))
    }

    func testAZeroPixelScaleHasNoPlan() {
        XCTAssertNil(AreaCaptureLoupe.plan(
            at: CGPoint(x: 500, y: 350),
            bounds: display,
            framePixelSize: framePixels,
            pixelsPerPoint: 0
        ))
    }
}
