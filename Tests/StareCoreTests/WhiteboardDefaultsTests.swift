import Foundation
import XCTest

@testable import StareCore

/// Tests for the persisted whiteboard defaults (T3/S6): today a whiteboard
/// opens with one white page, so `.standard` must reproduce exactly that, and
/// `pagesOnOpen` must clamp to 1...10 on every path — init, decoding and
/// assignment — because a blob or a malformed UI value must never yield zero
/// or a runaway page count.

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

    // MARK: Background round trip

    func testBackgroundRoundTripsThroughJSON() throws {
        var saved = WhiteboardDefaults.standard
        saved.background = .black
        saved.pagesOnOpen = 3
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(WhiteboardDefaults.self, from: data), saved)
    }
}
