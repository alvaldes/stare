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

    /// A legacy user keeps the look they were running: the factory defaults of
    /// their own era (72 pt), not the ones v0.4/S9 introduced for fresh
    /// installs. Migration overrides only the keys they actually had.
    func testMigrationUsesTheLegacyDefaultsWhenSomeKeysAreMissing() {
        let store = InMemoryPreferenceStore()
        store.set("squircle", forKey: "pointerShape")
        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.pointer.preset, .squircle)
        XCTAssertEqual(prefs.pointer.size, 72)
        XCTAssertEqual(prefs.pointer.bandWidth, 0.26)
        XCTAssertEqual(prefs.pointer.colorSource, .ink)
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

    // MARK: Active tool and ink (T8/S6)

    func testStandardCarriesPenAndRedInk() {
        XCTAssertEqual(AppPreferences.standard.tool, .pen)
        XCTAssertEqual(AppPreferences.standard.ink, .red)
        XCTAssertEqual(AppPreferences(store: InMemoryPreferenceStore()).tool, .pen)
        XCTAssertEqual(AppPreferences(store: InMemoryPreferenceStore()).ink, .red)
    }

    func testRoundTripsToolAndInkThroughStore() {
        let store = InMemoryPreferenceStore()
        var saved = AppPreferences.standard
        saved.tool = .laser
        saved.ink = .blue

        saved.save(to: store)
        let loaded = AppPreferences(store: store)
        XCTAssertEqual(loaded.tool, .laser)
        XCTAssertEqual(loaded.ink, .blue)
        XCTAssertEqual(loaded, saved)
    }

    func testBlobPredatingToolAndInkLoadsTheirDefaults() {
        let store = InMemoryPreferenceStore()
        store.set(Data(#"{"pointer":{"preset":"dot","size":44}}"#.utf8), forKey: AppPreferences.storageKey)

        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.tool, .pen)
        XCTAssertEqual(prefs.ink, .red)
        XCTAssertEqual(prefs.pointer.preset, .dot)
    }

    func testCorruptOrUnknownToolAndInkFallBackToDefaultsAndKeepTheRest() {
        let store = InMemoryPreferenceStore()
        // An unknown tool raw value and an undecodable ink must not fail the
        // whole document; every other field still loads.
        store.set(
            Data(#"{"tool":"wrench","ink":["garbage"],"capture":{"fileNamePrefix":"Shots"}}"#.utf8),
            forKey: AppPreferences.storageKey
        )

        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.tool, .pen)
        XCTAssertEqual(prefs.ink, .red)
        XCTAssertEqual(prefs.capture.fileNamePrefix, "Shots")
    }

    // MARK: Capture, whiteboard and update fields (T3/S6)

    func testStandardCarriesStandardCaptureWhiteboardAndUpdateFields() {
        XCTAssertEqual(AppPreferences.standard.capture, CapturePreference.standard)
        XCTAssertEqual(AppPreferences.standard.whiteboard, WhiteboardDefaults.standard)
        XCTAssertEqual(AppPreferences.standard.updates, UpdateSchedulePreference.standard)
    }

    func testRoundTripsCaptureWhiteboardAndUpdatesThroughStore() {
        let store = InMemoryPreferenceStore()
        var saved = AppPreferences.standard
        saved.capture.format = .jpeg
        saved.capture.destination = .folder(path: "/Users/al/Pictures/Stare")
        saved.capture.fileNamePrefix = "Shots"
        saved.whiteboard.background = .black
        saved.whiteboard.pagesOnOpen = 5
        saved.updates.schedule = .daily
        saved.updates.lastCheck = date(2026, 11, 21, 10)

        saved.save(to: store)
        XCTAssertEqual(AppPreferences(store: store), saved)
    }

    func testBlobPredatingTheNewFieldsLoadsStandardDefaultsForThem() {
        let store = InMemoryPreferenceStore()
        store.set(Data(#"{"pointer":{"preset":"dot","size":44}}"#.utf8), forKey: AppPreferences.storageKey)

        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.pointer.preset, .dot)
        XCTAssertEqual(prefs.pointer.size, 44)
        XCTAssertEqual(prefs.capture, CapturePreference.standard)
        XCTAssertEqual(prefs.whiteboard, WhiteboardDefaults.standard)
        XCTAssertEqual(prefs.updates, UpdateSchedulePreference.standard)
    }

    // MARK: Legacy whiteboard blob compatibility (T13/S8)

    /// A whole preferences blob written before the System choice existed must
    /// load with the user's whiteboard background preserved — a stored black
    /// board never resets to white.
    func testLegacyWhiteboardBackgroundSurvivesThroughAppPreferences() {
        let store = InMemoryPreferenceStore()
        store.set(
            Data(#"{"whiteboard":{"background":"black","pagesOnOpen":4}}"#.utf8),
            forKey: AppPreferences.storageKey
        )

        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.whiteboard.background, WhiteboardBackgroundChoice.black)
        XCTAssertEqual(prefs.whiteboard.pagesOnOpen, 4)
        XCTAssertEqual(prefs.whiteboard.resolvedBackground(isDarkAppearance: false), .black)
        XCTAssertEqual(prefs.whiteboard.resolvedBackground(isDarkAppearance: true), .black)
    }

    // MARK: Whiteboard migration from the per-key build (whiteboard-2)

    /// A user who ran the build that stored the board choices per key keeps
    /// every choice: the page colour, the scope and the border flag land in
    /// the blob, and the legacy keys are only read, never rewritten.
    func testMigrationFromLegacyBoardKeysCarriesBackgroundScopeAndBorder() {
        let store = InMemoryPreferenceStore()
        store.set("system", forKey: PreferencesMigration.legacyBoardBackgroundKey)
        store.set("active", forKey: PreferencesMigration.legacyBoardScopeKey)
        store.set(false, forKey: PreferencesMigration.legacyBoardBorderKey)

        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.whiteboard.background, WhiteboardBackgroundChoice.system)
        XCTAssertEqual(prefs.whiteboard.scope, OverlayScope.active)
        XCTAssertFalse(prefs.whiteboard.showsBorder)
        XCTAssertFalse(prefs.hasCompletedOnboarding)
    }

    func testUnknownLegacyBoardValuesFallBackToTheirDefaults() {
        let store = InMemoryPreferenceStore()
        store.set("sepia", forKey: PreferencesMigration.legacyBoardBackgroundKey)
        store.set("someOther", forKey: PreferencesMigration.legacyBoardScopeKey)
        store.set(true, forKey: PreferencesMigration.legacyBoardBorderKey)

        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.whiteboard.background, WhiteboardBackgroundChoice.system)
        XCTAssertEqual(prefs.whiteboard.scope, OverlayScope.all)
        XCTAssertTrue(prefs.whiteboard.showsBorder)
    }

    func testBoardKeysWithoutMarkerDoNotMigrate() {
        let store = InMemoryPreferenceStore()
        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.whiteboard, WhiteboardDefaults.standard)
    }

    /// The blob wins: once the one document exists the per-key board choices
    /// are no longer read, so a later Settings change survives a restart and
    /// is never clobbered by stale keys.
    func testBlobOverridesLegacyBoardKeys() {
        let store = InMemoryPreferenceStore()
        store.set("black", forKey: PreferencesMigration.legacyBoardBackgroundKey)
        var saved = AppPreferences()
        saved.whiteboard.background = .white
        saved.save(to: store)

        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.whiteboard.background, WhiteboardBackgroundChoice.white)
    }

    func testCorruptSubFieldFallsBackToStandardAndKeepsTheRestOfTheBlob() {
        let store = InMemoryPreferenceStore()
        // "capture" is undecodable garbage; the pointer and the other new
        // fields must still load from the same document.
        store.set(
            Data(#"{"pointer":{"preset":"dot","size":44},"capture":"garbage","whiteboard":{"pagesOnOpen":3},"updates":{"schedule":"daily"}}"#.utf8),
            forKey: AppPreferences.storageKey
        )

        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.pointer.preset, .dot)
        XCTAssertEqual(prefs.pointer.size, 44)
        XCTAssertEqual(prefs.capture, CapturePreference.standard)
        XCTAssertEqual(prefs.whiteboard.pagesOnOpen, 3)
        XCTAssertEqual(prefs.updates.schedule, .daily)
    }

    // MARK: General preferences (T6 slice 1/S4)

    func testStandardCarriesGeneralPreferences() {
        XCTAssertEqual(AppPreferences.standard.general, GeneralPreferences.standard)
    }

    func testRoundTripsGeneralPreferencesThroughStore() {
        let store = InMemoryPreferenceStore()
        var saved = AppPreferences.standard
        saved.general.showArmedFrame = false
        saved.general.scope = .active
        saved.general.palettePlacement = .fixed
        saved.general.laserLifetime = .five

        saved.save(to: store)
        XCTAssertEqual(AppPreferences(store: store), saved)
    }

    func testBlobPredatingGeneralLoadsStandardGeneralAndKeepsTheRest() {
        let store = InMemoryPreferenceStore()
        store.set(Data(#"{"pointer":{"preset":"dot","size":44}}"#.utf8), forKey: AppPreferences.storageKey)

        let prefs = AppPreferences(store: store)
        XCTAssertEqual(prefs.general, GeneralPreferences.standard)
        XCTAssertEqual(prefs.pointer.preset, .dot)
        XCTAssertEqual(prefs.pointer.size, 44)
    }

    func testMigrationFromLegacyGeneralKeysProducesMigratedGeneralPreferences() {
        let store = InMemoryPreferenceStore()
        store.set(false, forKey: "showArmedFrame")
        store.set("active", forKey: "overlayScope")
        store.set("fixed", forKey: "palettePlacement")
        store.set(5.0, forKey: "laserLifetime")

        let prefs = AppPreferences(store: store)
        XCTAssertFalse(prefs.general.showArmedFrame)
        XCTAssertEqual(prefs.general.scope, .active)
        XCTAssertEqual(prefs.general.palettePlacement, .fixed)
        XCTAssertEqual(prefs.general.laserLifetime, .five)
        XCTAssertEqual(prefs.pointer, PointerStyle.standard)
    }

    func testLegacyGeneralKeysStayUntouchedAfterFollowUpSave() {
        let store = InMemoryPreferenceStore()
        store.set(false, forKey: "showArmedFrame")
        store.set("active", forKey: "overlayScope")
        store.set("fixed", forKey: "palettePlacement")
        store.set(5.0, forKey: "laserLifetime")

        let prefs = AppPreferences(store: store)
        prefs.save(to: store)

        XCTAssertNotNil(store.data(forKey: AppPreferences.storageKey))
        XCTAssertFalse(store.bool(forKey: "showArmedFrame", default: true))
        XCTAssertEqual(store.string(forKey: "overlayScope"), "active")
        XCTAssertEqual(store.string(forKey: "palettePlacement"), "fixed")
        XCTAssertEqual(store.double(forKey: "laserLifetime", default: -1), 5)

        // The saved blob must now win over the (stale) legacy keys.
        XCTAssertEqual(AppPreferences(store: store), prefs)
    }

    // MARK: Onboarding flag (T5/S3)

    func testHasCompletedOnboardingDefaultsToFalse() {
        XCTAssertFalse(AppPreferences.standard.hasCompletedOnboarding)
        XCTAssertFalse(AppPreferences(store: InMemoryPreferenceStore()).hasCompletedOnboarding)
    }

    func testRoundTripsHasCompletedOnboardingThroughStore() {
        let store = InMemoryPreferenceStore()
        var saved = AppPreferences.standard
        saved.hasCompletedOnboarding = true

        saved.save(to: store)
        XCTAssertTrue(AppPreferences(store: store).hasCompletedOnboarding)
    }

    func testBlobPredatingTheOnboardingFlagLoadsFalseAndKeepsTheRest() {
        let store = InMemoryPreferenceStore()
        // A blob written before the onboarding guide existed carries no flag;
        // loading must yield false and keep everything else from the document.
        store.set(Data(#"{"pointer":{"preset":"dot","size":44},"capture":{"fileNamePrefix":"Shots"}}"#.utf8), forKey: AppPreferences.storageKey)

        let prefs = AppPreferences(store: store)
        XCTAssertFalse(prefs.hasCompletedOnboarding)
        XCTAssertEqual(prefs.pointer.preset, .dot)
        XCTAssertEqual(prefs.pointer.size, 44)
        XCTAssertEqual(prefs.capture.fileNamePrefix, "Shots")
    }
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
