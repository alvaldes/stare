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

    func testOnlyNumberCompletesImmediately() {
        XCTAssertTrue(Tool.number.commitsImmediately)
        for tool in Tool.allCases where tool != .number {
            XCTAssertFalse(tool.commitsImmediately, "\(tool) waits for confirmation")
        }
    }

    func testClickToolsAreNumberAndText() {
        XCTAssertTrue(Tool.number.isClickTool)
        XCTAssertTrue(Tool.text.isClickTool)
        for tool in [Tool.pen, .highlighter, .arrow, .line, .rectangle, .ellipse, .laser, .eraser] {
            XCTAssertFalse(tool.isClickTool, "\(tool) needs a drag")
        }
    }

    func testLaserIsTransientAndEraserRemoves() {
        XCTAssertTrue(Tool.laser.isTransient)
        XCTAssertFalse(Tool.pen.isTransient)
        XCTAssertTrue(Tool.eraser.isEraser)
        XCTAssertFalse(Tool.pen.isEraser)
    }

    func testRouterResolvesToolsAndInks() {
        XCTAssertEqual(ShortcutRouter.resolve("p"), .tool(.pen))
        XCTAssertEqual(ShortcutRouter.resolve("O"), .tool(.ellipse))
        XCTAssertEqual(ShortcutRouter.resolve("3"), .ink(.yellow))
        XCTAssertEqual(ShortcutRouter.resolve("8"), .ink(.black))
        XCTAssertEqual(ShortcutRouter.resolve("z"), .none)
        XCTAssertEqual(ShortcutRouter.resolve("0"), .none)
    }

    func testRouterNeverConfusesToolsAndInks() {
        // Every tool key must resolve to a tool, every digit to an ink.
        for tool in Tool.allCases {
            XCTAssertEqual(ShortcutRouter.resolve(tool.shortcut), .tool(tool))
        }
        for ink in Ink.allCases {
            XCTAssertEqual(ShortcutRouter.resolve(Character("\(ink.number)")), .ink(ink))
        }
    }

    func testNewToolShortcuts() {
        XCTAssertEqual(Tool.text.shortcut, "T")
        XCTAssertEqual(Tool.laser.shortcut, "F")
        XCTAssertEqual(Tool.eraser.shortcut, "E")
        XCTAssertEqual(ToolShortcut.tool(for: "t"), .text)
        XCTAssertEqual(ToolShortcut.tool(for: "F"), .laser)
        XCTAssertEqual(ToolShortcut.tool(for: "e"), .eraser)
    }

    func testBlurResolvesFromBAndDescribesItself() {
        XCTAssertEqual(Tool.blur.shortcut, "B")
        XCTAssertEqual(Tool.blur.displayName, "Blur")
        XCTAssertEqual(Tool.blur.symbolName, "camera.filters")
        XCTAssertEqual(ToolShortcut.tool(for: "b"), .blur)
        XCTAssertEqual(ToolShortcut.tool(for: "B"), .blur)
    }

    // T5/S3: blur is an area tool drawn by dragging a rectangle.
    func testBlurIsAnEndpointsOnlyDragTool() {
        XCTAssertTrue(Tool.blur.usesEndpointsOnly, "blur spans the dragged rectangle")
        XCTAssertFalse(Tool.blur.isClickTool)
        XCTAssertFalse(Tool.blur.isTransient)
        XCTAssertFalse(Tool.blur.isEraser)
        XCTAssertFalse(Tool.blur.commitsImmediately)
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
    // S5: the palette groups tools of a kind, and never shows one twice or drops one.
    func testToolbarGroupsShowEveryToolExactlyOnce() {
        let grouped = Tool.toolbarGroups.flatMap { $0 }
        XCTAssertEqual(grouped.count, Tool.allCases.count, "a tool must not appear twice in the palette")
        XCTAssertEqual(Set(grouped), Set(Tool.allCases), "every tool must be reachable from the palette")
    }

    func testToolbarGroupsKeepToolsOfAKindTogether() {
        XCTAssertEqual(Tool.toolbarGroups.first, [.pen, .highlighter])
        XCTAssertEqual(Tool.toolbarGroups.last, [.eraser])
    }

}
