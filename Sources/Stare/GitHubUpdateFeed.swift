import Foundation
import SwiftUI
import StareCore

/// The `UpdateFeed` implementation over the public GitHub releases API
/// (T10/S6): `releases/latest` of `alvaldes/stare`, which skips drafts and
/// prereleases. Comparison and scheduling stay in StareCore's
/// `UpdateChecker`; this type only speaks HTTP and JSON.
struct GitHubUpdateFeed: UpdateFeed {
    static let releasesURL = URL(string: "https://api.github.com/repos/alvaldes/stare/releases/latest")!

    /// Process-wide count of feed contacts. The selftest reads it to prove a
    /// check that is not due never reaches the network.
    static let callCounter = FeedCallCounter()

    func latestRelease() async throws -> UpdateRelease? {
        Self.callCounter.increment()
        var request = URLRequest(url: Self.releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateFeedError.unreachable
        }
        let release = try JSONDecoder().decode(ReleaseEnvelope.self, from: data)
        guard let version = SemanticVersion(string: release.tagName),
            let pageURL = URL(string: release.htmlURL)
        else { return nil }
        return UpdateRelease(version: version, pageURL: pageURL, highlights: Self.highlights(in: release.body))
    }

    /// Short release-note lines for the pane: the first bullet points of the
    /// release body, markdown stripped, at most three.
    static func highlights(in body: String?) -> [String] {
        guard let body else { return [] }
        let lines = body
            .split(separator: "\n")
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "*` "))
            }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(3))
    }

    private struct ReleaseEnvelope: Decodable {
        let tagName: String
        let htmlURL: String
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
        }
    }
}

/// Why a feed lookup failed — the checker turns any error into
/// `lastCheckFailed`, so the cases only exist to name the failure in the log.
enum UpdateFeedError: Error {
    case unreachable
}

/// Thread-safe counter for the feed contacts the selftest observes.
final class FeedCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// The app-side runner over StareCore's `UpdateChecker` (T10/S6). The
/// version comes from the bundle (`AppVersion`'s dev-runner fallback covers
/// `swift run`, which has no Info.plist) and the check's outcome is published
/// through the one preferences model: `lastCheck` rides the persisted
/// `updates` field, availability rides the runtime mirror.
///
/// The app is not notarized: a check only informs and links to the release
/// page — nothing is ever installed.
@MainActor
enum UpdateFlow {
    /// The real network feed for production and the selftest's not-due check.
    static let feed = GitHubUpdateFeed()

    /// The running version from the bundle; an unparseable version reads as
    /// zero, so any real release is reported rather than none.
    static var currentVersion: SemanticVersion {
        var version = SemanticVersion(major: 0, minor: 0, patch: 0)!
        if let parsed = SemanticVersion(string: AppVersion.short) {
            version = parsed
        }
        return version
    }

    /// Runs a check right now and publishes the outcome; a success stamps
    /// `lastCheck` into the persisted blob, a failure leaves it untouched.
    static func checkNow(model: PreferencesModel) async {
        let checker = UpdateChecker(feed: feed, currentVersion: currentVersion)
        await checker.checkNow(at: Date())
        model.noteUpdateCheck(await checker.status)
    }

    /// Runs a check only when the persisted schedule says one is due against
    /// the persisted `lastCheck`; otherwise the feed is never contacted and
    /// the stored state stays exactly as it was.
    static func checkIfDue(model: PreferencesModel) async {
        let now = Date()
        guard model.updateSchedule.isDue(lastCheck: model.updateLastCheck, now: now) else { return }
        let checker = UpdateChecker(feed: feed, currentVersion: currentVersion)
        await checker.checkNow(at: now)
        model.noteUpdateCheck(await checker.status)
    }
}
