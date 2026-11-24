import Foundation
import XCTest
@testable import StareCore

final class GeneralPreferencesTests: XCTestCase {
    // MARK: Defaults (T6 slice 1 / S4)

    func testStandardMatchesTodayDefaults() {
        XCTAssertTrue(GeneralPreferences.standard.showArmedFrame)
        XCTAssertEqual(GeneralPreferences.standard.scope, .active)
        XCTAssertEqual(GeneralPreferences.standard.palettePlacement, .cursor)
        XCTAssertEqual(GeneralPreferences.standard.laserLifetime, .twoPointFive)
        // T9/S12: a fresh install keeps the bar exactly where it opens today —
        // a horizontal row docked at the top edge.
        XCTAssertEqual(GeneralPreferences.standard.toolbarOrientation, .horizontal)
        XCTAssertEqual(GeneralPreferences.standard.toolbarBorder, .top)
        XCTAssertEqual(GeneralPreferences(), GeneralPreferences.standard)
    }

    // MARK: Cases and titles

    func testOverlayScopeOffersExactlyTodaysCasesAndTitles() {
        XCTAssertEqual(OverlayScope.allCases, [.all, .active])
        XCTAssertEqual(OverlayScope.all.title, "Every display")
        XCTAssertEqual(OverlayScope.active.title, "Only the active display")
    }

    func testPalettePlacementOffersExactlyTodaysCasesAndTitles() {
        XCTAssertEqual(PalettePlacement.allCases, [.cursor, .frontWindow, .fixed])
        XCTAssertEqual(PalettePlacement.cursor.title, "Under the pointer")
        XCTAssertEqual(PalettePlacement.frontWindow.title, "On the display of the front window")
        XCTAssertEqual(PalettePlacement.fixed.title, "On the last used display")
    }

    func testToolbarOrientationOffersExactlyTheTwoCasesAndTitles() {
        XCTAssertEqual(ToolbarOrientation.allCases, [.horizontal, .vertical])
        XCTAssertEqual(ToolbarOrientation.horizontal.title, "Horizontal")
        XCTAssertEqual(ToolbarOrientation.vertical.title, "Vertical")
    }

    func testToolbarBorderOffersExactlyTheFourCasesAndTitles() {
        XCTAssertEqual(ToolbarBorder.allCases, [.top, .bottom, .left, .right])
        XCTAssertEqual(ToolbarBorder.top.title, "Top")
        XCTAssertEqual(ToolbarBorder.bottom.title, "Bottom")
        XCTAssertEqual(ToolbarBorder.left.title, "Left")
        XCTAssertEqual(ToolbarBorder.right.title, "Right")
    }

    func testLaserLifetimeOffersExactlyTodaysPickerValuesAndTitles() {
        XCTAssertEqual(LaserLifetime.allCases.map(\.rawValue), [1, 2, 2.5, 3, 5])
        XCTAssertEqual(LaserLifetime.one.title, "1 seconds")
        XCTAssertEqual(LaserLifetime.two.title, "2 seconds")
        XCTAssertEqual(LaserLifetime.twoPointFive.title, "2.5 seconds")
        XCTAssertEqual(LaserLifetime.three.title, "3 seconds")
        XCTAssertEqual(LaserLifetime.five.title, "5 seconds")
    }

    // MARK: Lenient decoding

    func testUnknownScopeFallsBackToDefaultAndKeepsTheRest() throws {
        let general = try Self.decode(
            #"{"showArmedFrame":false,"scope":"galaxy","palettePlacement":"fixed","laserLifetime":3}"#
        )
        XCTAssertEqual(general.scope, .active, "an unknown scope falls back to the default, not to all displays")
        XCTAssertFalse(general.showArmedFrame)
        XCTAssertEqual(general.palettePlacement, .fixed)
        XCTAssertEqual(general.laserLifetime, .three)
    }

    func testUnknownPalettePlacementFallsBackToDefaultAndKeepsTheRest() throws {
        let general = try Self.decode(
            #"{"showArmedFrame":false,"scope":"active","palettePlacement":"sky","laserLifetime":3}"#
        )
        XCTAssertEqual(general.palettePlacement, .cursor)
        XCTAssertEqual(general.scope, .active)
        XCTAssertEqual(general.laserLifetime, .three)
    }

    func testUnknownLaserLifetimeFallsBackToDefaultAndKeepsTheRest() throws {
        let general = try Self.decode(
            #"{"showArmedFrame":false,"scope":"active","palettePlacement":"fixed","laserLifetime":4}"#
        )
        XCTAssertEqual(general.laserLifetime, .twoPointFive)
        XCTAssertEqual(general.scope, .active)
        XCTAssertEqual(general.palettePlacement, .fixed)
    }

