import CoreGraphics
import XCTest
@testable import Stare
@testable import StareCore

/// The stage's fit is the thing that lets the preview show a VERTICAL bar: a
/// width-only fit drew the column 700 pt high and pushed the pane apart, which is
/// why the preview used to be pinned to horizontal and why switching to vertical
/// looked like nothing happened.
final class SettingsPreviewFitTests: XCTestCase {
    /// The bar's two shapes at their natural sizes.
    private let row = CGSize(width: 750, height: 42)
    private let column = CGSize(width: 44, height: 742)

    func testAHorizontalBarFitsByItsWidth() {
        let cardsWidth: CGFloat = 766
        let scale = BarPane.previewScale(naturalSize: row, cardsWidth: cardsWidth)
        let available = cardsWidth - SettingsMetrics.stageChrome
        XCTAssertEqual(row.width * scale, available, accuracy: 0.5)
        XCTAssertLessThan(scale, 1)
    }

    func testAVerticalBarFitsByItsHeightAndStaysInsideTheStage() {
        let cardsWidth: CGFloat = 766
        let scale = BarPane.previewScale(naturalSize: column, cardsWidth: cardsWidth)
        XCTAssertLessThanOrEqual(
            column.height * scale, SettingsMetrics.stageMaxPreviewHeight + 0.5,
            "a column that only fitted its width would draw 742 pt tall and break the pane")
        // And it is still wide enough to be read.
        XCTAssertGreaterThan(column.width * scale, 10)
    }

    func testItNeverEnlargesABarThatAlreadyFits() {
        let small = CGSize(width: 120, height: 30)
        XCTAssertEqual(BarPane.previewScale(naturalSize: small, cardsWidth: 900), 1)
        XCTAssertEqual(BarPane.previewScale(naturalSize: .zero, cardsWidth: 900), 1)
    }
}
