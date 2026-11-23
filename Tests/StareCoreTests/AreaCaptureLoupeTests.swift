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
        // frame pixel coordinates (top-left origin, as `CGImage.cropping(to:)`
        // crops): 30 pt around (500, 350) → pixels (970, 670, 60, 60).
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

    // MARK: Orientation

    // `CGImage.cropping(to:)` crops in the frame's own pixel space, which is
    // top-left origin (CaptureEditor's `EditorCropSpace` states the same
    // convention for the editor's crops). These tests read actual cropped
    // pixels, not coordinate arithmetic: the frame carries distinct
    // horizontal bands and the pointer sits well off the display's vertical
    // centre — a mirrored, bottom-left source rect lands a different band, so
    // it fails under the very pixels it chose.

    /// The frozen frame split into two horizontal bands in top-left pixel
    /// space: `topHalf` covers rows 0..<700, `bottomHalf` rows 700..<1400.
    /// CGContext fills bottom-up, so the bottom band is painted at its own
    /// context y first and the top band above it.
    private func bandedFrame(
        topHalf: (r: CGFloat, g: CGFloat, b: CGFloat),
        bottomHalf: (r: CGFloat, g: CGFloat, b: CGFloat)
    ) -> CGImage {
        let context = CGContext(
            data: nil, width: 2000, height: 1400, bitsPerComponent: 8,
            bytesPerRow: 2000 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: bottomHalf.r, green: bottomHalf.g, blue: bottomHalf.b, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2000, height: 700))
        context.setFillColor(red: topHalf.r, green: topHalf.g, blue: topHalf.b, alpha: 1)
        context.fill(CGRect(x: 0, y: 700, width: 2000, height: 700))
        return context.makeImage()!
    }

    /// The single pixel of `image` whose top-left corner index is `point`:
    /// cropped 1×1 in the frame's own top-left space, decoded to RGBA8.
    private func pixel(
        of image: CGImage, at point: CGPoint
    ) throws -> (r: UInt8, g: UInt8, b: UInt8) {
        let one = try XCTUnwrap(image.cropping(
            to: CGRect(origin: point, size: CGSize(width: 1, height: 1))))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(one, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: 4)
        return (bytes[0], bytes[1], bytes[2])
    }

    func testAnOffCentrePointerMagnifiesThePixelUnderItInTopLeftPixelSpace() throws {
        // The pointer (500, 300) sits on pixel row 600 under the top-left
        // convention `CGImage.cropping(to:)` crops by, but on row 800 under a
        // bottom-left one — different halves, so a mirrored source fails on
        // the pixels themselves.
        let frame = bandedFrame(topHalf: (0, 1, 0), bottomHalf: (0, 0, 1))
        let plan = try XCTUnwrap(AreaCaptureLoupe.plan(
            at: CGPoint(x: 500, y: 300),
            bounds: display,
            framePixelSize: framePixels,
            pixelsPerPoint: pixelsPerPoint
        ))
        let crop = try XCTUnwrap(frame.cropping(to: plan.source))
        let centre = try pixel(
            of: crop, at: CGPoint(x: crop.width / 2, y: crop.height / 2))
        XCTAssertEqual(centre.g, 255, "the crop's centre pixel is the pixel under the pointer")
        XCTAssertEqual(centre.b, 0)
        XCTAssertEqual(centre.r, 0)
    }

    func testADisplayWhoseOriginIsNotZeroStillMagnifiesTopLeft() throws {
        // A display canvas does not sit at (0,0): a display above or left of
        // the primary has a negative origin, and the conversion must be
        // bounds-relative. Here (1700, 300) is 300 points below the display's
        // own top edge, which is pixel row 1200 — the bottom band.
        let offOriginDisplay = CGRect(x: 1200, y: -300, width: 1000, height: 700)
        let frame = bandedFrame(topHalf: (1, 0, 0), bottomHalf: (0, 0, 1))
        let plan = try XCTUnwrap(AreaCaptureLoupe.plan(
            at: CGPoint(x: 1700, y: 300),
            bounds: offOriginDisplay,
            framePixelSize: framePixels,
            pixelsPerPoint: pixelsPerPoint
        ))
        let crop = try XCTUnwrap(frame.cropping(to: plan.source))
        let centre = try pixel(
            of: crop, at: CGPoint(x: crop.width / 2, y: crop.height / 2))
        XCTAssertEqual(centre.b, 255, "the crop's centre pixel is the pixel under the pointer")
        XCTAssertEqual(centre.g, 0)
        XCTAssertEqual(centre.r, 0)
    }
}
