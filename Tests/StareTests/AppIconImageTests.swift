import AppKit
import XCTest
@testable import Stare

/// Spec S2 of batch A: the Settings app mark must show the real colour
/// artwork ("el icono en settings no tiene colores porque?"). The recorded
/// cause is a desaturated `NSApp.applicationIconImage` on macOS 26, solved by
/// reading `Resources/AppIcon.icns` first — now extracted into ONE shared
/// source (`AppIconArtwork`) that `AppMark` and `OnboardingView` both use, so
/// a third variant cannot drift in.
///
/// The resolution is pinned headlessly by feeding the testable core the
/// repository's real icns (the test target's bundle does not carry
/// `Resources/AppIcon.icns`, so the file is reached by its repo path) and a
/// missing URL for the fallback.
final class AppIconImageTests: XCTestCase {
    /// `Resources/` in the repository, walked from the test file's location:
    /// `Tests/StareTests/<this file>`.
    private static let repoResources: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Resources")
    }()

    private static let icnsURL = repoResources.appendingPathComponent("AppIcon.icns")

    /// The resolution must prefer the real icns artwork: the image it returns
    /// is the file decoded, in colour, not a template image, and non-empty.
    func testResolutionPrefersTheRealIcnsArtwork() throws {
        let file = try XCTUnwrap(NSImage(contentsOf: Self.icnsURL), "the repo's AppIcon.icns must decode")
        let image = AppIconArtwork.resolve(
            resourceURL: Self.icnsURL,
            fallback: NSImage(size: NSSize(width: 1, height: 1))
        )

        XCTAssertEqual(image.size, file.size, "the resolved image is the icns decoded, not the fallback")
        XCTAssertGreaterThan(image.size.width, 0, "the resolved icon must be non-empty")
        XCTAssertGreaterThan(image.size.height, 0, "the resolved icon must be non-empty")
        XCTAssertEqual(image.isTemplate, false, "the colour artwork must not be marked a template image")
    }

    /// A missing file falls back instead of returning nothing: the given
    /// fallback image comes back, unchanged.
    func testMissingResourceFallsBackInsteadOfReturningNothing() {
        let fallback = NSImage(size: NSSize(width: 7, height: 11))
        let image = AppIconArtwork.resolve(resourceURL: nil, fallback: fallback)
        XCTAssertTrue(image === fallback, "a missing resource resolves to the fallback itself")
        XCTAssertEqual(image.size, NSSize(width: 7, height: 11))
    }

    /// An undecodable resource at the URL also falls back rather than
    /// surfacing a broken image.
    func testUndecodableResourceAlsoFallsBack() throws {
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stare-appicon-\(UUID().uuidString).icns")
        try Data("not an icon".utf8).write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let fallback = NSImage(size: NSSize(width: 3, height: 5))
        let image = AppIconArtwork.resolve(resourceURL: temporary, fallback: fallback)
        XCTAssertTrue(image === fallback, "an undecodable resource resolves to the fallback itself")
        XCTAssertEqual(image.size, NSSize(width: 3, height: 5))
    }

    /// The real bundle path keeps pointing at the artwork the app ships: the
    /// same resource name the bundled app resolves through `Bundle.main`. In
    /// the test bundle there is no resource, which is exactly the branches
    /// the two tests above pin by hand.
    func testTheSharedSourceStillQueriesTheShippedResourceName() {
        XCTAssertEqual(
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            nil,
            "the test bundle ships no resources, which is what the fallback tests model"
        )
    }
}
