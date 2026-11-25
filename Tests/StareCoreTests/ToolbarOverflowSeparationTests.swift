import XCTest
@testable import StareCore

/// Removing a separator from the bar: every separator carries the same value, so
/// the one the user right-clicked is identified by where it sits.
final class ToolbarOverflowSeparationTests: XCTestCase {
    private let layout = ToolbarToolLayout(items: [
        .tool(.pen), .separator, .tool(.highlighter), .separator, .tool(.eraser),
    ])

    func testItRemovesTheSeparatorAtThatIndexAndNothingElse() {
        let withoutFirst = layout.removingItem(at: 1)
        XCTAssertEqual(withoutFirst.items, [.tool(.pen), .tool(.highlighter), .separator, .tool(.eraser)])

        let withoutSecond = layout.removingItem(at: 3)
        XCTAssertEqual(withoutSecond.items, [.tool(.pen), .separator, .tool(.highlighter), .tool(.eraser)])
        // The pool is untouched either way: a separator is not a tool and never
        // enters it (normalisation already topped it up with the tools the bar
        // does not hold).
        XCTAssertEqual(withoutFirst.pool, layout.pool)
    }

    func testAToolAtThatIndexStillCannotEmptyTheBar() {
        let single = ToolbarToolLayout(items: [.tool(.pen)])
        XCTAssertEqual(single.removingItem(at: 0), single, "the bar keeps its last tool")
        // A tool leaves through the pool instead, so the layout keeps it there.
        let pooled = layout.removingItem(at: 0)
        XCTAssertEqual(pooled.visibleTools.first, .highlighter)
        XCTAssertTrue(pooled.pool.contains(.pen))
    }

    func testAnIndexOutOfRangeChangesNothing() {
        XCTAssertEqual(layout.removingItem(at: -1), layout)
        XCTAssertEqual(layout.removingItem(at: 99), layout)
    }
}
