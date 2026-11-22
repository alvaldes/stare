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

    func testUnknownToolbarOrientationFallsBackToDefaultAndKeepsTheRest() throws {
        let general = try Self.decode(
            #"{"showArmedFrame":false,"scope":"active","palettePlacement":"fixed","laserLifetime":3,"toolbarOrientation":"diagonal","toolbarBorder":"left"}"#
        )
        XCTAssertEqual(general.toolbarOrientation, .horizontal)
        XCTAssertEqual(general.toolbarBorder, .left)
        XCTAssertEqual(general.scope, .active)
        XCTAssertEqual(general.laserLifetime, .three)
    }

    func testUnknownToolbarBorderFallsBackToDefaultAndKeepsTheRest() throws {
        let general = try Self.decode(
            #"{"scope":"active","palettePlacement":"fixed","laserLifetime":3,"toolbarOrientation":"vertical","toolbarBorder":"sky"}"#
        )
        XCTAssertEqual(general.toolbarBorder, .top)
        XCTAssertEqual(general.toolbarOrientation, .vertical)
        XCTAssertEqual(general.scope, .active)
        XCTAssertEqual(general.laserLifetime, .three)
    }

    func testMissingFieldsFallBackToDefaults() throws {
        XCTAssertEqual(try Self.decode("{}"), GeneralPreferences.standard)
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

    // MARK: Helpers

    private static func decode(_ json: String) throws -> GeneralPreferences {
        try JSONDecoder().decode(GeneralPreferences.self, from: Data(json.utf8))
    }
}
