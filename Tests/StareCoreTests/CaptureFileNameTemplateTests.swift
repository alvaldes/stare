import AppKit
import XCTest

@testable import StareCore

/// Tests for file-name templates over the folder destination (T10/S17): a
/// template with `{date}`, `{time}`, `{app}` and `{display}` tokens replaces
/// today's fixed shape, and an empty template reproduces today's name byte
/// for byte. Every refusal — unknown token, malformed braces, unsafe literal,
/// unavailable app or display — falls back to today's prefix name, following
/// the file's house rule: a value that cannot be honoured degrades to the
/// known-good name instead of writing one nobody asked for. (The PRESERVE pin
/// for today's name lives in `CaptureFileNamePreservePinTests`.)
final class CaptureFileNameTemplateTests: XCTestCase {
    /// Gregorian UTC calendar and a fixed instant, so dates and times are
    /// pinned exactly and nothing is injected from the environment.
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private lazy var date: Date = {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 14, minute: 5, second: 33))!
    }()

    // MARK: Templates render the tokens

    func testTemplateWithDateAndTimeTokensRendersTheirComponents() {
        var preference = CapturePreference.standard
        preference.fileNameTemplate = "{date}_{time}"
        XCTAssertEqual(
            preference.fileName(at: date, calendar: calendar),
            "2026-11-21_14-05-33.png"
        )
    }

    func testTemplateWithAppAndDisplayTokensSubstitutesTheGivenValues() {
        var preference = CapturePreference.standard
        preference.fileNameTemplate = "{app}-on-{display}-{date}"
        XCTAssertEqual(
            preference.fileName(at: date, calendar: calendar, app: "Safari", display: "Studio"),
            "Safari-on-Studio-2026-11-21.png"
        )
        // In another format the extension follows the format, as today.
        preference.format = .jpeg
        XCTAssertEqual(
            preference.fileName(at: date, calendar: calendar, app: "Safari", display: "Studio"),
            "Safari-on-Studio-2026-11-21.jpg"
        )
    }

    func testTokenValuesKeepOnlySafeCharacters() {
        var preference = CapturePreference.standard
        preference.fileNameTemplate = "{app}-{date}"
        // Path separators, spaces, shell metacharacters and non-ASCII are
        // dropped from substitute values, never reaching the filesystem.
        XCTAssertEqual(
            preference.fileName(at: date, calendar: calendar, app: "App/Store ✨", display: "Studio!"),
            "AppStore-2026-11-21.png"
        )
    }

    // MARK: Refusals — every unusable template degrades to today's name

    func testUnknownTokenRefusesTheWholeTemplate() {
        var preference = CapturePreference.standard
        preference.fileNamePrefix = "Shots"
        preference.fileNameTemplate = "{date}-{bogus}"
        // The literal token is never written: an unknown token refuses the
        // template and today's name is produced instead — matching this
        // file's habit of degrading an unsafe value to the known good one.
        XCTAssertEqual(preference.fileName(at: date, calendar: calendar), "Shots-2026-11-21-at-14-05-33.png")
    }

    func testMalformedBracesRefuseTheTemplate() {
        func name(_ template: String) -> String {
            var preference = CapturePreference.standard
            preference.fileNamePrefix = "Shots"
            preference.fileNameTemplate = template
            return preference.fileName(at: date, calendar: calendar)
        }
        XCTAssertEqual(name("{date"), "Shots-2026-11-21-at-14-05-33.png")
        XCTAssertEqual(name("date}"), "Shots-2026-11-21-at-14-05-33.png")
        XCTAssertEqual(name("sh{}ot"), "Shots-2026-11-21-at-14-05-33.png")
        XCTAssertEqual(name("sh{app ot"), "Shots-2026-11-21-at-14-05-33.png")
    }

    func testUnavailableAppOrDisplayValueRefusesTheTemplate() {
        // A token with no value to substitute cannot be honoured either: the
        // template is refused rather than writing a name with a hole in it.
        var preference = CapturePreference.standard
        preference.fileNamePrefix = "Shots"
        preference.fileNameTemplate = "{app}-{display}-{date}"
        let legacy = "Shots-2026-11-21-at-14-05-33.png"
        XCTAssertEqual(preference.fileName(at: date, calendar: calendar), legacy, "no app, no display")
        XCTAssertEqual(preference.fileName(at: date, calendar: calendar, app: "Safari"), legacy, "display missing")
        XCTAssertEqual(preference.fileName(at: date, calendar: calendar, display: "Studio"), legacy, "app missing")
    }

    func testUnsafeLiteralTextRefusesTheTemplateAtStorage() {
        func stored(_ raw: String) -> String {
            CapturePreference(format: .png, destination: .clipboard, fileNamePrefix: "Stare", fileNameTemplate: raw)
                .fileNameTemplate
        }
        // Literal text keeps the safe character set only: no space, no path
        // separator, no shell metacharacter, no non-ASCII.
        XCTAssertEqual(stored("My {date} shots"), "") // space
        XCTAssertEqual(stored("a/{date}"), "") // path separator
        XCTAssertEqual(stored("{date}:{time}"), "") // colon
        XCTAssertEqual(stored("fotos_{date}_é"), "") // non-ASCII
        XCTAssertEqual(stored("{date}"), "{date}")
        XCTAssertEqual(stored("shots-{date}_{time}"), "shots-{date}_{time}")
    }

    func testTemplateTraversalCannotEscapeTheDestinationFolder() throws {
        // A token carrying a path separator, a dot-dot, or a template with a
        // literal separator can never move the file out of the folder: the
        // write lands inside it or not at all.
        let folder = try temporaryFolder()
        var preference = CapturePreference(
            format: .png,
            destination: .folder(path: folder.path),
            fileNamePrefix: "Stare"
        )
        preference.fileNameTemplate = "{app}-{date}"
        let url = try XCTUnwrap(
            CaptureFile.write(
                CGImage.solid(width: 4, height: 4)!,
                preference: preference,
                date: date,
                calendar: calendar,
                app: "../../etc/passwd",
                displayName: nil
            )
        )
        XCTAssertEqual(
            url.lastPathComponent,
            "....etcpasswd-2026-11-21.png",
            "separators never survive; dots do, but without a separator a dot run cannot form a traversal"
        )
        XCTAssertFalse(url.lastPathComponent.contains("/"))
        XCTAssertTrue(url.path.hasPrefix(folder.path + "/"), "the file never escapes the destination folder")

        // And even a dot-dot value still names one component inside the
        // folder, because the extension is always appended and no separator
        // can survive the substitution.
        preference.fileNameTemplate = "{app}"
        let dotDot = try XCTUnwrap(
            CaptureFile.write(
                CGImage.solid(width: 4, height: 4)!,
                preference: preference,
                date: date,
                calendar: calendar,
                app: "..",
                displayName: nil
            )
        )
        XCTAssertEqual(dotDot.lastPathComponent, "...png")
        XCTAssertTrue(dotDot.path.hasPrefix(folder.path + "/"))
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Empty template is today's behaviour, byte for byte

    func testEmptyTemplateIgnoresAppAndDisplayAndKeepsThePrefixName() {
        var preference = CapturePreference.standard
        preference.fileNamePrefix = "Shots"
        XCTAssertEqual(
            preference.fileName(at: date, calendar: calendar, app: "Safari", display: "Studio"),
            "Shots-2026-11-21-at-14-05-33.png"
        )
        preference.fileNameTemplate = ""
        XCTAssertEqual(
            preference.fileName(at: date, calendar: calendar, app: "Safari", display: "Studio"),
            "Shots-2026-11-21-at-14-05-33.png"
        )
    }

    // MARK: Determinism

    func testSameInputsProduceTheSameName() {
        var preference = CapturePreference.standard
        preference.fileNameTemplate = "{app}-on-{display}-{date}-{time}"
        let first = preference.fileName(at: date, calendar: calendar, app: "Safari", display: "Studio")
        let second = preference.fileName(at: date, calendar: calendar, app: "Safari", display: "Studio")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, "Safari-on-Studio-2026-11-21-14-05-33.png")
    }

    // MARK: The folder write uses the templated name

    func testFolderSaveWritesTheTemplatedName() throws {
        let folder = try temporaryFolder()
        var preference = CapturePreference(
            format: .png,
            destination: .folder(path: folder.path),
            fileNamePrefix: "Stare"
        )
        preference.fileNameTemplate = "{date}_{time}"
        let url = try XCTUnwrap(
            CaptureFile.write(CGImage.solid(width: 4, height: 4)!, preference: preference, date: date, calendar: calendar)
        )
        XCTAssertEqual(url.lastPathComponent, "2026-11-21_14-05-33.png")
        XCTAssertTrue(url.path.hasPrefix(folder.path + "/"))
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Lenient decoding of the new field

    func testBlobWithoutTemplateFieldDecodesEmpty() throws {
        let decoded = try JSONDecoder().decode(
            CapturePreference.self,
            from: Data(#"{"format":"jpeg","destination":{"folder":"/tmp/shots"},"fileNamePrefix":"Shots"}"#.utf8)
        )
        XCTAssertEqual(decoded.fileNameTemplate, "")
        XCTAssertEqual(decoded, CapturePreference(format: .jpeg, destination: .folder(path: "/tmp/shots"), fileNamePrefix: "Shots"))
    }

    func testUnknownOrUnsafeTemplateInBlobDecodesEmptyAndKeepsTheRest() throws {
        let unknownToken = try JSONDecoder().decode(
            CapturePreference.self,
            from: Data(#"{"format":"png","destination":{"clipboard":true},"fileNamePrefix":"Shots","fileNameTemplate":"{bogus}"}"#.utf8)
        )
        XCTAssertEqual(unknownToken.fileNameTemplate, "")
        XCTAssertEqual(unknownToken.fileNamePrefix, "Shots")
        let unsafeLiteral = try JSONDecoder().decode(
            CapturePreference.self,
            from: Data(#"{"format":"png","destination":{"clipboard":true},"fileNamePrefix":"Shots","fileNameTemplate":"a b {date}"}"#.utf8)
        )
        XCTAssertEqual(unsafeLiteral.fileNameTemplate, "")
    }

    func testTemplateRoundTripsThroughJSON() throws {
        var saved = CapturePreference.standard
        saved.fileNameTemplate = "{app}_{date}_{time}"
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(CapturePreference.self, from: data), saved)
    }

    // MARK: Assignment sanitisation

    func testAssignedTemplateIsSanitisedToo() {
        var preference = CapturePreference.standard
        preference.fileNameTemplate = "a/{bogus}"
        XCTAssertEqual(preference.fileNameTemplate, "")
        preference.fileNameTemplate = "{time}"
        XCTAssertEqual(preference.fileNameTemplate, "{time}")
        preference.fileNameTemplate = "   {date}   "
        XCTAssertEqual(preference.fileNameTemplate, "{date}", "surrounding whitespace is trimmed")
        preference.fileNameTemplate = "   "
        XCTAssertEqual(preference.fileNameTemplate, "")
    }

    // MARK: Scratch folder

    /// A fresh temp directory per test, removed again before the test ends.
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("stare-template-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

private extension CGImage {
    /// A small solid image, enough for the encoders.
    static func solid(width: Int, height: Int) -> CGImage? {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }
}
