import AppKit
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
        for tool in [Tool.pen, .highlighter, .arrow, .line, .rectangle, .ellipse, .laser, .eraser, .blur, .spotlight] {
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

    // S15 slice B: the spotlight (D) is a persistent dimming mark, an area
    // tool like the blur — a key of its own, no ink of its own.
    func testSpotlightResolvesFromDAndDescribesItself() {
        XCTAssertEqual(Tool.spotlight.shortcut, "D")
        XCTAssertEqual(Tool.spotlight.displayName, "Spotlight")
        XCTAssertEqual(ToolShortcut.tool(for: "d"), .spotlight)
        XCTAssertEqual(ToolShortcut.tool(for: "D"), .spotlight)
        // The ink keys must keep working while the spotlight is selected:
        // the spotlight claims a letter, never a digit, and every ink keeps
        // its number.
        XCTAssertEqual(ShortcutRouter.resolve("1"), .ink(.red))
        for ink in Ink.allCases {
            XCTAssertEqual(ShortcutRouter.resolve(Character("\(ink.number)")), .ink(ink))
        }
    }

    func testSpotlightIsAnEndpointsOnlyDimmingAreaTool() {
        XCTAssertTrue(Tool.spotlight.usesEndpointsOnly, "the spotlight spans the dragged rectangle")
        XCTAssertFalse(Tool.spotlight.isClickTool)
        XCTAssertFalse(Tool.spotlight.isTransient, "a spotlight is a persistent mark, never a fading one")
        XCTAssertFalse(Tool.spotlight.isEraser)
        XCTAssertFalse(Tool.spotlight.commitsImmediately)
        XCTAssertTrue(Tool.spotlight.worksInCaptureEditor, "an emphasis region works over a still capture too")
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
        // T11/S6: the selection cursor leads the bar as its own family group.
        XCTAssertEqual(Tool.toolbarGroups.first, [.select])
        XCTAssertEqual(Tool.toolbarGroups.last, [.eraser])
    }

    // T11/S6 defect B: every tool's symbol must be a real SF Symbol, or the
    // toolbar renders an empty button — and the cursor is the first one.
    func testEveryToolSymbolNameExistsInSFSymbols() {
        for tool in Tool.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: nil),
                "\(tool) must have a real SF Symbol, got '\(tool.symbolName)'"
            )
        }
    }

    // T11/S6: the first tool is the edit cursor, and it answers to V.
    func testSelectLeadsTheToolbarAndDescribesItself() {
        XCTAssertEqual(Tool.select.shortcut, "V")
        XCTAssertEqual(Tool.select.displayName, "Cursor")
        XCTAssertTrue(Tool.select.isSelection)
        for tool in Tool.allCases where tool != .select {
            XCTAssertFalse(tool.isSelection)
        }
        XCTAssertEqual(ToolShortcut.tool(for: "v"), .select)
        XCTAssertEqual(ToolShortcut.tool(for: "V"), .select)
        XCTAssertFalse(Tool.select.usesEndpointsOnly)
        XCTAssertFalse(Tool.select.isClickTool)
        XCTAssertFalse(Tool.select.isTransient)
        XCTAssertFalse(Tool.select.isEraser)
        XCTAssertFalse(Tool.select.commitsImmediately)
    }

    // T11/S6 advisory B: the capture editor draws over a static captured image
    // with no live session, so tools that need one must not be offered there —
    // text has no field editor and the laser's lifetime is meaningless over a
    // still image. Select joins the editor's palette per S4/L4 (owner: "le falta
    // el tool 'v'"): it mints no mark over a still image, so it is the
    // palette's empty-handed pointer route. Every tool the editor does offer
    // keeps its place in the groups.
    func testCaptureEditorOffersOnlyToolsThatWorkThere() {
        let offered = Tool.captureEditorTools
        XCTAssertTrue(offered.contains(.select), "S4/L4: the cursor is offered in the capture editor — it mints no mark over a still image")
        XCTAssertFalse(offered.contains(.text), "text has no field editor in the capture editor")
        XCTAssertFalse(offered.contains(.laser), "the laser fades with the session, not over a still image")
        for tool in [.pen, .highlighter, .arrow, .line, .rectangle, .ellipse, .number, .eraser, .blur, .spotlight] as [Tool] {
            XCTAssertTrue(offered.contains(tool), "\(tool) still works over a captured image")
        }
        // Same order and grouping as the main bar, minus the dead tools.
        XCTAssertEqual(Tool.captureEditorGroups, Tool.toolbarGroups.map { $0.filter(\.worksInCaptureEditor) }.filter { !$0.isEmpty })
        XCTAssertEqual(Set(Tool.captureEditorTools), Set(offered), "the flattened list matches the groups")
        // The overlay bar is untouched: same tools, cursor first (order within
        // the groups is by family, not the enum order).
        XCTAssertEqual(Set(Tool.toolbarGroups.flatMap { $0 }), Set(Tool.allCases))
        XCTAssertEqual(Tool.toolbarGroups.flatMap { $0 }.first, .select)
    }

    // T2/S2: every tool shows its own cursor. The role vocabulary is exactly
    // the tool set — one role per tool, nothing shared and no silent default —
    // so the pointer always tells the active tool apart.
    func testEveryToolHasItsOwnCursorRole() {
        let roles = Tool.allCases.map(\.cursor)
        XCTAssertEqual(
            Set(roles).count,
            Tool.allCases.count,
            "two tools sharing a cursor must be an explicit, documented exception"
        )
        XCTAssertEqual(
            Set(roles),
            Set(ToolCursor.allCases),
            "the role set must cover every tool exactly: no silent default"
        )
    }

    // T2/S2: the tool → role choice itself, pinned per tool. System cursors
    // where one genuinely matches the tool's job; drawn glyphs elsewhere —
    // since batch A/S3 the number joins the drawn set with its
    // circle-inside-a-circle shape.
    func testCursorRolesNameTheirToolExactly() {
        let expected: [Tool: ToolCursor] = [
            .select: .editArrow,
            .text: .textIBeam,
            .number: .numberRings,
            .line: .lineCrosshair,
            .pen: .penDot,
            .highlighter: .markerBeam,
            .arrow: .arrowCrosshair,
            .rectangle: .rectangleCrosshair,
            .ellipse: .ellipseCrosshair,
            .laser: .laserSpark,
            .eraser: .eraserRing,
            .blur: .blurDots,
            .spotlight: .spotlightBeam,
        ]
        XCTAssertEqual(expected.count, Tool.allCases.count, "the pin must name every tool")
        for (tool, role) in expected {
            XCTAssertEqual(tool.cursor, role, "\(tool) shows the wrong cursor role")
        }
    }

    // Advisory B, re-derived per S4/L4: V resolves to the select tool in the
    // capture editor as it does in the overlay — the editor offers the cursor —
    // while a tool the editor hides still lands on nothing.
    func testSelectShortcutResolvesInTheCaptureEditor() {
        XCTAssertEqual(ShortcutRouter.resolve("v"), .tool(.select), "the overlay offers the cursor")
        XCTAssertEqual(
            ShortcutRouter.resolve("v", allowedTools: Tool.captureEditorTools),
            .tool(.select),
            "S4/L4: the editor offers the cursor too"
        )

        // Every tool the editor shows stays reachable by its shortcut, and no
        // offered shortcut resolves to a tool the editor hides.
        for tool in Tool.captureEditorTools {
            XCTAssertEqual(
                ShortcutRouter.resolve(Character(tool.shortcut.lowercased()), allowedTools: Tool.captureEditorTools),
                .tool(tool)
            )
        }
        XCTAssertEqual(
            ShortcutRouter.resolve("t", allowedTools: Tool.captureEditorTools),
            .none,
            "the text shortcut is dead in the editor too"
        )
    }
}
