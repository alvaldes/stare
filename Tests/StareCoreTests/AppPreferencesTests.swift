import Foundation
import XCTest
@testable import StareCore

final class AppPreferencesTests: XCTestCase {
    // MARK: Round trip

    func testRoundTripsThroughInMemoryStore() {
        let store = InMemoryPreferenceStore()
        var saved = AppPreferences.standard
        saved.pointer.preset = .dot
        saved.pointer.size = 44
        saved.pointer.colorSource = .fixed(.purple)
        saved.pointer.bandWidth = 0.4
        saved.pointer.glowIntensity = 0.5
        saved.pointer.fadeWhenIdle = false

        saved.save(to: store)
        let loaded = AppPreferences(store: store)
        XCTAssertEqual(loaded, saved)
    }

    func testSaveWritesVersionedBlob() {
        let store = InMemoryPreferenceStore()
        AppPreferences.standard.save(to: store)
        XCTAssertNotNil(store.data(forKey: AppPreferences.storageKey))
    }

    // MARK: Corrupt blob

    func testCorruptBlobFallsBackToStandard() {
        let store = InMemoryPreferenceStore()
        store.set(Data("not json".utf8), forKey: AppPreferences.storageKey)
        XCTAssertEqual(AppPreferences(store: store), AppPreferences.standard)
    }

    func testCorruptBlobFallsBackToLegacyMigrationWhenLegacyKeysExist() {
        let store = InMemoryPreferenceStore()
        store.set(Data("not json".utf8), forKey: AppPreferences.storageKey)
        store.set(60.0, forKey: "pointerSize.v3")
        store.set("circle", forKey: "pointerShape")

        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.pointer.preset, .ring)
        XCTAssertEqual(prefs.pointer.size, 60)
    }

    // MARK: Migration

    func testMigrationFromLegacyKeysProducesMigratedStyle() {
        let store = InMemoryPreferenceStore()
        store.set(60.0, forKey: "pointerSize.v3")
        store.set("circle", forKey: "pointerShape")
        store.set(false, forKey: "pointerGlow")
        store.set(false, forKey: "pointerFadeWhenIdle")

        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.pointer.preset, .ring)
        XCTAssertEqual(prefs.pointer.size, 60)
        XCTAssertEqual(prefs.pointer.glowIntensity, 0)
        XCTAssertFalse(prefs.pointer.fadeWhenIdle)
        XCTAssertEqual(prefs.pointer.colorSource, .ink)
        XCTAssertEqual(prefs.pointer.bandWidth, 0.26)
    }

    func testMigrationMapsSquircleAndNonSquircleLikeToday() {
        let squircleStore = InMemoryPreferenceStore()
        squircleStore.set("squircle", forKey: "pointerShape")
        XCTAssertEqual(AppPreferences(store: squircleStore).pointer.preset, .squircle)

        let unknownStore = InMemoryPreferenceStore()
        unknownStore.set("triangle", forKey: "pointerShape")
        // Today's renderer draws a circle for anything that is not "squircle".
        XCTAssertEqual(AppPreferences(store: unknownStore).pointer.preset, .ring)
    }

    func testMigrationUsesTodayDefaultsWhenSomeKeysAreMissing() {
        let store = InMemoryPreferenceStore()
        store.set("squircle", forKey: "pointerShape")
        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.pointer.preset, .squircle)
        XCTAssertEqual(prefs.pointer.size, PointerStyle.standard.size)
        XCTAssertEqual(prefs.pointer.glowIntensity, 1)
        XCTAssertTrue(prefs.pointer.fadeWhenIdle)
    }

    func testFollowUpSaveWritesBlobAndLegacyKeysStayUntouched() {
        let store = InMemoryPreferenceStore()
        store.set(60.0, forKey: "pointerSize.v3")
        store.set("circle", forKey: "pointerShape")
        store.set(false, forKey: "pointerGlow")
        store.set(false, forKey: "pointerFadeWhenIdle")

        let prefs = AppPreferences(store: store)
        prefs.save(to: store)

        XCTAssertNotNil(store.data(forKey: AppPreferences.storageKey))
        XCTAssertEqual(store.double(forKey: "pointerSize.v3", default: -1), 60)
        XCTAssertEqual(store.string(forKey: "pointerShape"), "circle")
        XCTAssertFalse(store.bool(forKey: "pointerGlow", default: true))
        XCTAssertFalse(store.bool(forKey: "pointerFadeWhenIdle", default: true))

        // The saved blob must now win over the (stale) legacy keys.
        XCTAssertEqual(AppPreferences(store: store), prefs)
    }

    // MARK: Fresh install

    func testNoKeysAndNoBlobYieldsStandard() {
        let store = InMemoryPreferenceStore()
        XCTAssertEqual(AppPreferences(store: store), AppPreferences.standard)
    }
}
