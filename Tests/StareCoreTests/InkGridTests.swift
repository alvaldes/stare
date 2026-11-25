import XCTest
@testable import StareCore

/// T9/S10 (L29): the pure rule behind the bar's ink palette — the inks fold
/// into `columns`-wide rows without dropping, reordering or duplicating any
/// of them, and a count that does not divide evenly leaves its remainder in
/// the last row instead of padding with a hole. A width of 0 or less is
/// treated as 1 (a single row/column, the bar's own shape) rather than
/// trapping or producing empty rows.
final class InkGridTests: XCTestCase {
    func testEightInksInTwoColumnsGiveFourRowsOfTwo() {
        let rows = InkGrid.rows(columns: 2)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map(\.count), [2, 2, 2, 2])
    }

    func testTheFlattenedRowsAreTheInksInOrder() {
        let rows = InkGrid.rows(columns: 2)
        XCTAssertEqual(rows.flatMap { $0 }, Array(Ink.allCases))
    }

    func testOneColumnGivesEightRowsOfOne() {
        let rows = InkGrid.rows(columns: 1)
        XCTAssertEqual(rows.count, 8)
        XCTAssertEqual(rows.map(\.count), Array(repeating: 1, count: 8))
        XCTAssertEqual(rows.flatMap { $0 }, Array(Ink.allCases))
    }

    func testAnUnevenCountLeavesItsRemainderInTheLastRow() {
        let inks = Array(Ink.allCases.prefix(5))
        let rows = InkGrid.rows(inks, columns: 2)
        XCTAssertEqual(rows.map(\.count), [2, 2, 1])
        XCTAssertEqual(rows.flatMap { $0 }, inks)
    }

    func testZeroAndNegativeColumnsAreTreatedAsOne() {
        for width in [0, -1, -7] {
            let rows = InkGrid.rows(columns: width)
            XCTAssertEqual(rows.count, 8, "columns \(width) must read as one")
            XCTAssertEqual(rows.flatMap { $0 }, Array(Ink.allCases))
        }
    }
}
