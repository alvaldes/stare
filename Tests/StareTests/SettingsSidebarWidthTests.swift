import AppKit
import XCTest

@testable import Stare
import StareCore

/// The sidebar's rows never reflow: a row that wraps when it becomes the
/// selected one jumps the whole list, which is what the owner saw on "Pointer
/// Highlight" — it fits in regular and did not fit in semibold.
///
/// The toolbar's label is `.lineLimit(1)` now, so this measures the number that
/// decides whether that limit ever bites: every area's title, in the SEMIBOLD
/// the selected row uses, has to fit the width a row's text actually gets.
final class SettingsSidebarWidthTests: XCTestCase {

    /// What a row's label gets: the sidebar, less the sidebar's own padding,
    /// less the row's padding, less the symbol and the gap beside it.
    private var availableTextWidth: CGFloat {
        SettingsMetrics.sidebarWidth - 2 * 10 - 2 * 10 - 18 - 10
    }

    private func width(of title: String, weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: weight)
        return (title as NSString).size(withAttributes: [.font: font]).width
    }

    /// At least this much slack over the longest title. "Fits by half a point"
    /// is not a fit: SwiftUI's own metrics for the same string disagree with
    /// `NSFont` by fractions, and a row sitting on that edge wraps in the app
    /// while measuring fine here — which is exactly how "Pointer Highlight"
    /// jumped. The slack is what makes the difference observable.
    private let requiredSlack: CGFloat = 12

    func testEverySidebarTitleFitsWithRoomToSpareWhenSelected() {
        for area in SettingsArea.allCases {
            let selected = width(of: area.title, weight: .semibold)
            XCTAssertGreaterThanOrEqual(
                availableTextWidth - selected, requiredSlack,
                "\"\(area.title)\" leaves \(availableTextWidth - selected) pt of slack in semibold; a row on the edge wraps the moment it is selected"
            )
        }
    }
}
