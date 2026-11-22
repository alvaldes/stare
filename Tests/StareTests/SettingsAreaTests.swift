import XCTest
@testable import Stare

/// The sidebar's contract: one object per pane, every pane in exactly one
/// group, and the groups in the order the window shows them. A pane that loses
/// its group disappears from the sidebar without any other test noticing.
final class SettingsAreaTests: XCTestCase {
    func testEveryPaneBelongsToExactlyOneGroup() {
        let grouped = SettingsGroup.allCases.flatMap(\.areas)

        XCTAssertEqual(
            grouped.count,
            SettingsArea.allCases.count,
            "a pane is listed twice or missing from every group"
        )
        XCTAssertEqual(
            Set(grouped),
            Set(SettingsArea.allCases),
            "a pane has no group, so the sidebar would never draw it"
        )
    }

    func testGroupsKeepTheSidebarOrderAndSize() {
        // The published map: one capture pane, three drawing panes, the
        // pointer, the board, and four system panes.
        XCTAssertEqual(SettingsGroup.allCases.map(\.title), ["Capture", "Draw", "Pointer", "Board", "System"])
        XCTAssertEqual(SettingsGroup.allCases.map { $0.areas.count }, [1, 3, 1, 1, 4])
        XCTAssertEqual(
            SettingsGroup.allCases.flatMap(\.areas),
            SettingsArea.allCases,
            "the sidebar order must follow the enum, so the switch and the list never disagree"
        )
    }

    func testTheBarAndTheOverlayAreNoLongerInsideGeneral() {
        XCTAssertEqual(SettingsArea.bar.group, .draw)
        XCTAssertEqual(SettingsArea.overlay.group, .draw)
        XCTAssertEqual(
            SettingsArea.general.group.areas,
            [.shortcuts, .general, .permissions, .about],
            "General keeps startup and updates; drawing, the bar and the laser moved out"
        )
    }

    func testTitlesAndSymbolsAreUnique() {
        let titles = SettingsArea.allCases.map(\.title)
        let symbols = SettingsArea.allCases.map(\.symbol)

        XCTAssertEqual(Set(titles).count, titles.count, "two panes share a title")
        XCTAssertEqual(Set(symbols).count, symbols.count, "two panes share an icon")
    }
}
