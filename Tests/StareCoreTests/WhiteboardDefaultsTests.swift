import Foundation
import XCTest

@testable import StareCore

/// Tests for the persisted whiteboard defaults (T3/S6, T13/S8): a whiteboard
/// opens with the user's background choice — white, black, or System, which
/// resolves white in light mode and black in dark mode at board-open time —
/// and `pagesOnOpen` must clamp to 1...10 on every path — init, decoding and
/// assignment — because a blob or a malformed UI value must never yield zero
/// or a runaway page count.
///
/// Backward compatibility is part of the contract: blobs written before the
/// System choice existed store `"white"|"black"` under the same `background`
/// key, and they must decode into the same choice — a stored black board
/// never resets to white.

private func decode(_ json: String) throws -> WhiteboardDefaults {
    try JSONDecoder().decode(WhiteboardDefaults.self, from: Data(json.utf8))
}

final class WhiteboardDefaultsTests: XCTestCase {
    // MARK: Defaults reproduce today's whiteboard (S6/S7)

    func testStandardIsWhiteBackgroundWithOnePage() {
        XCTAssertEqual(WhiteboardDefaults.standard.background, .white)
        XCTAssertEqual(WhiteboardDefaults.standard.pagesOnOpen, 1)
        XCTAssertEqual(WhiteboardDefaults.standard, WhiteboardDefaults())
    }

    // MARK: Clamping on init

    func testInitClampsPagesOnOpenIntoTheValidRange() {
        XCTAssertEqual(WhiteboardDefaults(pagesOnOpen: 0).pagesOnOpen, 1)
        XCTAssertEqual(WhiteboardDefaults(pagesOnOpen: -3).pagesOnOpen, 1)
        XCTAssertEqual(WhiteboardDefaults(pagesOnOpen: 11).pagesOnOpen, 10)
        XCTAssertEqual(WhiteboardDefaults(pagesOnOpen: 5).pagesOnOpen, 5)
    }

    // MARK: Clamping on assignment

    func testAssignmentClampsPagesOnOpen() {
        var defaults = WhiteboardDefaults.standard
        defaults.pagesOnOpen = 99
        XCTAssertEqual(defaults.pagesOnOpen, 10)
        defaults.pagesOnOpen = 0
        XCTAssertEqual(defaults.pagesOnOpen, 1)
        defaults.pagesOnOpen = 7
        XCTAssertEqual(defaults.pagesOnOpen, 7)
    }

    func testAssigningReturnsAClampedValue() {
        let assigned = WhiteboardDefaults.standard.assigning(pagesOnOpen: 42)
        XCTAssertEqual(assigned.pagesOnOpen, 10)
        XCTAssertEqual(WhiteboardDefaults.standard, WhiteboardDefaults(background: .white, pagesOnOpen: 1))
    }

    // MARK: Lenient decoding

    func testDecodeClampsOutOfRangePagesOnOpen() throws {
        XCTAssertEqual(try decode(#"{"pagesOnOpen":99}"#).pagesOnOpen, 10)
        XCTAssertEqual(try decode(#"{"pagesOnOpen":0}"#).pagesOnOpen, 1)
    }

    func testDecodeMissingFieldsTakeTodayDefaults() throws {
        let decoded = try decode(#"{}"#)
        XCTAssertEqual(decoded.background, .white)
        XCTAssertEqual(decoded.pagesOnOpen, 1)
    }

    func testUnknownBackgroundFallsBackToWhiteAndKeepsTheRest() throws {
        let decoded = try decode(#"{"background":"sepia","pagesOnOpen":4}"#)
        XCTAssertEqual(decoded.background, .white)
        XCTAssertEqual(decoded.pagesOnOpen, 4)
    }

    // MARK: Background choice resolution (T13/S8)

    func testStandardResolvesWhiteForBothAppearances() {
        let standard = WhiteboardDefaults.standard
        XCTAssertEqual(standard.background, WhiteboardBackgroundChoice.white)
        XCTAssertEqual(standard.resolvedBackground(isDarkAppearance: false), .white)
        XCTAssertEqual(standard.resolvedBackground(isDarkAppearance: true), .white)
    }

    func testWhiteChoiceResolvesWhiteForBothAppearances() {
        let defaults = WhiteboardDefaults(background: .white)
        XCTAssertEqual(defaults.resolvedBackground(isDarkAppearance: false), .white)
        XCTAssertEqual(defaults.resolvedBackground(isDarkAppearance: true), .white)
    }

    func testBlackChoiceResolvesBlackForBothAppearances() {
        let defaults = WhiteboardDefaults(background: .black)
        XCTAssertEqual(defaults.resolvedBackground(isDarkAppearance: false), .black)
        XCTAssertEqual(defaults.resolvedBackground(isDarkAppearance: true), .black)
    }

    func testSystemChoiceResolvesByAppearance() {
        let defaults = WhiteboardDefaults(background: .system)
        XCTAssertEqual(defaults.resolvedBackground(isDarkAppearance: false), .white)
        XCTAssertEqual(defaults.resolvedBackground(isDarkAppearance: true), .black)
    }

    func testSystemChoiceDetailStatesWhatItResolvesTo() {
        let detail = WhiteboardBackgroundChoice.system.detail
        XCTAssertTrue(detail.contains("light"), "the System detail must say what light mode resolves to")
        XCTAssertTrue(detail.contains("dark"), "the System detail must say what dark mode resolves to")
    }

    // MARK: Legacy blob compatibility (T13/S8)

    /// Old blobs store `"white"|"black"` under the same `background` key; the
    /// new choice type must decode straight from them, so a user's existing
    /// black board stays black both in the stored choice and in resolution.
    func testLegacyBlackBlobDecodesIntoBlackChoiceAndStaysBlack() throws {
        let decoded = try decode(#"{"background":"black","pagesOnOpen":3}"#)
        XCTAssertEqual(decoded.background, WhiteboardBackgroundChoice.black)
        XCTAssertEqual(decoded.pagesOnOpen, 3)
        XCTAssertEqual(decoded.resolvedBackground(isDarkAppearance: false), .black)
        XCTAssertEqual(decoded.resolvedBackground(isDarkAppearance: true), .black)
    }

    func testLegacyWhiteBlobDecodesIntoWhiteChoice() throws {
        let decoded = try decode(#"{"background":"white"}"#)
        XCTAssertEqual(decoded.background, WhiteboardBackgroundChoice.white)
    }

    /// The new shape keeps the `background` raw string, now able to carry
    /// `"system"`; encoding and decoding round-trip the choice untouched.
    func testSystemChoiceRoundTripsThroughJSON() throws {
        var saved = WhiteboardDefaults.standard
        saved.background = .system
        saved.pagesOnOpen = 2
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(WhiteboardDefaults.self, from: data), saved)
    }

    // MARK: Background round trip

    func testBackgroundRoundTripsThroughJSON() throws {
        var saved = WhiteboardDefaults.standard
        saved.background = .black
        saved.pagesOnOpen = 3
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(WhiteboardDefaults.self, from: data), saved)
    }
}
