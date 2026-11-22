import Foundation
import XCTest
@testable import StareCore

final class GeneralPreferencesTests: XCTestCase {
    // MARK: Defaults (T6 slice 1 / S4)

    func testStandardMatchesTodayDefaults() {
        XCTAssertTrue(GeneralPreferences.standard.showArmedFrame)
        XCTAssertEqual(GeneralPreferences.standard.scope, .all)
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
        XCTAssertEqual(general.scope, .all)
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

    // MARK: Toolbar tool layout (T8/S10)

    /// Shorthand for the stored layout the Settings pane and the toolbar read.
    /// Hidden tools keep their place in `tools`, so hiding one can never make
    /// it fall off and come back as if it were new.
    private static func decodeLayout(_ json: String) throws -> ToolbarToolLayout {
        try JSONDecoder().decode(ToolbarToolLayout.self, from: Data(json.utf8))
    }

    func testStandardToolbarLayoutReproducesTodaysBar() {
        // The shipped layout is exactly the grouped bar the app has always
        // drawn: same groups, same order, nothing hidden.
        XCTAssertEqual(ToolbarToolLayout.standard.visibleGroups, Tool.toolbarGroups)
        XCTAssertEqual(ToolbarToolLayout.standard.visibleTools, Tool.toolbarGroups.flatMap { $0 })
        XCTAssertTrue(ToolbarToolLayout.standard.hidden.isEmpty)
        XCTAssertEqual(GeneralPreferences.standard.toolbarTools, .standard)
    }

    func testHidingRemovesExactlyThatToolWithNoGapsOrDuplicates() {
        let layout = ToolbarToolLayout.standard.setting(.number, isVisible: false)

        // The hidden tool is gone from the bar but keeps its stored place,
        // so re-showing it does not shuffle the order.
        XCTAssertEqual(layout.visibleTools, Tool.toolbarGroups.flatMap { $0 }.filter { $0 != .number })
        XCTAssertTrue(layout.tools.contains(.number), "a hidden tool keeps its place in the stored order")
        XCTAssertEqual(layout.visibleGroups.flatMap { $0 }, layout.visibleTools)
    }

    func testHidingTheLastVisibleToolIsRefused() {
        // The bar can never go empty: hiding the one visible tool leaves the
        // layout exactly as it was.
        var only = ToolbarToolLayout.standard
        for tool in ToolbarToolLayout.defaultOrder where tool != .pen {
            only = only.setting(tool, isVisible: false)
        }
        XCTAssertEqual(only.visibleTools, [.pen])

        XCTAssertEqual(only.setting(.pen, isVisible: false), only)
    }

    func testShowingAHidingToolPutsItBackWithoutShuffling() {
        let hiddenBar = ToolbarToolLayout.standard.setting(.laser, isVisible: false)
        XCTAssertEqual(hiddenBar.setting(.laser, isVisible: true), ToolbarToolLayout.standard)
    }

    func testMovingSwapsNeighbours() {
        // One step up swaps with the tool before it.
        let penMovedUp = [
            Tool.pen, .select, .highlighter, .line, .arrow, .rectangle, .ellipse,
            .text, .number, .blur, .laser, .eraser,
        ]
        XCTAssertEqual(ToolbarToolLayout.standard.moving(.pen, by: -1).tools, penMovedUp)
    }

    func testMovingUpSwapsTheToolIntoThePreviousSlot() {
        XCTAssertEqual(ToolbarToolLayout.standard.moving(.blur, by: -1).visibleTools, [
            .select, .pen, .highlighter, .line, .arrow, .rectangle, .ellipse,
            .text, .blur, .number, .laser, .eraser,
        ])
    }

    func testMovingDownSwapsTheToolIntoTheNextSlot() {
        XCTAssertEqual(ToolbarToolLayout.standard.moving(.select, by: 1).visibleTools, [
            .pen, .select, .highlighter, .line, .arrow, .rectangle, .ellipse,
            .text, .number, .blur, .laser, .eraser,
        ])
    }

    func testMovingClampsAtBothEnds() {
        XCTAssertEqual(ToolbarToolLayout.standard.moving(.select, by: -1), ToolbarToolLayout.standard)
        XCTAssertEqual(ToolbarToolLayout.standard.moving(.eraser, by: 5), ToolbarToolLayout.standard)
    }

    func testUnknownStoredIdentifiersAreDropped() throws {
        let layout = try Self.decodeLayout(
            #"{"tools":["pen","galaxy","select"],"hidden":[]}"#
        )
        // The two known tools keep their stored order; everything the list
        // never mentioned is appended in the documented default order.
        XCTAssertEqual(layout.visibleTools, [
            .pen, .select, .highlighter, .line, .arrow, .rectangle, .ellipse,
            .text, .number, .blur, .laser, .eraser,
        ])
    }

    func testStoredListMissingANewlyAddedToolAppendsItSoItIsNeverInvisible() throws {
        // A future build adds a tool; the stored list predates it. The new
        // tool is appended at the end in the documented default order instead
        // of being silently invisible.
        let layout = try Self.decodeLayout(
            #"{"tools":["select","pen","blur"],"hidden":["laser"]}"#
        )
        XCTAssertEqual(layout.hidden, [.laser])
        let lastAppended = ToolbarToolLayout.defaultOrder.filter { ![.select, .pen, .blur, .laser].contains($0) }
        XCTAssertEqual(Array(layout.visibleTools.dropFirst(3)), lastAppended)
        XCTAssertFalse(layout.visibleTools.isEmpty)
        XCTAssertTrue(layout.visibleTools.contains(.highlighter))
    }

    func testDuplicateStoredEntriesCollapseToTheirFirstOccurrence() throws {
        let layout = try Self.decodeLayout(#"{"tools":["pen","select","pen"],"hidden":[]}"#)
        XCTAssertEqual(layout.tools.filter { $0 == .pen }.count, 1)
        XCTAssertEqual(layout.visibleTools.first, .pen)
        XCTAssertEqual(Set(layout.visibleTools), Set(Tool.allCases))
    }

    func testEmptyStoredListFallsBackToTheDefaultInsteadOfAnEmptyBar() throws {
        XCTAssertEqual(try Self.decodeLayout(#"{"tools":[],"hidden":[]}"#), .standard)
        // Missing fields (an older blob) are the shipped layout too.
        XCTAssertEqual(try Self.decodeLayout("{}"), .standard)
        let general = try Self.decode(
            #"{"toolbarOrientation":"vertical","toolbarTools":{"tools":[],"hidden":[]}}"#
        )
        XCTAssertEqual(general.toolbarTools, .standard)
        XCTAssertEqual(general.toolbarOrientation, .vertical)
    }

    func testStoredBarThatHidesEveryToolLosesTheHiddenSet() throws {
        // A corrupt document hiding everything is refused: the hidden set is
        // dropped, the stored order keeps everything visible.
        let layout = try Self.decodeLayout(
            #"{"tools":["select","pen","highlighter","line","arrow","rectangle","ellipse","text","number","blur","laser","eraser"],"hidden":["select","pen","highlighter","line","arrow","rectangle","ellipse","text","number","blur","laser","eraser"]}"#
        )
        XCTAssertTrue(layout.hidden.isEmpty)
        XCTAssertEqual(layout.visibleTools, ToolbarToolLayout.defaultOrder)
    }

    func testToolbarLayoutRoundTripsThroughGeneralPreferences() throws {
        var general = GeneralPreferences.standard
        general.toolbarTools = ToolbarToolLayout.standard
            .setting(.number, isVisible: false)
            .moving(.eraser, by: -1)

        let data = try JSONEncoder().encode(general)
        let decoded = try JSONDecoder().decode(GeneralPreferences.self, from: data)
        XCTAssertEqual(decoded, general)
        // And a hidden choice survives a round trip: the hidden tool stays
        // hidden across launches.
        XCTAssertFalse(decoded.toolbarTools.visibleTools.contains(.number))
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
        XCTAssertEqual(general?.scope, .all)
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
        XCTAssertEqual(ToolbarGripperSpec.defaultAnchor(border: .top), ToolbarGripperSpec.defaultAnchor)
    }

    func testGripperSpecDefaultAnchorPerBorderIsSymmetricAndDistinct() {
        let anchors = ToolbarBorder.allCases.map { ToolbarGripperSpec.defaultAnchor(border: $0) }
        // Four borders, four distinct anchors: top and bottom mirror on the
        // vertical axis, left and right on the horizontal one.
        XCTAssertEqual(Set(anchors), Set([
            CGPoint(x: 0.5, y: 0.08),
            CGPoint(x: 0.5, y: 0.92),
            CGPoint(x: 0.08, y: 0.5),
            CGPoint(x: 0.92, y: 0.5),
        ]))
        XCTAssertEqual(anchors.count, 4)
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
