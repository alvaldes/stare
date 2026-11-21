import Foundation
import XCTest

@testable import StareCore

/// Tests for the persisted global-hotkey bindings (S6/S7): the defaults must
/// reproduce today's ⌥⇧A / ⌥⇧M / ⌥⇧P / ⌥⇧W exactly, and the map must refuse
/// invalid or conflicting assignments without changing what it already holds.

fileprivate extension Result {
    /// True when the result is a success.
    var isOk: Bool { if case .success = self { return true }; return false }
    /// The failure payload, if the result failed.
    var failureValue: Failure? { if case .failure(let error) = self { return error }; return nil }
}

final class HotkeyBindingsTests: XCTestCase {
    // MARK: Carbon flags

    func testCarbonFlagsMatchTheCarbonConstants() {
        // EventModifiers constants: cmdKey 4096, optionKey 2048,
        // controlKey 16384, shiftKey 512.
        XCTAssertEqual(HotkeyModifiers.command.carbonFlags, 4096)
        XCTAssertEqual(HotkeyModifiers.option.carbonFlags, 2048)
        XCTAssertEqual(HotkeyModifiers.control.carbonFlags, 16384)
        XCTAssertEqual(HotkeyModifiers.shift.carbonFlags, 512)
        XCTAssertEqual(HotkeyModifiers([.option, .shift]).carbonFlags, 2048 + 512)
    }

    // MARK: Virtual key codes

    func testVirtualKeyCodesMatchTheANSIKeyCodes() {
        // kVK_ANSI_* codes: a = 0, s = 1, d = 2, … m = 46, and the digits are
        // not sequential: 1 = 18 … 9 = 25, 0 = 29.
        XCTAssertEqual(VirtualKey.a.keyCode, 0)
        XCTAssertEqual(VirtualKey.s.keyCode, 1)
        XCTAssertEqual(VirtualKey.d.keyCode, 2)
        XCTAssertEqual(VirtualKey.m.keyCode, 46)
        XCTAssertEqual(VirtualKey.w.keyCode, 13)
        XCTAssertEqual(VirtualKey.p.keyCode, 35)
        XCTAssertEqual(VirtualKey.zero.keyCode, 29)
        XCTAssertEqual(VirtualKey.one.keyCode, 18)
        XCTAssertEqual(VirtualKey.nine.keyCode, 25)
    }

    func testVirtualKeyCharacterLookupIsCaseInsensitive() {
        XCTAssertEqual(VirtualKey(character: "a"), .a)
        XCTAssertEqual(VirtualKey(character: "M"), .m)
        XCTAssertEqual(VirtualKey(character: "7"), .seven)
        XCTAssertNil(VirtualKey(character: "!"))
        XCTAssertEqual(VirtualKey.m.character, "m")
        XCTAssertEqual(VirtualKey.three.character, "3")
    }

    // MARK: Defaults reproduce today's hotkeys (S7)

    func testStandardDefaultsAreOptionShiftAMPW() {
        let standard = HotkeyBindings.standard
        let optionShift: HotkeyModifiers = [.option, .shift]

        XCTAssertEqual(standard[.drawOverlay], HotkeyBinding(key: .a, modifiers: optionShift))
        XCTAssertEqual(standard[.pointerHighlight], HotkeyBinding(key: .m, modifiers: optionShift))
        XCTAssertEqual(standard[.pin], HotkeyBinding(key: .p, modifiers: optionShift))
        XCTAssertEqual(standard[.whiteboard], HotkeyBinding(key: .w, modifiers: optionShift))
    }

    func testEveryActionIsPresentInStandard() {
        XCTAssertEqual(HotkeyAction.allCases.count, 4)
        for action in HotkeyAction.allCases {
            XCTAssertEqual(HotkeyBindings.standard[action], action.defaultBinding)
            XCTAssertFalse(action.title.isEmpty)
        }
    }

    // MARK: Validation and refusal

    func testModifierLessBindingIsInvalidAndRefused() {
        let invalid = HotkeyBinding(key: .a, modifiers: [])
        XCTAssertFalse(invalid.isValid)
        XCTAssertTrue(HotkeyBinding(key: .a, modifiers: [.option]).isValid)

        var bindings = HotkeyBindings.standard
        let original = bindings
        let result = bindings.assigning(invalid, to: .drawOverlay)
        XCTAssertEqual(result.failureValue ?? nil, .invalidBinding)
        XCTAssertEqual(bindings, original, "a refused binding must leave the map untouched")
    }

