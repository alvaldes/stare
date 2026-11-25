import XCTest

import StareCore

/// B1: the capture history's thumbnail size as a persisted preference — the
/// value survives the versioned blob, an older document loads the shipped
/// size, and a hand-edited one is clamped to the range the pane offers instead
/// of producing a cell nobody can read.
final class HistoryPreferenceTests: XCTestCase {

    /// An in-memory `PreferenceStore`, so no test touches the user's real
    /// preferences.
    private final class InMemoryPreferenceStore: PreferenceStore {
        private var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    func testTheThumbnailSizeSurvivesTheVersionedBlob() {
        let store = InMemoryPreferenceStore()
        var preferences = AppPreferences.standard
        preferences.history = HistoryPreference(thumbnailSize: 240)
        preferences.save(to: store)

        XCTAssertEqual(AppPreferences(store: store).history.thumbnailSize, 240,
            "the size is part of the one versioned document, not a lone key")
    }

    func testADocumentFromBeforeThePreferenceExistedLoadsTheShippedSize() throws {
        let old = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(old.history, .standard)
        XCTAssertEqual(old.history.thumbnailSize, HistoryPreference.defaultThumbnailSize,
            "every blob written before B1 loads as the grid the panel shipped with")
    }

    func testAForeignThumbnailSizeIsClampedToTheOfferedRange() {
        XCTAssertEqual(HistoryPreference(thumbnailSize: 5).thumbnailSize,
            HistoryPreference.thumbnailSizeRange.lowerBound, "a cell too narrow is not a preference")
        XCTAssertEqual(HistoryPreference(thumbnailSize: 5_000).thumbnailSize,
            HistoryPreference.thumbnailSizeRange.upperBound, "nor is one wider than the panel")
        XCTAssertEqual(HistoryPreference(thumbnailSize: .nan).thumbnailSize,
            HistoryPreference.defaultThumbnailSize, "a non-number falls back to the shipped size")

        var preference = HistoryPreference(thumbnailSize: 200)
        preference.thumbnailSize = 10
        XCTAssertEqual(preference.thumbnailSize, HistoryPreference.thumbnailSizeRange.lowerBound,
            "the setter clamps too, not only the initialiser")
    }
}
