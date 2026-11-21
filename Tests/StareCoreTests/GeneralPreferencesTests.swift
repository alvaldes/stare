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

    // MARK: Helpers

    private static func decode(_ json: String) throws -> GeneralPreferences {
        try JSONDecoder().decode(GeneralPreferences.self, from: Data(json.utf8))
    }
}
