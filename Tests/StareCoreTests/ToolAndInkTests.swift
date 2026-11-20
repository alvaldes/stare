import CoreGraphics
import XCTest

import StareCore

final class ToolAndInkTests: XCTestCase {
    func testToolShortcutsMatchTheAgreedKeys() {
        let expected: [(Tool, Character)] = [
            (.pen, "P"),
            (.highlighter, "H"),
            (.arrow, "A"),
            (.line, "L"),
            (.rectangle, "R"),
            (.ellipse, "O"),
            (.number, "C"),
        ]

        for (tool, key) in expected {
            XCTAssertEqual(tool.shortcut, key, "\(tool) must answer to \(key)")
        }

        let shortcuts = Tool.allCases.map(\.shortcut)
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count, "shortcuts must not collide")
    }

    func testToolShortcutLookupIsCaseInsensitive() {
        XCTAssertEqual(ToolShortcut.tool(for: "p"), .pen)
        XCTAssertEqual(ToolShortcut.tool(for: "O"), .ellipse)
        XCTAssertNil(ToolShortcut.tool(for: "Z"))
    }

    func testOnlyNumberCompletesOnAClick() {
        XCTAssertTrue(Tool.number.isClickTool)
        for tool in Tool.allCases where tool != .number {
            XCTAssertFalse(tool.isClickTool, "\(tool) needs a drag")
        }
    }

    func testShapeToolsKeepOnlyEndpoints() {
        for tool in Tool.allCases where [.line, .arrow, .rectangle, .ellipse].contains(tool) {
            XCTAssertTrue(tool.usesEndpointsOnly, "\(tool) is defined by its endpoints")
        }
        for tool in [Tool.pen, .highlighter, .number] {
            XCTAssertFalse(tool.usesEndpointsOnly, "\(tool) keeps its samples")
        }
    }

    func testEightInksAreSelectableByDigitOneThroughEight() {
        XCTAssertEqual(Ink.allCases.count, 8)
        XCTAssertEqual(Ink.allCases.map(\.number), Array(1...8))

        for number in 1...8 {
            XCTAssertNotNil(Ink.ink(forNumber: number))
        }
        XCTAssertNil(Ink.ink(forNumber: 0))
        XCTAssertNil(Ink.ink(forNumber: 9))
    }

    func testInkColoursAreDistinct() {
        let colours = Ink.allCases.map { ink in
            [ink.rgb.red, ink.rgb.green, ink.rgb.blue]
        }
        for (index, colour) in colours.enumerated() {
            for other in colours[(index + 1)...] {
                XCTAssertNotEqual(colour, other)
            }
        }
    }
}
