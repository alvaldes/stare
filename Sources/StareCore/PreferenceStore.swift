import CoreFoundation
import Foundation

/// Read/write seam over the host persistence layer, so app preferences can be
/// tested against an in-memory store instead of `UserDefaults`. The raw
/// `object`/`set` pair is the only contract; the typed conveniences below add
/// the default-on-mismatch behaviour every caller relies on.
public protocol PreferenceStore: AnyObject {
    /// Raw stored value for `key`, or nil when nothing is stored.
    func object(forKey key: String) -> Any?
    /// Stores `value` under `key`; nil removes the key.
    func set(_ value: Any?, forKey key: String)
}

public extension PreferenceStore {
    /// Stored boolean for `key`, or `defaultValue` when the key is absent or
    /// holds a value that is not a boolean. A number stored as a double is not
    /// a boolean, so it yields `defaultValue` instead of its truthiness.
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        guard let number = object(forKey: key) as? NSNumber, Self.isBoolean(number) else {
            return defaultValue
        }
        return number.boolValue
    }

    /// Stored double for `key`, or `defaultValue` when the key is absent or
    /// holds a value that is not a number. Booleans are numbers to the host
    /// persistence layer, so they are rejected here: `double(forKey:)` on a
    /// boolean key must yield `defaultValue`, never 0 or 1.
    func double(forKey key: String, default defaultValue: Double) -> Double {
        guard let number = object(forKey: key) as? NSNumber, !Self.isBoolean(number) else {
            return defaultValue
        }
        return number.doubleValue
    }

    /// Distinguishes a stored boolean from the numeric values that share the
    /// same `NSNumber` representation in `UserDefaults`.
    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// Stored string for `key`, or nil when the key is absent or holds a value
    /// that is not a string.
    func string(forKey key: String) -> String? {
        object(forKey: key) as? String
    }

    /// Stored data blob for `key`, or nil when the key is absent or holds a
    /// value that is not `Data`.
    func data(forKey key: String) -> Data? {
        object(forKey: key) as? Data
    }
}

/// `PreferenceStore` backed by `UserDefaults`, so the app target can hand in
/// `.standard` (or a suite) without writing an adapter.
public final class UserDefaultsPreferenceStore: PreferenceStore {
    private let defaults: UserDefaults

    /// Wraps `defaults`; defaults to the standard domain.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func object(forKey key: String) -> Any? {
        defaults.object(forKey: key)
    }

    public func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}
