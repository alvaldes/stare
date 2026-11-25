import XCTest
@testable import StareCore

/// The bar's overflow control (`⁞`): the pure values the toolbar view draws
/// from, so the glyph, the axis and what the control says about the active
/// tool can be pinned without spinning up SwiftUI.
final class ToolbarOverflowSpecTests: XCTestCase {
    func testTheCollapsedControlDrawsThreeDotsThatFollowTheBarsAxis() {
        XCTAssertEqual(ToolbarOverflowSpec.glyph, "ellipsis")
        // A vertical bar stacks the dots, a horizontal one lays them out:
        // the same symbol, turned.
        XCTAssertEqual(ToolbarOverflowSpec.rotationDegrees(isVertical: true), 90)
        XCTAssertEqual(ToolbarOverflowSpec.rotationDegrees(isVertical: false), 0)
    }

    func testTheControlTakesTheActiveToolsSymbolWhenThatToolHidesBehindIt() {
        let hidden: [Tool] = [.line, .number, .blur, .spotlight, .laser]
        // S6: the bar always says which tool is active, even the one you
        // picked from behind the `⁞`.
        XCTAssertEqual(ToolbarOverflowSpec.symbolName(selected: .spotlight, hidden: hidden), Tool.spotlight.symbolName)
        XCTAssertEqual(ToolbarOverflowSpec.symbolName(selected: .blur, hidden: hidden), Tool.blur.symbolName)
        // A tool that is on the bar marks itself there; the control stays dots.
        XCTAssertEqual(ToolbarOverflowSpec.symbolName(selected: .pen, hidden: hidden), ToolbarOverflowSpec.glyph)
        XCTAssertEqual(ToolbarOverflowSpec.symbolName(selected: nil, hidden: hidden), ToolbarOverflowSpec.glyph)
        // Nothing behind it: dots, never a stale tool.
        XCTAssertEqual(ToolbarOverflowSpec.symbolName(selected: .spotlight, hidden: []), ToolbarOverflowSpec.glyph)
    }

    func testTheControlListsWhatWaitsBehindItAndNamesTheActiveHiddenTool() {
        let hidden: [Tool] = [.line, .number, .blur, .spotlight, .laser]
        XCTAssertEqual(
            ToolbarOverflowSpec.help(selected: .pen, hidden: hidden),
            "More tools: Line, Numbered step, Blur, Spotlight, Laser pointer"
        )
        XCTAssertEqual(
            ToolbarOverflowSpec.help(selected: .spotlight, hidden: hidden),
            "Spotlight is active and hidden · More tools: Line, Numbered step, Blur, Spotlight, Laser pointer"
        )
        XCTAssertEqual(ToolbarOverflowSpec.help(selected: nil, hidden: []), "No hidden tools")
    }
}
