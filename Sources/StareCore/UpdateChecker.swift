import Foundation

/// A parsed `MAJOR.MINOR.PATCH` version. Comparable by its numeric core only:
/// a trailing build or prerelease suffix (`1.2.0-beta.1`, `2.0.0+build.7`) is
/// tolerated in parsing but ignored in comparison, and nothing else parses —
/// so update availability can never hinge on suffix semantics.
public struct SemanticVersion: Comparable, Codable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// Creates a version from its numeric components.
    public init?(major: Int, minor: Int, patch: Int) {
        guard major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `"MAJOR.MINOR.PATCH"`, tolerating an optional leading `v`/`V`
    /// and a trailing suffix after the first `-` or `+`. Anything else fails.
    public init?(string: String) {
        var core = string
        if core.hasPrefix("v") || core.hasPrefix("V") {
            core.removeFirst()
        }
        // Drop the first suffix marker; the core must be exactly three numbers.
        if let marker = core.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            core = String(core[..<marker])
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
            let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
            major >= 0, minor >= 0, patch >= 0
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// The numeric core as `"MAJOR.MINOR.PATCH"`, suffix always dropped.
    public var displayString: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// Encodes as the plain `"MAJOR.MINOR.PATCH"` string.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(displayString)
    }

    /// Decodes a `"MAJOR.MINOR.PATCH"` string; garbage throws so a malformed
    /// version is never silently zeroed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let version = SemanticVersion(string: raw) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Malformed semantic version \(raw)")
            )
        }
        self = version
    }
}

/// How often the app checks for updates. Raw values are what the versioned
/// preferences blob persists.
public enum UpdateCheckSchedule: String, Codable, CaseIterable, Sendable {
    /// Never check; the user opens the release page by hand.
    case never
    /// Check at most once per calendar day.
    case daily
    /// Check at most once per calendar week.
    case weekly
    /// Check at most once per calendar month.
    case monthly

    /// English label shown in Settings.
    public var title: String {
        switch self {
        case .never: "Never"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    /// Whether a check is due now: `.never` is never due; without a previous
    /// check every real schedule is due immediately; otherwise a check is due
    /// once the previous one falls in an earlier calendar day (daily), week
    /// (weekly) or month (monthly), all computed in the passed calendar.
    public func isDue(lastCheck: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .never:
            return false
        case .daily:
            guard let lastCheck else { return true }
            return !calendar.isDate(now, inSameDayAs: lastCheck)
        case .weekly:
            guard let lastCheck else { return true }
            return calendar.dateInterval(of: .weekOfYear, for: now) != calendar.dateInterval(of: .weekOfYear, for: lastCheck)
        case .monthly:
            guard let lastCheck else { return true }
            return calendar.dateInterval(of: .month, for: now) != calendar.dateInterval(of: .month, for: lastCheck)
        }
    }
}

/// One release the feed can offer: its version, the page to open in the
/// browser, and short English highlights the Settings pane can list.
public struct UpdateRelease: Equatable, Sendable {
    public var version: SemanticVersion
    public var pageURL: URL
    public var highlights: [String]

    public init(version: SemanticVersion, pageURL: URL, highlights: [String]) {
        self.version = version
        self.pageURL = pageURL
        self.highlights = highlights
    }
}

/// The network seam `UpdateChecker` consumes. The app implements this over the
/// public GitHub releases API later; tests hand in a fake. The checker never
/// touches `URLSession` itself.
public protocol UpdateFeed: Sendable {
    /// The newest release the feed knows about, or nil when it knows none.
    func latestRelease() async throws -> UpdateRelease?
}

/// What the UI shows about updates: the release to offer, when a check last
/// succeeded, and whether the last attempt failed.
public struct UpdateStatus: Equatable, Sendable {
    /// A release newer than the running version, when one was found.
    public var available: UpdateRelease?
    /// When the last successful check ran; nil until one does.
    public var lastCheck: Date?
    /// True when the last check could not reach the feed; a later successful
    /// check clears it.
    public var lastCheckFailed: Bool

    public init(available: UpdateRelease?, lastCheck: Date?, lastCheckFailed: Bool) {
        self.available = available
        self.lastCheck = lastCheck
        self.lastCheckFailed = lastCheckFailed
    }

    /// English status line for the Settings pane. Availability wins, then the
    /// failure flag, then "not checked yet"; the wording is pinned by tests.
    public var message: String {
        if let available {
            return "Stare \(available.version.displayString) is available"
        }
        if lastCheckFailed {
            return "Couldn't reach GitHub"
        }
        if lastCheck == nil {
            return "Not checked yet"
        }
        return "Stare is up to date"
    }
}

/// Updates without Sparkle (S6): a checker over an injected `UpdateFeed` that
/// compares the feed's release against the running version and reports a newer
/// one. The app is not notarized, so this only informs and links — the pane
/// opens `UpdateRelease.pageURL` in the browser (or the user runs
/// `brew upgrade --cask stare`); it never installs anything.
///
/// Time and network are injected: `checkNow(at:)` takes the timestamp, the
/// feed comes from the initializer, and `currentVersion` is passed in —
/// `Bundle.main` is never read inside StareCore.
public actor UpdateChecker {
    /// The running version, injected by the app; a release must be strictly
    /// newer than this to be reported.
    public let currentVersion: SemanticVersion

    private let feed: UpdateFeed
    private var statusValue: UpdateStatus

    /// The current status; initially "Not checked yet".
    public var status: UpdateStatus { statusValue }

    /// Creates a checker over `feed` that only reports releases newer than
    /// `currentVersion`. The app passes its version from its own Bundle; the
    /// core never reads one itself.
    public init(feed: UpdateFeed, currentVersion: SemanticVersion) {
        self.feed = feed
        self.currentVersion = currentVersion
        self.statusValue = UpdateStatus(available: nil, lastCheck: nil, lastCheckFailed: false)
    }

    /// Runs a check when `schedule` says one is due against the caller's
    /// persisted `lastCheck`; otherwise the feed is never contacted and the
    /// status stays untouched. The calendar decides day/week boundaries and is
    /// injectable like every other ambient value.
    public func checkIfDue(now: Date, schedule: UpdateCheckSchedule, lastCheck: Date?, calendar: Calendar = .current) async {
        guard schedule.isDue(lastCheck: lastCheck, now: now, calendar: calendar) else { return }
        await checkNow(at: now)
    }

    /// Runs a check right now, stamping `now` as `lastCheck` on success. A
    /// failing feed sets `lastCheckFailed` and leaves the previous status —
    /// including any previously available release and its `lastCheck` —
    /// intact.
    public func checkNow(at now: Date) async {
        do {
            let release = try await feed.latestRelease()
            let available = release.flatMap { $0.version > currentVersion ? $0 : nil }
            statusValue = UpdateStatus(available: available, lastCheck: now, lastCheckFailed: false)
        } catch {
            statusValue.lastCheckFailed = true
        }
    }
}
