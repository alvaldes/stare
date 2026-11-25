import CoreGraphics
import XCTest
@testable import StareCore

/// S1/S4 of the overflow batch, second round: the extras panel opens toward the
/// middle of the screen, never toward the edge the bar is parked on, and never
/// off the visible frame.
final class ToolbarOverflowPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let panel = CGSize(width: 120, height: 200)

    /// A vertical bar hugging an edge, 44 wide and 400 tall, 8 pt in.
    private func verticalBar(on border: ToolbarBorder) -> CGRect {
        switch border {
        case .left: return CGRect(x: 8, y: 400, width: 44, height: 400)
        case .right: return CGRect(x: 1388, y: 400, width: 44, height: 400)
        default:
            XCTFail("not a vertical border")
            return .zero
        }
    }

    /// A horizontal bar hugging an edge, 600 wide and 42 tall, 8 pt in.
    private func horizontalBar(on border: ToolbarBorder) -> CGRect {
        switch border {
        case .top: return CGRect(x: 400, y: 850, width: 600, height: 42)
        case .bottom: return CGRect(x: 400, y: 8, width: 600, height: 42)
        default:
            XCTFail("not a horizontal border")
            return .zero
        }
    }

    func testAVerticalBarOpensItsPanelTowardTheMiddleOfTheScreen() {
        let left = ToolbarOverflowPlacement.panelFrame(
            panelSize: panel, barFrame: verticalBar(on: .left), border: .left, visibleFrame: visible)
        // Parked on the left edge, the panel sits to the right of the bar.
        XCTAssertEqual(left.minX, 8 + 44 + ToolbarOverflowPlacement.gap)
        XCTAssertEqual(left.maxY, 800, "aligned with the bar's top edge")

        let right = ToolbarOverflowPlacement.panelFrame(
            panelSize: panel, barFrame: verticalBar(on: .right), border: .right, visibleFrame: visible)
        // Parked on the right edge, it sits to the LEFT: toward the screen.
        XCTAssertEqual(right.maxX, 1388 - ToolbarOverflowPlacement.gap)
        XCTAssertEqual(right.maxY, 800)
    }

    func testAHorizontalBarOpensItsPanelTowardTheMiddleOfTheScreen() {
        let top = ToolbarOverflowPlacement.panelFrame(
            panelSize: panel, barFrame: horizontalBar(on: .top), border: .top, visibleFrame: visible)
        // Hanging from the top edge, the panel drops BELOW the bar.
        XCTAssertEqual(top.maxY, 850 - ToolbarOverflowPlacement.gap)
        XCTAssertEqual(top.minX, 400, "aligned with the bar's left edge")

        let bottom = ToolbarOverflowPlacement.panelFrame(
            panelSize: panel, barFrame: horizontalBar(on: .bottom), border: .bottom, visibleFrame: visible)
        // Along the bottom edge, it rises ABOVE the bar.
        XCTAssertEqual(bottom.minY, 8 + 42 + ToolbarOverflowPlacement.gap)
        XCTAssertEqual(bottom.minX, 400)
    }

    func testThePanelIsAlwaysInsideTheVisibleFrame() {
        let corners: [(ToolbarBorder, CGRect)] = [
            (.left, CGRect(x: 0, y: 0, width: 44, height: 400)),
            (.right, CGRect(x: 1396, y: 0, width: 44, height: 400)),
            (.top, CGRect(x: 0, y: 833, width: 600, height: 42)),
            (.bottom, CGRect(x: 0, y: 0, width: 600, height: 42)),
        ]
        for (border, bar) in corners {
            let frame = ToolbarOverflowPlacement.panelFrame(
                panelSize: panel, barFrame: bar, border: border, visibleFrame: visible)
            XCTAssertTrue(
                visible.contains(frame), "\(border): \(frame) is not inside \(visible)")
        }
    }

    /// A panel with no room left keeps its leading corner on screen instead of
    /// computing a frame outside the display.
    func testAPanelLargerThanTheRoomStaysReachable() {
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 200)
        let frame = ToolbarOverflowPlacement.panelFrame(
            panelSize: CGSize(width: 400, height: 300),
            barFrame: CGRect(x: 0, y: 0, width: 200, height: 40),
            border: .bottom,
            visibleFrame: tiny
        )
        XCTAssertEqual(frame.minX, tiny.minX)
        XCTAssertEqual(frame.minY, tiny.minY)
    }
}
