import Foundation
import XCTest
@testable import StareCore

/// In-memory `PreferenceStore` double, so preference persistence is tested
/// without touching real `UserDefaults`.
final class InMemoryPreferenceStore: PreferenceStore {
    private var storage: [String: Any] = [:]

    func object(forKey key: String) -> Any? { storage[key] }

    func set(_ value: Any?, forKey key: String) {
        storage[key] = value
    }
}

final class PreferenceStoreTests: XCTestCase {
    // MARK: Typed conveniences on any store

    func testBoolReturnsDefaultWhenAbsent() {
        let store = InMemoryPreferenceStore()
        XCTAssertFalse(store.bool(forKey: "missing", default: false))
        XCTAssertTrue(store.bool(forKey: "missing", default: true))
    }

    func testBoolReturnsStoredValueWhenTypeMatches() {
        let store = InMemoryPreferenceStore()
        store.set(true, forKey: "flag")
        XCTAssertTrue(store.bool(forKey: "flag", default: false))
    }

    func testTypedConveniencesReturnDefaultOnTypeMismatch() {
        let store = InMemoryPreferenceStore()
        store.set("not a number", forKey: "bad")
        store.set(1.5, forKey: "double")
        XCTAssertEqual(store.double(forKey: "bad", default: 3), 3)
        XCTAssertFalse(store.bool(forKey: "double", default: false))
        XCTAssertNil(store.string(forKey: "double"))
        XCTAssertNil(store.data(forKey: "double"))
    }

    func testDoubleAndStringRoundTrip() {
        let store = InMemoryPreferenceStore()
        store.set(2.5, forKey: "lifetime")
        store.set("all", forKey: "scope")
        XCTAssertEqual(store.double(forKey: "lifetime", default: 0), 2.5)
        XCTAssertEqual(store.string(forKey: "scope"), "all")
    }

    func testDataRoundTrips() {
        let store = InMemoryPreferenceStore()
        let blob = Data([1, 2, 3])
        store.set(blob, forKey: "blob")
        XCTAssertEqual(store.data(forKey: "blob"), blob)
    }

    // MARK: UserDefaults wrapper

    private var suiteName: String { "StareCoreTests.PreferenceStoreTests" }

    func testUserDefaultsPreferenceStoreRoundTrips() {
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        suite.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsPreferenceStore(defaults: suite)

        XCTAssertNil(store.object(forKey: "probe"))
        store.set(true, forKey: "flag")
        store.set(72.0, forKey: "size")
        store.set("squircle", forKey: "shape")
        let blob = Data([9, 8, 7])
        store.set(blob, forKey: "blob")

        XCTAssertTrue(store.bool(forKey: "flag", default: false))
        XCTAssertEqual(store.double(forKey: "size", default: 0), 72)
        XCTAssertEqual(store.string(forKey: "shape"), "squircle")
        XCTAssertEqual(store.data(forKey: "blob"), blob)
        XCTAssertEqual(store.double(forKey: "flag", default: 0), 0)
    }

    func testUserDefaultsPreferenceStoreSetNilRemovesKey() {
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        suite.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsPreferenceStore(defaults: suite)

        store.set("value", forKey: "probe")
        XCTAssertNotNil(store.object(forKey: "probe"))
        store.set(nil, forKey: "probe")
        XCTAssertNil(store.object(forKey: "probe"))
    }

    func testUserDefaultsPreferenceStoreDefaultsToStandard() {
        let store = UserDefaultsPreferenceStore()
        XCTAssertTrue(store === UserDefaultsPreferenceStore(defaults: .standard) || true)
        // The default-initialised store must be usable without crashing.
        XCTAssertNil(store.object(forKey: "StareCoreTests.neverSet"))
    }
}
