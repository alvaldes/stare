import XCTest
@testable import StareCore

/// The dangerous half of the overflow batch's migration (S3): the shipped bar
/// changed, and a saved layout that nobody touched is upgraded once. What must
/// never happen is the other half — a layout the *user* built being rewritten
/// on every load because it happens to look like the old shipped bar.
final class ToolbarOverflowMigrationTests: XCTestCase {

    /// The bar v0.5 shipped, in the order v0.5 persisted it.
    private static let v05Items: [ToolbarLayoutItem] = [
        .tool(.select), .separator,
        .tool(.pen), .tool(.highlighter), .separator,
        .tool(.line), .tool(.arrow), .tool(.rectangle), .tool(.ellipse), .separator,
        .tool(.text), .tool(.number), .separator,
        .tool(.blur), .tool(.spotlight), .tool(.laser), .separator,
        .tool(.eraser),
    ]

    private func decode(_ json: String) throws -> ToolbarToolLayout {
        try JSONDecoder().decode(ToolbarToolLayout.self, from: Data(json.utf8))
    }

    private func roundTrip(_ layout: ToolbarToolLayout) throws -> ToolbarToolLayout {
        try JSONDecoder().decode(ToolbarToolLayout.self, from: try JSONEncoder().encode(layout))
    }

    /// The unchanged saved bar still upgrades — the point of the batch.
    func testTheUntouchedV05BarUpgradesOnceAndStaysUpgraded() throws {
        let identifiers = Self.v05Items.map { "\"" + $0.identifier + "\"" }.joined(separator: ",")
        XCTAssertEqual(try decode(#"{"items":["# + identifiers + #"],"pool":[]}"#), .standard)
        // Reloading what this build wrote changes nothing more.
        XCTAssertEqual(try roundTrip(.standard), .standard)
    }

    /// And the half that must not happen: a bar the user rebuilt to hold every
    /// tool again is their arrangement, not the shipped default. Saving it and
    /// loading it back — the next launch — has to leave it exactly as it was.
    func testAFullBarTheUserRebuiltSurvivesASave() throws {
        let rebuilt = ToolbarToolLayout(items: Self.v05Items, pool: [])
        XCTAssertEqual(rebuilt.visibleTools.count, Tool.allCases.count)
        XCTAssertTrue(rebuilt.pool.isEmpty)
        // Pre-condition: this arrangement is exactly the old shipped one, which
        // is what made it vulnerable.
        XCTAssertEqual(rebuilt.items, ToolbarToolLayout.legacyStandardItems)
        XCTAssertEqual(try roundTrip(rebuilt), rebuilt)
    }

    /// The same guarantee after the app has saved once: whatever a build of
    /// this version stored is never migrated again.
    func testOnceSavedByThisBuildALayoutIsNeverUpgradedAgain() throws {
        let rebuilds = [
            ToolbarToolLayout(items: Self.v05Items, pool: []),
            ToolbarToolLayout(items: Self.v05Items.dropLast(2).map { $0 }, pool: [.eraser, .laser]),
            ToolbarToolLayout(items: ToolbarToolLayout.standard.items, pool: ToolbarToolLayout.standard.pool),
        ]
        for layout in rebuilds {
            XCTAssertEqual(try roundTrip(layout), layout)
        }
    }

    /// A rearranged full bar is a choice, not the shipped default: one tool
    /// moved out of the v0.5 order must survive untouched.
    func testARearrangedFullBarIsLeftExactlyAsSaved() throws {
        var swapped = Self.v05Items
        swapped.swapAt(2, 3)
        let json = #"{"items":["# + swapped.map { "\"" + $0.identifier + "\"" }.joined(separator: ",") + #"],"pool":[]}"#
        let layout = try decode(json)
        XCTAssertEqual(layout.visibleTools.count, Tool.allCases.count)
        XCTAssertTrue(layout.pool.isEmpty)
        XCTAssertEqual(layout.items.prefix(4), [.tool(.select), .separator, .tool(.highlighter), .tool(.pen)])
    }

    /// The upgrade may move the bar and nothing else: every other setting in
    /// the stored blob survives a load that migrates the layout.
    func testTheUpgradeTouchesNothingElseInTheStoredBlob() throws {
        var original = AppPreferences.standard
        original.general.showArmedFrame = false
        original.general.scope = .all
        original.general.palettePlacement = .fixed
        original.general.laserLifetime = .five
        original.general.toolbarOrientation = .vertical
        original.general.toolbarBorder = .right
        original.general.persistsSession = false
        original.tool = .spotlight
        original.toolShortcuts.assigning("Q", to: .blur)
        original.hasCompletedOnboarding = true

        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(original)) as? [String: Any]
        )
        var general = try XCTUnwrap(object["general"] as? [String: Any])
        let identifiers = Self.v05Items.map { "\"" + $0.identifier + "\"" }.joined(separator: ",")
        general["toolbarTools"] = try JSONSerialization.jsonObject(
            with: Data((#"{"items":["# + identifiers + #"],"pool":[]}"#).utf8)
        )
        object["general"] = general

        let decoded = try JSONDecoder().decode(
            AppPreferences.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )
        var expected = original
        expected.general.toolbarTools = .standard
        XCTAssertEqual(decoded, expected)
        XCTAssertEqual(decoded.general.toolbarBorder, .right)
        XCTAssertEqual(decoded.toolShortcuts[.blur], "Q")
    }

    /// The shipped bar itself is stable across a save.
    func testTheShippedBarRoundTrips() throws {
        XCTAssertEqual(try roundTrip(.standard), .standard)
    }
}
