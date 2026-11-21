import Foundation
import XCTest

@testable import StareCore

/// Tests for the per-tool shortcut map (S6/S7): `standard` must equal today's
/// `Tool.shortcut` for every tool — that is the regression pin — and the map
/// must refuse taken or unsupported characters without changing what it holds.

fileprivate extension Result {
    /// True when the result is a success.
    var isOk: Bool { if case .success = self { return true }; return false }
    /// The failure payload, if the result failed.
    var failureValue: Failure? { if case .failure(let error) = self { return error }; return nil }
}

final class ToolShortcutMapTests: XCTestCase {
    // MARK: Defaults reproduce today's shortcuts (S7)

    func testStandardMatchesToolShortcutForEveryTool() {
        // The regression pin for S7: the map, not the static, becomes what the
        // router reads, so it must reproduce `Tool.shortcut` exactly.
        for tool in Tool.allCases {
            XCTAssertEqual(ToolShortcutMap.standard[tool], tool.shortcut)
        }
    }

    func testEveryToolIsPresentInStandard() {
        XCTAssertEqual(Tool.allCases.map { ToolShortcutMap.standard[$0] }, Tool.allCases.map { $0.shortcut })
    }

    func testToolForResolvesCaseInsensitivelyLikeToday() {
        let map = ToolShortcutMap.standard
        XCTAssertEqual(map.tool(for: "p"), .pen)
        XCTAssertEqual(map.tool(for: "O"), .ellipse)
        XCTAssertEqual(map.tool(for: "V"), .select)
        XCTAssertNil(map.tool(for: "z"), "an unclaimed character resolves to nothing")
        XCTAssertNil(map.tool(for: "!"))
    }

    // MARK: Validation and refusal

    func testRefusesATakenCharacterAndLeavesTheMapUntouched() {
        var map = ToolShortcutMap.standard
        let original = map
        // "P" already belongs to the pen.
        XCTAssertEqual(map.conflictingTool(for: "P"), .pen)
        XCTAssertEqual(map.conflictingTool(for: "p"), .pen)

        let result = map.assigning("P", to: .laser)
        XCTAssertEqual(result.failureValue ?? nil, .conflict(.pen))
        XCTAssertEqual(map, original, "a refused assignment must leave the map untouched")
    }

    func testRefusesAnUnsupportedCharacterAndLeavesTheMapUntouched() {
        var map = ToolShortcutMap.standard
        let original = map

        for character in ["!", "-", "?", " ", "é"] {
            let result = map.assigning(Character(character), to: .laser)
            XCTAssertEqual(result.failureValue ?? nil, .unsupportedCharacter, "\(character) must be refused")
            XCTAssertEqual(map, original)
        }
    }

    func testAssigningAFreeLetterAndDigitSucceeds() {
        var map = ToolShortcutMap.standard
        XCTAssertTrue(map.assigning("Z", to: .laser).isOk)
        XCTAssertEqual(map[.laser], "Z")
        XCTAssertEqual(map.tool(for: "z"), .laser)

        XCTAssertTrue(map.assigning("2", to: .blur).isOk)
        XCTAssertEqual(map[.blur], "2")
        XCTAssertEqual(map.tool(for: "2"), .blur)
    }

    func testReassigningAToolToItsOwnCharacterIsAccepted() {
        var map = ToolShortcutMap.standard
        let own = map[.pen]
        XCTAssertTrue(map.assigning(own, to: .pen).isOk)
    }

    // MARK: Round trip

    func testRoundTripsThroughJSON() throws {
        var map = ToolShortcutMap.standard
        XCTAssertTrue(map.assigning("Z", to: .laser).isOk)

        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode(ToolShortcutMap.self, from: data)
        XCTAssertEqual(decoded, map)
    }

    // MARK: Lenient decoding

    func testConflictResolutionOnAHandWrittenJSONDocument() throws {
        // pen and laser both claim "Z"; blur carries an unsupported character;
        // number's entry is corrupt and eraser is missing entirely.
        let json = """
        {
          "pen": "Z",
          "laser": "Z",
          "blur": "!",
          "number": 7,
          "select": "v"
        }
        """
        let decoded = try JSONDecoder().decode(ToolShortcutMap.self, from: Data(json.utf8))

        XCTAssertEqual(decoded[.pen], "Z")
        XCTAssertEqual(decoded[.laser], "F", "the later duplicate yields to its default")
        XCTAssertEqual(decoded[.blur], "B", "an unsupported character falls back to the default")
        XCTAssertEqual(decoded[.number], "C", "a corrupt entry falls back to the default")
        XCTAssertEqual(decoded[.eraser], "E", "a missing tool falls back to the default")
        XCTAssertEqual(decoded[.select], "V", "a lowercase entry normalises to today's shortcut")

        // The map is a bijection: complete and conflict-free.
        let keys = Tool.allCases.map { decoded[$0] }
        XCTAssertEqual(keys.count, Tool.allCases.count)
        XCTAssertEqual(Set(keys).count, Tool.allCases.count)
    }

    // MARK: Router differential (S7)

    func testRouterWithStandardMapMatchesToday() {
        let router = ShortcutRouter(shortcuts: .standard)
        for tool in Tool.allCases {
            XCTAssertEqual(router.resolve(tool.shortcut), .tool(tool))
            XCTAssertEqual(router.resolve(Character(tool.shortcut.lowercased())), .tool(tool))
        }
    }

    func testRouterKeepsTodaySReservedAndIgnoredKeys() {
        let router = ShortcutRouter(shortcuts: .standard)
        XCTAssertEqual(router.resolve("3"), .ink(.yellow), "digits stay ink selectors")
        XCTAssertEqual(router.resolve("8"), .ink(.black))
        XCTAssertEqual(router.resolve("0"), .none)
        XCTAssertEqual(router.resolve("z"), .none)
        XCTAssertEqual(router.resolve("!"), .none)
    }

    func testStaticRouterEntryPointsKeepTheirBehaviour() {
        XCTAssertEqual(ShortcutRouter.resolve("p"), .tool(.pen))
        XCTAssertEqual(ShortcutRouter.resolve("O"), .tool(.ellipse))
        XCTAssertEqual(ShortcutRouter.resolve("3"), .ink(.yellow))
        XCTAssertEqual(ShortcutRouter.resolve("z"), .none)
        XCTAssertEqual(ShortcutRouter.resolve("v", allowedTools: [.select]), .tool(.select))
        XCTAssertEqual(ShortcutRouter.resolve("v", allowedTools: Tool.captureEditorTools), .none)
    }
}
