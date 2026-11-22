import CoreFoundation
import Darwin
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

/// The machine's boot instant (T10/S11), read from `sysctl kern.boottime`.
/// A drawing session is stored tagged with this instant, so a session written
/// before a restart is discarded at the next launch instead of being restored
/// into a different boot: the restart is where a stored session's lifetime
/// ends.
public enum BootClock {
    /// The instant this macOS session started, or nil when the kernel call
    /// fails. nil means "tagging is impossible", so nothing is written — an
    /// untagged session could otherwise survive a restart and be restored
    /// into the wrong boot.
    public static func current() -> Date? {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boottime, &size, nil, 0) == 0 else { return nil }
        return Date(
            timeIntervalSince1970: Double(boottime.tv_sec) + Double(boottime.tv_usec) / 1_000_000
        )
    }
}

/// The versioned session archive (T10/S11): what was drawn per display (the
/// committed, non-transient marks) and the boards' pages per display, tagged
/// with the machine's boot instant so a restart discards it. Decoding is
/// all-or-nothing at the archive level: a corrupt payload loads as nil, which
/// is exactly a fresh launch — the app never fails because of the archive and
/// never silently paints someone else's partial document.
public struct SessionArchive: Codable, Equatable, Sendable {
    /// Versioned storage key holding the JSON archive.
    public static let storageKey = "session.archive.v1"

    /// The boot the archive was written in. `BootSessionStore.save` stamps
    /// this; readers discard an archive whose stamp is not the running boot.
    public var bootTime: Date
    /// Drawing marks per display, keyed by the display's decimal id.
    public var displays: [String: [PersistedStroke]]
    /// Board pages per display, keyed by the display's decimal id.
    public var boards: [String: PersistedBoard]

    public init(bootTime: Date = Date(), displays: [String: [PersistedStroke]], boards: [String: PersistedBoard]) {
        self.bootTime = bootTime
        self.displays = displays
        self.boards = boards
    }
}

/// The boot-scoped seam over `PreferenceStore` for the session archive
/// (T10/S11). Cheap and safe by contract: every operation either does its
/// small job or does nothing — a failed encode or an unknown boot instant
/// leaves the store untouched and the calling session working.
public final class BootSessionStore {
    /// The archive is only restored when its stamp names the running boot;
    /// clock adjustments inside one boot never reach a minute, and a restart
    /// is hours away at the very least.
    private static let bootTolerance: TimeInterval = 60

    private let store: PreferenceStore
    private let bootTime: () -> Date?

    /// Reads and writes the archive through `store`, tagging and gating by
    /// `bootTime`. The defaults are the production path: the app's standard
    /// domain and the real boot clock.
    public init(store: PreferenceStore = UserDefaultsPreferenceStore(), bootTime: @escaping () -> Date? = BootClock.current) {
        self.store = store
        self.bootTime = bootTime
    }

    /// The archive stored for the running boot, or nil when nothing is valid:
    /// no key, an undecodable payload, an unknown boot instant, or a stamp
    /// from an earlier boot. nil always behaves like a fresh launch.
    public func load() -> SessionArchive? {
        guard let current = bootTime(),
              let data = store.data(forKey: SessionArchive.storageKey),
              let archive = try? JSONDecoder().decode(SessionArchive.self, from: data),
              abs(archive.bootTime.timeIntervalSince(current)) < Self.bootTolerance
        else { return nil }
        return archive
    }

    /// Stores `archive` stamped with the current boot instant. Skipped, never
    /// thrown, when the boot instant is unknown or the archive cannot be
    /// encoded: a failed save leaves the in-memory session exactly as it was.
    public func save(_ archive: SessionArchive) {
        guard let bootTime = bootTime() else { return }
        var stamped = archive
        stamped.bootTime = bootTime
        guard let data = try? JSONEncoder().encode(stamped) else { return }
        store.set(data, forKey: SessionArchive.storageKey)
    }

    /// Removes the stored archive entirely, so the next launch starts empty.
    public func drop() {
        store.set(nil, forKey: SessionArchive.storageKey)
    }
}
