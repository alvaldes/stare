import Foundation
import XCTest
@testable import StareCore


fileprivate extension Result {
    /// True when the result is a success.
    var isOk: Bool { if case .success = self { return true }; return false }
    /// The failure payload, if the result failed.
    var failureValue: Failure? { if case .failure(let error) = self { return error }; return nil }
}

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

    // MARK: Shortcut and hotkey fields (T2/S6–S7)

    func testStandardCarriesStandardShortcutsAndHotkeys() {
        XCTAssertEqual(AppPreferences.standard.toolShortcuts, ToolShortcutMap.standard)
        XCTAssertEqual(AppPreferences.standard.hotkeys, HotkeyBindings.standard)
    }

    func testRoundTripsToolShortcutsAndHotkeys() {
        let store = InMemoryPreferenceStore()
        var saved = AppPreferences.standard
        var shortcuts = saved.toolShortcuts
        XCTAssertTrue(shortcuts.assigning("Z", to: .laser).isOk)
        saved.toolShortcuts = shortcuts
        var hotkeys = saved.hotkeys
        XCTAssertTrue(hotkeys.assigning(HotkeyBinding(key: .d, modifiers: [.control, .shift]), to: .pin).isOk)
        saved.hotkeys = hotkeys

        saved.save(to: store)
        XCTAssertEqual(AppPreferences(store: store), saved)
    }

    func testBlobPredatingTheShortcutFieldsLoadsStandardShortcuts() {
        let store = InMemoryPreferenceStore()
        // A blob written before `toolShortcuts`/`hotkeys` existed carries only
        // the pointer style; loading must still yield complete defaults.
        store.set(Data("{\"pointer\":{\"preset\":\"dot\",\"size\":44}}".utf8), forKey: AppPreferences.storageKey)

        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.pointer.preset, .dot)
        XCTAssertEqual(prefs.pointer.size, 44)
        XCTAssertEqual(prefs.toolShortcuts, ToolShortcutMap.standard)
        XCTAssertEqual(prefs.hotkeys, HotkeyBindings.standard)
    }
}