    func testWronglyTypedShowArmedFrameFallsBackToDefault() throws {
        let general = try Self.decode(#"{"showArmedFrame":"yes"}"#)
        XCTAssertTrue(general.showArmedFrame)
    }

    // MARK: Session persistence (T10/S11)

    func testSessionPersistenceDefaultsToOn() {
        // S11: by default what is drawn and the whiteboard pages persist
        // until the machine restarts — the switch ships on.
        XCTAssertTrue(GeneralPreferences.standard.persistsSession)
        XCTAssertTrue(GeneralPreferences().persistsSession)
    }

    func testSessionPersistenceDecodesLenientlyAndKeepsTheRest() throws {
        // A blob written before the field existed keeps the shipped default.
        let missing = try Self.decode(#"{"showArmedFrame":false,"scope":"active"}"#)
        XCTAssertTrue(missing.persistsSession)
        XCTAssertFalse(missing.showArmedFrame)
        XCTAssertEqual(missing.scope, .active)

        // A wrongly typed value falls back to the default, per-field.
        let wronglyTyped = try Self.decode(#"{"persistsSession":"yes"}"#)
        XCTAssertTrue(wronglyTyped.persistsSession)

        // The off choice survives decoding like any other value.
        let off = try Self.decode(#"{"persistsSession":false,"showArmedFrame":true}"#)
        XCTAssertFalse(off.persistsSession)
        XCTAssertTrue(off.showArmedFrame)
    }

    func testSessionPersistenceRoundTrips() throws {
        var general = GeneralPreferences.standard
        general.persistsSession = false

        let data = try JSONEncoder().encode(general)
        let decoded = try JSONDecoder().decode(GeneralPreferences.self, from: data)
        XCTAssertEqual(decoded, general)
        XCTAssertFalse(decoded.persistsSession, "the off choice must survive a round trip")
    }

    func testUnknownToolbarOrientationFallsBackToDefaultAndKeepsTheRest() throws {
        let general = try Self.decode(
            #"{"showArmedFrame":false,"scope":"active","palettePlacement":"fixed","laserLifetime":3,"toolbarOrientation":"diagonal","toolbarBorder":"left"}"#
        )
        XCTAssertEqual(general.toolbarOrientation, .horizontal)
        // T3/S4: the decoded border is never left inconsistent with the
        // orientation, so the legacy `left` re-docks on the horizontal row's
        // own default edge.
        XCTAssertEqual(general.toolbarBorder, .top)
        XCTAssertEqual(general.scope, .active)
        XCTAssertEqual(general.laserLifetime, .three)
    }

    func testUnknownToolbarBorderFallsBackToDefaultAndKeepsTheRest() throws {
        let general = try Self.decode(
            #"{"scope":"active","palettePlacement":"fixed","laserLifetime":3,"toolbarOrientation":"vertical","toolbarBorder":"sky"}"#
        )
        // T3/S4: the unknown raw value first falls back to the global
        // default, and that guess is then made valid for the stored
        // orientation — so the vertical bar never keeps a top/bottom dock.
        XCTAssertEqual(general.toolbarBorder, .left)
        XCTAssertEqual(general.toolbarOrientation, .vertical)
        XCTAssertEqual(general.scope, .active)
        XCTAssertEqual(general.laserLifetime, .three)
    }

    func testMissingFieldsFallBackToDefaults() throws {
        XCTAssertEqual(try Self.decode("{}"), GeneralPreferences.standard)
    }

    // MARK: Toolbar item layout (T6/S5)

    /// Shorthand for the stored layout the Settings organiser and the bar
    /// read.
    private static func decodeLayout(_ json: String) throws -> ToolbarToolLayout {
        try JSONDecoder().decode(ToolbarToolLayout.self, from: Data(json.utf8))
    }

    /// The bar a fresh install must draw, pinned literally: every tool in
    /// the documented order, a separator exactly between the tool families —
    /// the dividers the grouped bar has always placed.
    private static let standardItems: [ToolbarLayoutItem] = [
        .tool(.select), .separator,
        .tool(.pen), .tool(.highlighter), .separator,
        .tool(.line), .tool(.arrow), .tool(.rectangle), .tool(.ellipse), .separator,
        .tool(.text), .tool(.number), .separator,
        .tool(.blur), .tool(.spotlight), .tool(.laser), .separator,
        .tool(.eraser),
    ]

    func testStandardToolbarLayoutReproducesTodaysBar() {
        XCTAssertEqual(ToolbarToolLayout.standard.items, Self.standardItems)
        // Separators are placeable items, not automatic family grouping: the
        // shipped layout simply holds them at the family boundaries.
        XCTAssertEqual(ToolbarToolLayout.standard.items.filter { $0 == .separator }.count, 5)
        XCTAssertEqual(ToolbarToolLayout.standard.visibleTools, Tool.toolbarGroups.flatMap { $0 })
        XCTAssertTrue(ToolbarToolLayout.standard.pool.isEmpty)
        XCTAssertEqual(GeneralPreferences.standard.toolbarTools, .standard)
    }

    /// Taking a placed separator back out: the first one goes, the rest of
    /// the bar keeps its order.
    func testRemovingAPlacedSeparatorRemovesTheFirstOneOnly() {
        let layout = ToolbarToolLayout(items: Self.standardItems)
        let without = layout.removing(.separator)
        var expected = Self.standardItems
        expected.remove(at: 1)
        XCTAssertEqual(without.items, expected)
    }

    func testUnknownIdentifiersAreDroppedWhereverTheyAppear() throws {
        // The stored document is identifier strings; anything neither a tool
        // identifier nor the separator token is dropped, in the bar and in
        // the pool alike, and pool entries for tools already on the bar drop
        // too.
        let layout = try Self.decodeLayout(
            #"{"items":["tool:pen","tool:galaxy","separator","tool:select","tool:galaxy"],"pool":["laser","galaxy","laser","select"]}"#
        )
        XCTAssertEqual(layout.items, [.tool(.pen), .separator, .tool(.select)])
        XCTAssertEqual(layout.pool, [.laser] + ToolbarToolLayout.defaultOrder.filter { ![.select, .pen, .laser].contains($0) })
    }

    func testToolsTheStoredLayoutNeverMentionsLandInThePoolNeverOnTheBar() throws {
        // A tool a stored layout never mentions — a future build's tool, or
        // anything a document lost — must never appear silently on the bar:
        // it lands in the pool, in the documented default order.
        let layout = try Self.decodeLayout(
            #"{"items":["tool:pen","tool:highlighter"],"pool":[]}"#
        )
        XCTAssertEqual(layout.visibleTools, [.pen, .highlighter])
        XCTAssertEqual(layout.pool, ToolbarToolLayout.defaultOrder.filter { ![.pen, .highlighter].contains($0) })
    }

    func testDuplicateStoredToolsCollapseToTheirFirstOccurrence() throws {
        let layout = try Self.decodeLayout(
            #"{"items":["tool:select","tool:pen","tool:select","tool:eraser"],"pool":[]}"#
        )
        XCTAssertEqual(layout.items, [.tool(.select), .tool(.pen), .tool(.eraser)])
        XCTAssertEqual(layout.visibleTools.filter { $0 == .select }.count, 1)
        XCTAssertEqual(layout.pool, ToolbarToolLayout.defaultOrder.filter { ![.select, .pen, .eraser].contains($0) })
    }

    func testLeadingTrailingAndRepeatedSeparatorsAreCleaned() throws {
        // The bar cannot render an empty end: after normalisation a
        // separator only exists between two tools.
        let layout = try Self.decodeLayout(
            #"{"items":["separator","tool:pen","separator","separator","tool:select","separator"],"pool":[]}"#
        )
        XCTAssertEqual(layout.items, [.tool(.pen), .separator, .tool(.select)])
    }

    func testAStoredBarWithoutAnyToolIsRefused() throws {
        // Every one of these corrupt documents would leave the bar with no
        // tool at all: the layout is refused and the shipped bar comes back.
        XCTAssertEqual(try Self.decodeLayout("{}"), .standard)
        XCTAssertEqual(try Self.decodeLayout(#"{"items":[],"pool":[]}"#), .standard)
        XCTAssertEqual(try Self.decodeLayout(#"{"items":["separator","separator"],"pool":[]}"#), .standard)
        XCTAssertEqual(try Self.decodeLayout(#"{"items":["separator"],"pool":["pen"]}"#), .standard)
        let general = try Self.decode(#"{"toolbarOrientation":"vertical","toolbarTools":{"items":["separator"],"pool":[]}}"#)
        XCTAssertEqual(general.toolbarTools, .standard)
        XCTAssertEqual(general.toolbarOrientation, .vertical)
    }

    // MARK: v0.4 decode migration (T6/S5)

    func testV0_4StoredLayoutDecodesIntoTheNewShapeWithTheSameVisibleSetAndOrder() throws {
        let layout = try Self.decodeLayout(
            #"{"tools":["select","pen","highlighter","line","arrow","rectangle","ellipse","text","number","blur","laser","eraser"],"hidden":["number"]}"#
        )
        // Same visible set and order the v0.4 bar drew, with the family
        // dividers it drew too. The spotlight arrived after that layout was
        // written, so it is not on the bar: a tool the stored document never
        // placed waits in the pool, it does not push itself in.
        XCTAssertEqual(
            layout.visibleTools,
            ToolbarToolLayout.defaultOrder.filter { $0 != .number && $0 != .spotlight }
        )
        XCTAssertEqual(layout.items, [
            .tool(.select), .separator,
            .tool(.pen), .tool(.highlighter), .separator,
            .tool(.line), .tool(.arrow), .tool(.rectangle), .tool(.ellipse), .separator,
            .tool(.text), .separator, .tool(.blur), .tool(.laser), .separator,
            .tool(.eraser),
        ])
        // ...and the hidden tool lands in the pool instead of the old
        // hidden set.
        XCTAssertEqual(layout.pool, [.number, .spotlight])
    }

    func testV0_4StoredLayoutKeepsToolOrderAcrossFamiliesWithDividersWhereTheOldBarDrewThem() throws {
        // A reordered v0.4 layout never had explicit separators: the old bar
        // drew a divider wherever the family changed, so that is exactly
        // where the migrated one places them.
        let layout = try Self.decodeLayout(
            #"{"tools":["pen","select","blur"],"hidden":[]}"#
        )
        XCTAssertEqual(layout.visibleTools, [.pen, .select, .blur])
        XCTAssertEqual(layout.items, [.tool(.pen), .separator, .tool(.select), .separator, .tool(.blur)])
        XCTAssertEqual(layout.pool, ToolbarToolLayout.defaultOrder.filter { ![.select, .pen, .blur].contains($0) })
    }

    func testV0_4EmptyStoredListStillFallsBackToTheDefault() throws {
        XCTAssertEqual(try Self.decodeLayout(#"{"tools":[],"hidden":[]}"#), .standard)
    }

    func testV0_4LayoutThatHidesEveryToolIsRefused() throws {
        let layout = try Self.decodeLayout(
            #"{"tools":["select","pen","highlighter","line","arrow","rectangle","ellipse","text","number","blur","laser","eraser"],"hidden":["select","pen","highlighter","line","arrow","rectangle","ellipse","text","number","blur","laser","eraser"]}"#
        )
        XCTAssertEqual(layout, .standard)
    }

    func testV0_4UnknownIdentifiersAreDroppedAndDuplicatesCollapse() throws {
        let layout = try Self.decodeLayout(#"{"tools":["pen","galaxy","select","pen"],"hidden":[]}"#)
        // The two stored tools keep their order; anything the list never
        // mentions waits in the pool instead of silently joining the bar.
        XCTAssertEqual(layout.visibleTools, [.pen, .select])
        XCTAssertEqual(layout.pool, ToolbarToolLayout.defaultOrder.filter { ![.select, .pen].contains($0) })
    }

    // MARK: Organiser mutations (T6/S5)

    func testInsertingAToolTakesItOffThePoolAtTheDroppedPosition() {
        var layout = ToolbarToolLayout.standard
        layout = layout.removing(.tool(.laser))
        XCTAssertTrue(layout.pool.contains(.laser))
        XCTAssertFalse(layout.visibleTools.contains(.laser))

        // Dropping it before the eraser puts it exactly there.
        let eraserIndex = layout.items.firstIndex(of: .tool(.eraser))!
        layout = layout.inserting(.tool(.laser), at: eraserIndex)
        XCTAssertEqual(layout.items[eraserIndex], .tool(.laser))
        XCTAssertFalse(layout.pool.contains(.laser))
    }

    func testInsertingASeparatorNextToAnotherSeparatorCollapsesIntoOne() {
        let layout = ToolbarToolLayout(items: [.tool(.pen), .tool(.eraser)])
        let collapsed = layout.inserting(.separator, at: 1).inserting(.separator, at: 1)
        XCTAssertEqual(collapsed.items, [.tool(.pen), .separator, .tool(.eraser)])
    }

    func testMovingReordersWithinTheBarWithoutTouchingThePool() {
        var layout = ToolbarToolLayout.standard
        layout = layout.removing(.tool(.laser))
        XCTAssertTrue(layout.pool.contains(.laser))

        // Move the pen in front of the select: index semantics are the
        // insert position in the list as it would be without the item.
        let moved = layout.moving(.tool(.pen), to: 0)
        XCTAssertEqual(moved.items.first, .tool(.pen))
        XCTAssertEqual(moved.items[1], .tool(.select))
        XCTAssertEqual(moved.pool, layout.pool)
        XCTAssertEqual(moved.visibleTools.first, .pen)
    }

    func testMovingAnItemTheBarDoesNotHoldChangesNothing() {
        let layout = ToolbarToolLayout.standard
        XCTAssertEqual(layout.moving(.tool(.select), to: 0), layout)
    }

    // MARK: Exhaustive moving invariant

    /// Exhaustive termination-and-duplication net (independent verifier):
    /// over EVERY normalised bar whose items are drawn from the alphabet
    /// [pen, eraser, arrow(held on the bar), separator] up to six items long,
    /// with arrow hidden (in the pool) in the variant where it is not on the
    /// bar, moving every distinct item to every index from -2 to count+2
    /// must: stay a normalisation fixed point, keep the tool set and count,
    /// keep the item count and the separator count, never strand a leading,
    /// trailing or adjacent separator, and leave the pool untouched. The net
    /// is cheap — a few thousand pure-array calls — so it can live in the
    /// suite.
    func testMovingIsInvariantOnEveryNormalisedBarOverThePenEraserArrowSeparatorAlphabet() {
        let alphabet: [ToolbarLayoutItem] = [.tool(.pen), .tool(.eraser), .tool(.arrow), .separator]
        // Every sequence over the alphabet, up to six items, normalised; the
        // arrow-hidden variants come from the pool the normalisation passes.
        var layouts: [ToolbarToolLayout] = []
        var seen = Set<ToolbarToolKey>()
        struct ToolbarToolKey: Hashable {
            let items: [ToolbarLayoutItem]
            let pool: [Tool]
        }
        func enumerate(_ prefix: [ToolbarLayoutItem], _ remaining: Int) {
            if remaining == 0 { return }
            for item in alphabet {
                let candidate = prefix + [item]
                // Two pool variants wherever the arrow is not on the bar, so
                // its hidden form is exercised too; normalisation falls the
                // arrow-on-bar variant back to the other one, and the set
                // dedupes what normalisation collapses.
                let hidden = ToolbarToolLayout(items: candidate, pool: [.arrow])
                let shown = ToolbarToolLayout(items: candidate, pool: [])
                for layout in [hidden, shown] where seen.insert(
                    ToolbarToolKey(items: layout.items, pool: layout.pool)
                ).inserted {
                    layouts.append(layout)
                }
                enumerate(candidate, remaining - 1)
            }
        }
        enumerate([], 6)
        XCTAssertTrue(
            layouts.contains(ToolbarToolLayout.standard),
            "the refused sequences fall back to the shipped bar, which is a normalised bar of the alphabet too")

        var calls = 0
        for layout in layouts {
            let separatorCount = layout.items.filter { $0.tool == nil }.count
            for item in Set(layout.items) {
                for index in -2...(layout.items.count + 2) {
                    calls += 1
                    let moved = layout.moving(item, to: index)
                    let context = "moving \(item), to \(index) on \(layout.items)"
                    XCTAssertEqual(
                        moved, ToolbarToolLayout(items: moved.items, pool: moved.pool),
                        "the result must be a normalisation fixed point — \(context)")
                    XCTAssertEqual(
                        Set(moved.visibleTools), Set(layout.visibleTools),
                        "the tool set must be unchanged — \(context)")
                    XCTAssertEqual(
                        moved.visibleTools.count, layout.visibleTools.count,
                        "the tool count must be unchanged — \(context)")
                    XCTAssertEqual(
                        moved.items.count, layout.items.count,
                        "the item count must be unchanged — \(context)")
                    XCTAssertEqual(
                        moved.items.filter { $0.tool == nil }.count, separatorCount,
                        "the separator count must be unchanged — \(context)")
                    XCTAssertEqual(
                        moved.pool, layout.pool,
                        "the pool must be untouched — \(context)")
                    for (index, item) in moved.items.enumerated() where item.tool == nil {
                        XCTAssertTrue(
                            index > 0 && index < moved.items.count - 1,
                            "no leading or trailing separator — \(context): \(moved.items)")
                        XCTAssertTrue(
                            index == 0 || moved.items[index - 1].tool != nil,
                            "no adjacent separators — \(context): \(moved.items)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(calls, 500, "the net must actually be exhaustive over the alphabet")
    }

    // MARK: What cannot leave the bar (T3/S2)

    /// The bar keeps its first tool: the leading tool cannot leave, every
    /// other item — placed separators included — can. This is the one
    /// predicate the pool's handlers and the preview's fixed marking both
    /// read, and a one-tool bar's only tool is its first, which is also the
    /// case `removing` itself refuses.
    func testTheLeadingToolCannotLeaveWhileEveryOtherItemCan() {
        let layout = ToolbarToolLayout(items: [.tool(.pen), .separator, .tool(.eraser)])
        XCTAssertFalse(
            layout.canLeave(.tool(.pen)),
            "the bar's first tool cannot leave")
        XCTAssertTrue(layout.canLeave(.tool(.eraser)))
        XCTAssertTrue(layout.canLeave(.separator), "a placed separator always can (T4/S3)")
        XCTAssertTrue(layout.canLeave(.tool(.select)), "a pool tool is never the bar's first tool")

        // A one-tool bar's only tool is also its first tool.
        let solo = ToolbarToolLayout(items: [.tool(.pen)])
        XCTAssertFalse(solo.canLeave(.tool(.pen)))
    }

    // MARK: Reordering in place across a placed separator (T5/S5)

    /// T5/S5: a bar-to-bar move used to run through normalisation, which ate
    /// a separator the move stranded at a bar end — [pen, sep, eraser] with
    /// the pen moved onto the eraser's after-edge came back [eraser, pen]
    /// and the only way to keep the divider was a round trip through the
    /// pool. Now the moved item lands where it was dropped and the orphaned
    /// separator relocates to the nearest legal slot.
    func testMovingAToolAcrossAPlacedSeparatorRelocatesTheSeparatorInsteadOfDroppingIt() {
        let layout = ToolbarToolLayout(items: [.tool(.pen), .separator, .tool(.eraser)])
        let moved = layout.moving(.tool(.pen), to: 2)
        XCTAssertEqual(
            moved.items,
            [.tool(.eraser), .separator, .tool(.pen)],
            "the pen lands where it was dropped and the separator it crossed is relocated, not deleted")
    }

    /// A separator stranded at a bar's tail by a move slides to the nearest
    /// legal slot instead of being eaten.
    func testAMovedToolLeavesAnOrphanedTrailingSeparatorInItsNearestLegalSlot() {
        let layout = ToolbarToolLayout(items: [.tool(.pen), .separator, .tool(.eraser)])
        let moved = layout.moving(.tool(.eraser), to: 0)
        XCTAssertEqual(
            moved.items,
            [.tool(.eraser), .separator, .tool(.pen)],
            "the trailing separator is relocated to the bar's only legal slot")
    }

    /// Reordering inside one group crosses no separator and must touch none.
    func testReorderingWithinAGroupKeepsEverySeparator() {
        let layout = ToolbarToolLayout(items: [
            .tool(.pen), .tool(.eraser), .separator, .tool(.arrow),
        ])
        let moved = layout.moving(.tool(.pen), to: 1)
        XCTAssertEqual(
            moved.items,
            [.tool(.eraser), .tool(.pen), .separator, .tool(.arrow)],
            "in-place reordering inside one group needs no pool round trip and touches no separator")
    }

    /// Two consecutive in-place reorders: each lands the moved item where the
    /// drop said, repairs its own stranded separator, and the end state is
    /// predictable with no separator lost or duplicated.
    func testTwoConsecutiveReordersEndInAPredictableBar() {
        var layout = ToolbarToolLayout(items: [
            .tool(.pen), .separator, .tool(.eraser), .tool(.arrow),
        ])
        layout = layout.moving(.tool(.pen), to: 3)
        XCTAssertEqual(
            layout.items,
            [.tool(.eraser), .separator, .tool(.arrow), .tool(.pen)],
            "first reorder: the crossed separator follows into the nearest legal slot")
        layout = layout.moving(.tool(.eraser), to: 3)
        XCTAssertEqual(
            layout.items,
            [.tool(.arrow), .separator, .tool(.pen), .tool(.eraser)],
            "second reorder: still in place, and still exactly one separator")
    }

    func testASeparatorClampsIntoTheSlotsBetweenTwoTools() {
        let layout = ToolbarToolLayout(items: [.tool(.pen), .separator, .tool(.eraser)])
        // A stray drag before the first item or after the last one must not
        // strand the separator where normalisation would erase it: it stays
        // in the only between-two-tools slot.
        XCTAssertEqual(layout.moving(.separator, to: 0), layout)
        XCTAssertEqual(layout.moving(.separator, to: layout.items.count), layout)
        // And one dropped in front of the leading tool lands between the
        // two tools instead of at the bar's empty end.
        let plain = ToolbarToolLayout(items: [.tool(.pen), .tool(.eraser)])
        XCTAssertEqual(plain.inserting(.separator, at: 0), layout)
    }

    func testASeparatorCannotJoinAOneToolBar() {
        let layout = ToolbarToolLayout(items: [.tool(.pen)])
        XCTAssertEqual(layout.inserting(.separator, at: 1), layout)
        XCTAssertEqual(layout.moving(.separator, to: 0), layout)
    }

    func testRemovingTheLastToolIsRefused() {
        var only = ToolbarToolLayout.standard
        for tool in ToolbarToolLayout.defaultOrder where tool != .pen {
            only = only.removing(.tool(tool))
        }
        XCTAssertEqual(only.visibleTools, [.pen])
        XCTAssertEqual(only.removing(.tool(.pen)), only)
    }

    func testRemovingAToolDropsItIntoThePoolAtTheGivenPlace() {
        var layout = ToolbarToolLayout.standard
        layout = layout.removing(.tool(.laser))
        layout = layout.removing(.tool(.eraser))
        XCTAssertTrue(layout.pool.contains(.laser))

        layout = layout.inserting(.tool(.eraser), at: 0).removing(.tool(.select), intoPoolAt: 0)
        XCTAssertEqual(layout.pool.first, .select)
        XCTAssertFalse(layout.visibleTools.contains(.select))
        XCTAssertFalse(layout.items.contains(.tool(.select)))
    }

    func testPoolReorderingPersists() {
        let layout = ToolbarToolLayout(items: [.tool(.pen)], pool: [])
        XCTAssertEqual(layout.pool, ToolbarToolLayout.defaultOrder.filter { $0 != .pen })
        let reordered = layout.movingInPool(.laser, to: 0)
        XCTAssertEqual(reordered.pool.first, .laser)
        XCTAssertEqual(Set(reordered.pool), Set(ToolbarToolLayout.defaultOrder).subtracting([.pen]))
    }

    func testPoolNormalisesDuplicatesAndBarMembersAway() {
        let layout = ToolbarToolLayout(items: ToolbarToolLayout.standard.items, pool: [.laser, .laser, .select, .number])
        // Every one of those tools is already on the bar: the pool keeps
        // only the tools that are genuinely off it.
        XCTAssertTrue(layout.pool.isEmpty)
    }

    func testToolbarLayoutRoundTripsThroughGeneralPreferences() throws {
        var general = GeneralPreferences.standard
        general.toolbarTools = ToolbarToolLayout(items: [
            .tool(.select), .separator, .tool(.pen), .tool(.eraser),
        ], pool: [.laser, .number])

        let data = try JSONEncoder().encode(general)
        let decoded = try JSONDecoder().decode(GeneralPreferences.self, from: data)
        XCTAssertEqual(decoded, general)
        // The pool order is part of the document: a reordered pool survives
        // a relaunch, and the pool always lists every off-bar tool.
        XCTAssertEqual(Array(decoded.toolbarTools.pool.prefix(2)), [.laser, .number])
        XCTAssertEqual(
            Set(decoded.toolbarTools.pool),
            Set(ToolbarToolLayout.defaultOrder).subtracting([
                .select, .pen, .eraser,
            ])
        )
    }

    // MARK: Round trip

    func testRoundTripsEveryValue() throws {
        var general = GeneralPreferences.standard
        general.showArmedFrame = false
        general.scope = .active
        general.palettePlacement = .fixed
        general.laserLifetime = .five
        general.toolbarOrientation = .vertical
        general.toolbarBorder = .right

        let data = try JSONEncoder().encode(general)
        let decoded = try JSONDecoder().decode(GeneralPreferences.self, from: data)
        XCTAssertEqual(decoded, general)
    }

    // MARK: Migration from the legacy per-key preferences

    func testMigrationReadsEveryLegacyKey() {
        let store = InMemoryPreferenceStore()
        store.set(false, forKey: "showArmedFrame")
        store.set("active", forKey: "overlayScope")
        store.set("fixed", forKey: "palettePlacement")
        store.set(5.0, forKey: "laserLifetime")

        let general = PreferencesMigration.migratedGeneralPreferences(in: store)
        XCTAssertEqual(general?.showArmedFrame, false)
        XCTAssertEqual(general?.scope, .active)
        XCTAssertEqual(general?.palettePlacement, .fixed)
        XCTAssertEqual(general?.laserLifetime, .five)
    }

    func testMigrationFromEachSingleLegacyKeyKeepsDefaultsForTheRest() {
        let frameStore = InMemoryPreferenceStore()
        frameStore.set(false, forKey: "showArmedFrame")
        var general = PreferencesMigration.migratedGeneralPreferences(in: frameStore)
        XCTAssertNotNil(general)
        XCTAssertFalse(general!.showArmedFrame)
        XCTAssertEqual(general?.scope, .active, "a legacy key leaves the current default, the active display")
        XCTAssertEqual(general?.palettePlacement, .cursor)
        XCTAssertEqual(general?.laserLifetime, .twoPointFive)

        let scopeStore = InMemoryPreferenceStore()
        scopeStore.set("active", forKey: "overlayScope")
        general = PreferencesMigration.migratedGeneralPreferences(in: scopeStore)
        XCTAssertNotNil(general)
        XCTAssertTrue(general!.showArmedFrame)
        XCTAssertEqual(general?.scope, .active)

        let placementStore = InMemoryPreferenceStore()
        placementStore.set("frontWindow", forKey: "palettePlacement")
        general = PreferencesMigration.migratedGeneralPreferences(in: placementStore)
        XCTAssertNotNil(general)
        XCTAssertEqual(general?.palettePlacement, .frontWindow)

        let lifetimeStore = InMemoryPreferenceStore()
        lifetimeStore.set(1.0, forKey: "laserLifetime")
        general = PreferencesMigration.migratedGeneralPreferences(in: lifetimeStore)
        XCTAssertNotNil(general)
        XCTAssertEqual(general?.laserLifetime, .one)
    }

    func testMigrationMapsUnknownLegacyStringsAndNumbersToDefaults() {
        let store = InMemoryPreferenceStore()
        store.set("galaxy", forKey: "overlayScope")
        store.set("sky", forKey: "palettePlacement")
        store.set(4.0, forKey: "laserLifetime")

        let general = PreferencesMigration.migratedGeneralPreferences(in: store)
        XCTAssertEqual(general?.scope, .all)
        XCTAssertEqual(general?.palettePlacement, .cursor)
        XCTAssertEqual(general?.laserLifetime, .twoPointFive)
    }

    func testMigrationReturnsNilWithoutLegacyKeys() {
        XCTAssertNil(PreferencesMigration.migratedGeneralPreferences(in: InMemoryPreferenceStore()))
    }

    // MARK: Toolbar gripper (T3 / S4)

    func testGripperSpecPinsTheTwoByThreeDotPattern() {
        // The owner's `⠇⠇`: two columns of three stacked dots.
        XCTAssertEqual(ToolbarGripperSpec.dotColumns, 2)
        XCTAssertEqual(ToolbarGripperSpec.dotRows, 3)
    }

    func testGripperSpecTooltipNamesBothActions() {
        XCTAssertEqual(ToolbarGripperSpec.tooltip, "Drag to move · Right-click to reset position")
    }

    func testGripperSpecResetTargetIsTheFreshInstallAnchor() {
        // Right-clicking the gripper sends the bar back to the anchor the app
        // stores; with nothing stored the palette opens at this spot. The
        // border-aware overload (T9/S12) must reproduce it for today's top
        // dock so the reset target never moves on its own.
        XCTAssertEqual(ToolbarGripperSpec.defaultAnchor, CGPoint(x: 0.5, y: 0.08))
        XCTAssertEqual(ToolbarGripperSpec.defaultAnchor(border: .top, screenFrame: Self.screenFrame), ToolbarGripperSpec.defaultAnchor)
    }

    func testGripperSpecDefaultAnchorPerBorderIsSymmetricAndDistinct() {
        let anchors = ToolbarBorder.allCases.map {
            ToolbarGripperSpec.defaultAnchor(border: $0, screenFrame: Self.screenFrame)
        }
        // Four borders, four distinct anchors: top and bottom mirror on the
        // vertical axis, left and right on the horizontal one (S3).
        XCTAssertEqual(Set(anchors).count, 4)
        for border in ToolbarBorder.allCases {
            let anchor = ToolbarGripperSpec.defaultAnchor(border: border, screenFrame: Self.screenFrame)
            switch border {
            case .top: XCTAssertEqual(anchor, CGPoint(x: 0.5, y: 0.08))
            case .bottom: XCTAssertEqual(anchor, CGPoint(x: 0.5, y: 0.92))
            case .left, .right:
                // The side inset is the absolute distance the row keeps from
                // the top/bottom edge, read back as a fraction of the width.
                let inset = 0.08 * Self.screenFrame.height / Self.screenFrame.width
                XCTAssertEqual(anchor.x, border == .left ? inset : 1 - inset, accuracy: 1e-9)
                XCTAssertEqual(anchor.y, 0.5)
            }
        }
    }

    // MARK: Toolbar docking geometry (T9/S12)

    /// A 14" MacBook-like screen: 1512×982 frame with a 38-pt menu bar at the
    /// top, so the visible frame is 1512×944; and the same screen with a
    /// 90-pt dock on the bottom.
    private static let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private static let plainVisibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private static let dockedVisibleFrame = CGRect(x: 0, y: 90, width: 1512, height: 854)
    /// The wide bar the palette renders as a horizontal row today, and the
    /// tall bar the vertical orientation renders.
    private static let horizontalBarSize = CGSize(width: 600, height: 42)
    private static let verticalBarSize = CGSize(width: 42, height: 600)

    func testResetRectForTodaysTopBorderReproducesTheBarOpensExactlyThere() {
        // Same centre-and-clamp math the panel has always applied for the
        // fresh-install anchor: pin the exact rect for a horizontal bar at
        // the top border so a fresh install keeps opening exactly there.
        XCTAssertEqual(
            ToolbarGripperSpec.resetRect(
                barSize: Self.horizontalBarSize,
                screenFrame: Self.screenFrame,
                visibleFrame: Self.plainVisibleFrame,
                border: .top
            ),
            CGRect(x: 456, y: 58, width: 600, height: 42)
        )
    }

    func testResetRectForEveryOrientationAndBorderStaysInsideTheVisibleFrame() {
        for orientation in ToolbarOrientation.allCases {
            let barSize = orientation == .horizontal ? Self.horizontalBarSize : Self.verticalBarSize
            for border in ToolbarBorder.allCases {
                for visibleFrame in [Self.plainVisibleFrame, Self.dockedVisibleFrame] {
                    let rect = ToolbarGripperSpec.resetRect(
                        barSize: barSize,
                        screenFrame: Self.screenFrame,
                        visibleFrame: visibleFrame,
                        border: border
                    )
                    XCTAssertTrue(
                        visibleFrame.contains(rect),
                        "\(orientation)/\(border): \(rect) escapes the visible frame \(visibleFrame)"
                    )
                }
            }
        }
    }

    func testVerticalBarKeepsTheHorizontalBarsEdgeGap() {
        // S3: the column sits exactly as far from the side edge as the row
        // sits from the top/bottom edge. 8% of the width was a bigger number
        // of points than 8% of the height, which is what pushed the column in.
        let horizontal = ToolbarGripperSpec.resetRect(
            barSize: Self.horizontalBarSize,
            screenFrame: Self.screenFrame,
            visibleFrame: Self.plainVisibleFrame,
            border: .top
        )
        let vertical = ToolbarGripperSpec.resetRect(
            barSize: Self.verticalBarSize,
            screenFrame: Self.screenFrame,
            visibleFrame: Self.plainVisibleFrame,
            border: .left
        )
        XCTAssertEqual(
            vertical.minX - Self.screenFrame.minX,
            horizontal.minY - Self.screenFrame.minY,
            accuracy: 0.5
        )
    }

    func testRightDockedColumnMirrorsTheLeftOne() {
        let left = ToolbarGripperSpec.resetRect(
            barSize: Self.verticalBarSize,
            screenFrame: Self.screenFrame,
            visibleFrame: Self.plainVisibleFrame,
            border: .left
        )
        let right = ToolbarGripperSpec.resetRect(
            barSize: Self.verticalBarSize,
            screenFrame: Self.screenFrame,
            visibleFrame: Self.plainVisibleFrame,
            border: .right
        )
        XCTAssertEqual(left.minX - Self.screenFrame.minX, Self.screenFrame.maxX - right.maxX, accuracy: 0.5)
        XCTAssertEqual(left.minY, right.minY, accuracy: 0.5)
    }

    func testVerticalAndHorizontalResetRectsDifferWhereTheyMust() {
        // The bar shape is what the orientations differ in, so for the same
        // border the two rects swap the long axis while keeping the border
        // edge.
        for border in ToolbarBorder.allCases {
            let horizontal = ToolbarGripperSpec.resetRect(
                barSize: Self.horizontalBarSize,
                screenFrame: Self.screenFrame,
                visibleFrame: Self.plainVisibleFrame,
                border: border
            )
            let vertical = ToolbarGripperSpec.resetRect(
                barSize: Self.verticalBarSize,
                screenFrame: Self.screenFrame,
                visibleFrame: Self.plainVisibleFrame,
                border: border
            )
            XCTAssertNotEqual(horizontal, vertical, "border \(border)")
            XCTAssertEqual(horizontal.width, Self.horizontalBarSize.width)
            XCTAssertEqual(vertical.height, Self.verticalBarSize.height)
        }
    }

    func testUnknownStoredToolbarSettingFallsBackToTheDockedDefault() throws {
        // An unknown stored orientation or border keeps the documented
        // default — the bar the app has always opened with.
        let general = try Self.decode(
            #"{"toolbarOrientation":"diagonal","toolbarBorder":"sky"}"#
        )
        XCTAssertEqual(general.toolbarOrientation, GeneralPreferences.standard.toolbarOrientation)
        XCTAssertEqual(general.toolbarBorder, GeneralPreferences.standard.toolbarBorder)
    }

    // MARK: Valid edges per orientation (T3/S4)

    func testHorizontalDocksWithOnlyTopAndBottom() {
        XCTAssertEqual(ToolbarBorder.validEdges(for: .horizontal), [.top, .bottom])
    }

    func testVerticalDocksWithOnlyLeftAndRight() {
        XCTAssertEqual(ToolbarBorder.validEdges(for: .vertical), [.left, .right])
    }

    func testFallbackEdgeIsTheFirstValidEdgeOfTheOrientation() {
        // The horizontal answer is the dock the app has always opened with;
        // the vertical one mirrors it onto the column's first edge.
        XCTAssertEqual(ToolbarBorder.fallbackEdge(for: .horizontal), .top)
        XCTAssertEqual(ToolbarBorder.fallbackEdge(for: .vertical), .left)
    }

    func testValidationKeepsEveryValidPairAndFallsBackForEveryInvalidOne() {
        // All eight orientation × border combinations: a valid edge is
        // itself; an invalid one is that orientation's fallback edge.
        for border in ToolbarBorder.allCases {
            XCTAssertEqual(
                border.validated(for: .horizontal),
                border == .top || border == .bottom ? border : .top,
                "horizontal/\(border.rawValue)"
            )
            XCTAssertEqual(
                border.validated(for: .vertical),
                border == .left || border == .right ? border : .left,
                "vertical/\(border.rawValue)"
            )
        }
    }

    func testDecodingAnInvalidStoredPairFallsBackToTheOrientationsDefaultEdge() throws {
        // horizontal + left and vertical + bottom are the inconsistent pairs
        // S4 refuses: decoding re-docks them on the orientation's own default
        // edge, so the bar lands somewhere the orientation can actually sit.
        let horizontalLeft = try Self.decode(
            #"{"showArmedFrame":false,"toolbarOrientation":"horizontal","toolbarBorder":"left"}"#
        )
        XCTAssertEqual(horizontalLeft.toolbarOrientation, .horizontal)
        XCTAssertEqual(horizontalLeft.toolbarBorder, .top)

        let verticalBottom = try Self.decode(
            #"{"scope":"active","toolbarOrientation":"vertical","toolbarBorder":"bottom"}"#
        )
        XCTAssertEqual(verticalBottom.toolbarOrientation, .vertical)
        XCTAssertEqual(verticalBottom.toolbarBorder, .left)
    }

    func testDecodingAValidStoredPairRoundTripsItExactly() throws {
        // A stored pair that is already consistent survives the decode
        // untouched — the fallback must never move a bar that sits legally.
        let horizontalBottom = try Self.decode(
            #"{"toolbarOrientation":"horizontal","toolbarBorder":"bottom"}"#
        )
        XCTAssertEqual(horizontalBottom.toolbarOrientation, .horizontal)
        XCTAssertEqual(horizontalBottom.toolbarBorder, .bottom)

        let verticalRight = try Self.decode(
            #"{"toolbarOrientation":"vertical","toolbarBorder":"right"}"#
        )
        XCTAssertEqual(verticalRight.toolbarOrientation, .vertical)
        XCTAssertEqual(verticalRight.toolbarBorder, .right)
    }

    func testToolbarPairRoundTripsThroughEncodeAndDecodeConsistent() throws {
        var general = GeneralPreferences.standard
        general.toolbarOrientation = .vertical
        general.toolbarBorder = .right

        let data = try JSONEncoder().encode(general)
        let decoded = try JSONDecoder().decode(GeneralPreferences.self, from: data)
        XCTAssertEqual(decoded, general)
        XCTAssertEqual(decoded.toolbarBorder, .right, "a valid pair survives the round trip unchanged")
    }

    // MARK: Helpers

    private static func decode(_ json: String) throws -> GeneralPreferences {
        try JSONDecoder().decode(GeneralPreferences.self, from: Data(json.utf8))
    }
}
