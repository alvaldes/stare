import XCTest
@testable import StareCore

final class FrontWindowDisplayTests: XCTestCase {
    /// Two side-by-side displays, AppKit frames (bottom-left origin).
    private let displays: [CGRect] = [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: 1920, y: 0, width: 1920, height: 1080),
    ]

    func testAppKitFrameFlipsTheVerticalAxisAroundThePrimaryTop() {
        // CG window bounds are top-left origin: 100 left, 200 below the top
        // of the primary display, 800x600.
        let frame = FrontWindowDisplay.appKitFrame(
            cgWindowBounds: CGRect(x: 100, y: 200, width: 800, height: 600),
            primaryScreenTop: 1080
        )
        XCTAssertEqual(frame, CGRect(x: 100, y: 1080 - 800, width: 800, height: 600))
    }

    func testDisplayIndexOfWindowCentredOnEachDisplay() {
        let left = CGRect(x: 400, y: 300, width: 800, height: 600)
        let right = CGRect(x: 2400, y: 300, width: 800, height: 600)
        XCTAssertEqual(FrontWindowDisplay.displayIndex(windowFrame: left, displayFrames: displays), 0)
        XCTAssertEqual(FrontWindowDisplay.displayIndex(windowFrame: right, displayFrames: displays), 1)
    }

    func testDisplayIndexFallsBackToTheDisplayWithTheLargestOverlap() {
        // Two displays with a gap between them; the window's centre falls in
        // the gap, but most of the window sits on the second display.
        let gapped: [CGRect] = [
            CGRect(x: 0, y: 0, width: 1000, height: 1000),
            CGRect(x: 2000, y: 0, width: 1000, height: 1000),
        ]
        let straddling = CGRect(x: 900, y: 100, width: 1400, height: 400)
        XCTAssertEqual(FrontWindowDisplay.displayIndex(windowFrame: straddling, displayFrames: gapped), 1)
    }

    func testDisplayIndexIsNilWhenTheWindowTouchesNoDisplay() {
        let far = CGRect(x: 9000, y: 9000, width: 10, height: 10)
        XCTAssertNil(FrontWindowDisplay.displayIndex(windowFrame: far, displayFrames: displays))
    }

    func testDisplayIndexIsNilWithoutDisplays() {
        let frame = CGRect(x: 100, y: 100, width: 100, height: 100)
        XCTAssertNil(FrontWindowDisplay.displayIndex(windowFrame: frame, displayFrames: []))
    }

    func testConversionAndMappingTogetherPickTheRightDisplayOnStackedScreens() {
        // A secondary display stacked above the main one: the main display's
        // top edge (its frame height, 1080) is where the two coordinate
        // systems meet, so a window 1400..2200 in AppKit y sits at
        // 1080 - 2200 = -1120 in CG y. The conversion must bring it back onto
        // the upper display.
        let stacked: [CGRect] = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: 1080, width: 2560, height: 1440),
        ]
        let cgBounds = CGRect(x: 100, y: -1120, width: 1200, height: 800)
        let appKit = FrontWindowDisplay.appKitFrame(cgWindowBounds: cgBounds, primaryScreenTop: 1080)
        XCTAssertEqual(appKit, CGRect(x: 100, y: 1400, width: 1200, height: 800))
        XCTAssertEqual(FrontWindowDisplay.displayIndex(windowFrame: appKit, displayFrames: stacked), 1)
    }
}