    func testAssigningABindingUsedByAnotherActionIsRefusedAndMapIsUnchanged() {
        var bindings = HotkeyBindings.standard
        let original = bindings
        // ⌥⇧M is pointerHighlight's binding.
        let taken = HotkeyBindings.standard[.pointerHighlight]
        XCTAssertEqual(bindings.conflictingAction(for: taken), .pointerHighlight)

        let result = bindings.assigning(taken, to: .drawOverlay)
        XCTAssertEqual(result.failureValue ?? nil, .conflict(.pointerHighlight))
        XCTAssertEqual(bindings, original, "a refused assignment must leave the map untouched")
    }

    func testAssigningAFreeBindingSucceeds() {
        var bindings = HotkeyBindings.standard
        let result = bindings.assigning(HotkeyBinding(key: .d, modifiers: [.control]), to: .drawOverlay)
        XCTAssertTrue(result.isOk)
        XCTAssertEqual(bindings[.drawOverlay], HotkeyBinding(key: .d, modifiers: [.control]))
        // The other actions keep their defaults.
        XCTAssertEqual(bindings[.pointerHighlight], HotkeyAction.pointerHighlight.defaultBinding)
    }

    func testReassigningAnActionToItsOwnBindingIsAccepted() {
        var bindings = HotkeyBindings.standard
        let own = bindings[.pin]
        XCTAssertTrue(bindings.assigning(own, to: .pin).isOk)
    }

    // MARK: Round trip

    func testRoundTripsThroughJSON() throws {
        var bindings = HotkeyBindings.standard
        XCTAssertTrue(bindings.assigning(HotkeyBinding(key: .z, modifiers: [.command, .control]), to: .whiteboard).isOk)

        let data = try JSONEncoder().encode(bindings)
        let decoded = try JSONDecoder().decode(HotkeyBindings.self, from: data)
        XCTAssertEqual(decoded, bindings)
    }

    // MARK: Lenient decoding

    func testLenientDecodingReplacesDuplicateAndMissingWithDefaults() throws {
        // drawOverlay and whiteboard both claim ⌥⇧L; pin is missing.
        let json = """
        {
          "drawOverlay": {"key": "l", "modifiers": 10},
          "whiteboard": {"key": "l", "modifiers": 10}
        }
        """
        let decoded = try JSONDecoder().decode(HotkeyBindings.self, from: Data(json.utf8))

        XCTAssertEqual(decoded[.drawOverlay], HotkeyBinding(key: .l, modifiers: [.option, .shift]))
        XCTAssertEqual(decoded[.whiteboard], HotkeyAction.whiteboard.defaultBinding, "the later duplicate yields to its default")
        XCTAssertEqual(decoded[.pin], HotkeyAction.pin.defaultBinding, "a missing action falls back to its default")
        XCTAssertEqual(decoded[.pointerHighlight], HotkeyAction.pointerHighlight.defaultBinding)
        // The map is conflict-free and complete.
        let values = HotkeyAction.allCases.map { decoded[$0] }
        XCTAssertEqual(Set(values).count, HotkeyAction.allCases.count)
    }

    func testCorruptEntryDoesNotMakeTheMapIncomplete() throws {
        let json = """
        {
          "pin": {"key": "banana", "modifiers": 0},
          "drawOverlay": {"key": "a"}
        }
        """
        let decoded = try JSONDecoder().decode(HotkeyBindings.self, from: Data(json.utf8))

        XCTAssertEqual(HotkeyAction.allCases.map { decoded[$0] }, HotkeyAction.allCases.map { $0.defaultBinding })
    }

    func testUnknownKeysInJSONAreIgnored() throws {
        let json = """
        {"drawOverlay": {"key": "a", "modifiers": 10}, "partyMode": {"key": "q", "modifiers": 1}}
        """
        let decoded = try JSONDecoder().decode(HotkeyBindings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded[.drawOverlay], HotkeyAction.drawOverlay.defaultBinding)
        XCTAssertEqual(HotkeyAction.allCases.map { decoded[$0] }, HotkeyAction.allCases.map { $0.defaultBinding })
    }
}
