import Foundation
import XCTest

@testable import StareCore

/// Tests for the persisted capture preferences (T3/S6): today's capture is a
/// PNG written to the clipboard with the suggested name "Stare.png", so the
/// defaults must reproduce exactly that, and every unsafe value the blob or a
/// setter can produce must fall back instead of reaching the filesystem.

/// Gregorian UTC calendar and fixed dates, so time-dependent code has nothing
/// to inject from the environment.
private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private func decode(_ json: String) throws -> CapturePreference {
    try JSONDecoder().decode(CapturePreference.self, from: Data(json.utf8))
}

final class CapturePreferenceTests: XCTestCase {
    // MARK: Formats

    func testFormatsArePngAndJpegWithTitlesAndExtensions() {
        XCTAssertEqual(CaptureFormat.allCases, [.png, .jpeg])
        XCTAssertEqual(CaptureFormat.png.title, "PNG")
        XCTAssertEqual(CaptureFormat.png.fileExtension, "png")
        XCTAssertEqual(CaptureFormat.jpeg.title, "JPEG")
        XCTAssertEqual(CaptureFormat.jpeg.fileExtension, "jpg")
    }

    // MARK: Defaults reproduce today's behaviour (S6/S7)

    func testStandardIsPngToClipboardWithStarePrefix() {
        XCTAssertEqual(CapturePreference.standard.format, .png)
        XCTAssertEqual(CapturePreference.standard.destination, .clipboard)
        XCTAssertEqual(CapturePreference.standard.fileNamePrefix, "Stare")
        XCTAssertEqual(CapturePreference.standard, CapturePreference())
    }

    func testFreshInstallTemplateIsTheDocumentedTemplate() {
        // The shipped default is the explicit template that says what it does: it
        // renders, byte for byte, the name the empty template's legacy branch
        // produced — so the field's own example row and the save paths agree.
        XCTAssertEqual(CapturePreference.defaultFileNameTemplate, "Stare-{date}-at-{time}")
        XCTAssertEqual(CapturePreference().fileNameTemplate, "Stare-{date}-at-{time}")
        XCTAssertEqual(CapturePreference.standard.fileNameTemplate, "Stare-{date}-at-{time}")
    }

    // MARK: File name shape

    func testFileNameHasPinnedShapeAndExtensionPerFormat() {
        let at = date(2026, 11, 21, 14, 5, 33)
        XCTAssertEqual(CapturePreference.standard.fileName(at: at, calendar: calendar), "Stare-2026-11-21-at-14-05-33.png")

        var jpeg = CapturePreference.standard
        jpeg.format = .jpeg
        XCTAssertEqual(jpeg.fileName(at: at, calendar: calendar), "Stare-2026-11-21-at-14-05-33.jpg")
    }

    func testFileNameGroupNameStaysStableWithCustomPrefix() {
        var prefs = CapturePreference.standard
        prefs.fileNamePrefix = "Shots"
        // The prefix drives the name only when no template is set — the
        // stored-empty case (S4): a stored preference with `""` keeps the
        // user's prefix, byte for byte. A fresh install carries the explicit
        // default template instead, pinned where the default is tested.
        prefs.fileNameTemplate = ""
        XCTAssertEqual(prefs.fileName(at: date(2026, 1, 2, 3, 4, 5), calendar: calendar), "Shots-2026-01-02-at-03-04-05.png")
    }

    func testFileNameIsNeverDefeatedByUnsafeValues() {
        // Whatever garbage produced the preference, the produced name carries
        // only the escaped-safe character set: prefix alphanumerics, "-", "_",
        // "." and the date's digits, so no character ever needs quoting.
        let at = date(2026, 11, 21, 14, 5, 33)
        var prefs = CapturePreference(format: .png, destination: .clipboard, fileNamePrefix: "a/b c\u{301}")
        let name = prefs.fileName(at: at, calendar: calendar)
        XCTAssertEqual(name, "Stare-2026-11-21-at-14-05-33.png")
        XCTAssertEqual(name, name.filter { $0.isASCII })
    }

    // MARK: Prefix sanitisation

    func testPrefixSanitisationFallsBackToStareOnUnsafeValues() {
        func prefix(_ raw: String) -> String {
            CapturePreference(format: .png, destination: .clipboard, fileNamePrefix: raw).fileNamePrefix
        }
        XCTAssertEqual(prefix(""), "Stare")
        XCTAssertEqual(prefix("   "), "Stare")
        XCTAssertEqual(prefix("My Shots"), "Stare") // space needs quoting
        XCTAssertEqual(prefix("a/b"), "Stare") // path separator
        XCTAssertEqual(prefix("a:b"), "Stare") // classic macOS separator
        XCTAssertEqual(prefix("main.swift"), "main.swift")
        XCTAssertEqual(prefix("Shots-2026"), "Shots-2026")
        XCTAssertEqual(prefix("fotos_é"), "Stare") // non-ASCII needs escaping
    }

    func testAssignedPrefixIsSanitisedToo() {
        var prefs = CapturePreference.standard
        prefs.fileNamePrefix = "a/b"
        XCTAssertEqual(prefs.fileNamePrefix, "Stare")
        prefs.fileNamePrefix = "Boards"
        XCTAssertEqual(prefs.fileNamePrefix, "Boards")
    }

    // MARK: Destination

    func testUsableFolderPathsSurvive() {
        XCTAssertEqual(
            CapturePreference(format: .png, destination: .folder(path: "~/Pictures/Screenshots"), fileNamePrefix: "Stare").destination,
            .folder(path: "~/Pictures/Screenshots")
        )
        XCTAssertEqual(
            CapturePreference(format: .png, destination: .folder(path: "/tmp/shots"), fileNamePrefix: "Stare").destination,
            .folder(path: "/tmp/shots")
        )
    }

    func testUnusableDestinationFallsBackToClipboard() {
        func destination(_ path: String) -> CaptureDestination {
            CapturePreference(format: .png, destination: .folder(path: path), fileNamePrefix: "Stare").destination
        }
        XCTAssertEqual(destination(""), .clipboard)
        XCTAssertEqual(destination("   "), .clipboard)
        // A relative path has no meaning for capture output: it must resolve
        // from an absolute root or the home directory.
        XCTAssertEqual(destination("relative/shots"), .clipboard)
        XCTAssertEqual(destination("Downloads"), .clipboard)
    }

    // MARK: Lenient decoding

    func testUnknownFormatFallsBackToPngAndKeepsTheRestOfTheDocument() throws {
        let decoded = try decode(
            #"{"format":"heic","destination":{"folder":"/tmp/shots"},"fileNamePrefix":"Shots"}"#
        )
        XCTAssertEqual(decoded.format, .png)
        XCTAssertEqual(decoded.destination, .folder(path: "/tmp/shots"))
        XCTAssertEqual(decoded.fileNamePrefix, "Shots")
    }

    func testUnusableDestinationInBlobFallsBackToClipboardAndKeepsTheRest() throws {
        let decoded = try decode(
            #"{"format":"jpeg","destination":{"folder":"   "},"fileNamePrefix":"Shots"}"#
        )
        XCTAssertEqual(decoded.format, .jpeg)
        XCTAssertEqual(decoded.destination, .clipboard)
        XCTAssertEqual(decoded.fileNamePrefix, "Shots")
    }

    func testUnsafePrefixInBlobFallsBackToStareAndKeepsTheRest() throws {
        let decoded = try decode(
            #"{"format":"jpeg","destination":{"clipboard":true},"fileNamePrefix":"a/b"}"#
        )
        XCTAssertEqual(decoded.format, .jpeg)
        XCTAssertEqual(decoded.destination, .clipboard)
        XCTAssertEqual(decoded.fileNamePrefix, "Stare")
    }

    func testMissingFieldsTakeStandard() throws {
        // S8 canary — re-aimed once in S4 (L6), again in S8: without a
        // `version` key the document predates version stamping, so `{}` is a
        // pre-change document whose missing template field is the old shipped
        // default `""`. The migration moves it to the shipped template, which
        // makes the whole decode the standard document. A document that this
        // build already versioned keeps the template-less state as stored:
        // empty, the cleared choice, the legacy prefix name.
        XCTAssertEqual(try decode(#"{}"#), CapturePreference.standard)
        XCTAssertEqual(try decode(#"{"version":2}"#).fileNameTemplate, "")
    }

    // MARK: The default reaches a preference stored before it (S8)

    /// The capture document the template-era builds stored: every field this
    /// build writes, carrying the old shipped default `""` — and no `version`
    /// key, because version stamping begins with this change. The owner's
    /// stored blob is this document byte for byte.
    private static let oldStoredCapture = #"{"format":"png","destination":{"clipboard":true},"fileNamePrefix":"Stare","downscaleMode":"off","maxSaveWidth":1600,"fileNameTemplate":"","backdropPadding":0,"backdropCornerRadius":0,"backdropShadow":false}"#

    /// The old stored default migrates once to the shipped template: the
    /// document carries no `version` key (it predates stamping), its stored
    /// template is exactly `""` — the old default — and decoding answers the
    /// template this build ships, so `Stare-{date}-at-{time}` finally reaches
    /// the install that stored `""` before it existed. The rendered name is
    /// unchanged: the template and the legacy branch produce the same name.
    func testStoredOldBlobWithTheOldDefaultMigratesToTheShippedDefault() throws {
        let decoded = try decode(Self.oldStoredCapture)
        XCTAssertEqual(decoded.fileNameTemplate, CapturePreference.defaultFileNameTemplate)
        XCTAssertEqual(
            decoded.fileName(at: date(2026, 11, 21, 14, 5, 33), calendar: calendar),
            "Stare-2026-11-21-at-14-05-33.png",
            "the migration changes what the field says, never the name it renders"
        )
        // The same pre-change generation when a readable older version is
        // present: nothing wrote one yet, but the rule is the shape's.
        XCTAssertEqual(try decode(#"{"version":1,"fileNameTemplate":""}"#).fileNameTemplate, CapturePreference.defaultFileNameTemplate)
    }

    /// A stored template that is anything else is a user's choice, and the
    /// migration never touches it — at any version, including the unstamped
    /// generation.
    func testStoredBlobWithACustomTemplateKeepsItByteForByte() throws {
        let custom = "boards-{date}"
        for (label, json) in [
            ("unstamped", #"{"fileNameTemplate":"boards-{date}"}"#),
            ("version 1", #"{"version":1,"fileNameTemplate":"boards-{date}"}"#),
            ("version 2", #"{"version":2,"fileNameTemplate":"boards-{date}"}"#),
        ] {
            XCTAssertEqual(try decode(json).fileNameTemplate, custom, "a \(label) document keeps a chosen template")
        }
    }

    /// A document at the current version carries a choice: an explicitly
    /// cleared template stays empty, and the legacy branch keeps answering —
    /// this is the state a user reaches by clearing the field after upgrading.
    func testStoredBlobAtTheCurrentVersionWithAnEmptyTemplateStaysEmpty() throws {
        for (label, json) in [
            ("current", #"{"version":2,"fileNamePrefix":"Shots","fileNameTemplate":""}"#),
            ("beyond", #"{"version":3,"fileNamePrefix":"Shots","fileNameTemplate":""}"#),
        ] {
            let decoded = try decode(json)
            XCTAssertEqual(decoded.fileNameTemplate, "", "a \(label) version keeps the cleared template")
            XCTAssertEqual(
                decoded.fileName(at: date(2026, 11, 21, 14, 5, 33), calendar: calendar),
                "Shots-2026-11-21-at-14-05-33.png",
                "a \(label) version keeps the prefix naming the files"
            )
        }
    }

    /// The toolbar's hard-won rule (9efcbbd), kept here: a version this build
    /// cannot read is a document this build does not understand — it counts as
    /// current, and the migration never runs on it.
    func testAGarbledVersionNeverMigratesTheTemplate() throws {
        for garbled in ["\"abc\"", "true", "2.5", "null", "\"2\"", "[]"] {
            let json = "{\"version\":" + garbled + ",\"fileNamePrefix\":\"Stare\",\"fileNameTemplate\":\"\"}"
            XCTAssertEqual(
                try decode(json).fileNameTemplate,
                "",
                "a document whose version is \(garbled) must be left exactly as stored"
            )
        }
    }

    /// The upgrade may move the template and nothing else: every other field
    /// of the stored capture document survives a decode that migrates it.
    func testTheMigrationTouchesNothingElseInTheStoredCaptureDocument() throws {
        let decoded = try decode(
            #"{"format":"jpeg","destination":{"folder":"/Users/al/Pictures/Stare"},"fileNamePrefix":"Shots","downscaleMode":"maxWidth","maxSaveWidth":900,"fileNameTemplate":"","backdropPadding":40,"backdropCornerRadius":12,"backdropShadow":true}"#
        )
        var expected = CapturePreference(
            format: .jpeg,
            destination: .folder(path: "/Users/al/Pictures/Stare"),
            fileNamePrefix: "Shots"
        )
        expected.downscaleMode = .maxWidth
        expected.maxSaveWidth = 900
        expected.backdropPadding = 40
        expected.backdropCornerRadius = 12
        expected.backdropShadow = true
        XCTAssertEqual(decoded, expected)
    }

    /// Whatever this build itself saved is never migrated again: the document
    /// it writes carries the current version, so a template the user cleared
    /// afterwards reloads as the cleared choice — the after-upgrade empty.
    func testADeliberatelyClearedTemplateSurvivesThisBuildsOwnSave() throws {
        var cleared = CapturePreference.standard
        cleared.fileNamePrefix = "Shots"
        cleared.fileNameTemplate = ""
        let data = try JSONEncoder().encode(cleared)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, CapturePreference.currentVersion, "this build stamps every capture document it writes")
        XCTAssertEqual(try JSONDecoder().decode(CapturePreference.self, from: data), cleared)
    }

    // MARK: Round trip

    func testRoundTripsThroughJSON() throws {
        let saved = CapturePreference(
            format: .jpeg,
            destination: .folder(path: "/Users/al/Pictures/Stare"),
            fileNamePrefix: "Shots"
        )
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(CapturePreference.self, from: data), saved)
    }

    func testStandardRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(CapturePreference.standard)
        XCTAssertEqual(try JSONDecoder().decode(CapturePreference.self, from: data), CapturePreference.standard)
    }

    // MARK: Downscaling on save (T7/S14) — off by default

    func testStandardSavesExactlyAsCaptured() {
        // Off by default: every capture is saved exactly as today.
        XCTAssertEqual(CapturePreference.standard.downscaleMode, .off)
        XCTAssertEqual(CapturePreference.standard.maxSaveWidth, CapturePreference.defaultMaxSaveWidth)
    }

    func testMaxSaveWidthNeverDegradesToNothing() {
        var preference = CapturePreference.standard
        preference.maxSaveWidth = 800
        XCTAssertEqual(preference.maxSaveWidth, 800)
        preference.maxSaveWidth = 0
        XCTAssertEqual(preference.maxSaveWidth, 1)
        preference.maxSaveWidth = -50
        XCTAssertEqual(preference.maxSaveWidth, 1)
    }

    func testDownscaleSettingsRoundTripThroughJSON() throws {
        var saved = CapturePreference.standard
        saved.downscaleMode = .maxWidth
        saved.maxSaveWidth = 1200
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(CapturePreference.self, from: data), saved)

        saved.downscaleMode = .oneX
        saved.maxSaveWidth = CapturePreference.defaultMaxSaveWidth
        let oneXData = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(CapturePreference.self, from: oneXData), saved)
    }

    func testBlobWithoutDownscaleFieldsKeepsSavingExactlyAsToday() throws {
        // A document written before downscaling existed decodes with the
        // switch off and the default width, and every other field intact.
        let decoded = try decode(
            #"{"format":"jpeg","destination":{"folder":"/tmp/shots"},"fileNamePrefix":"Shots"}"#
        )
        XCTAssertEqual(decoded.format, .jpeg)
        XCTAssertEqual(decoded.destination, .folder(path: "/tmp/shots"))
        XCTAssertEqual(decoded.fileNamePrefix, "Shots")
        XCTAssertEqual(decoded.downscaleMode, .off)
        XCTAssertEqual(decoded.maxSaveWidth, CapturePreference.defaultMaxSaveWidth)
    }

    func testUnknownDownscaleModeInBlobFallsBackToOffAndKeepsTheRest() throws {
        let decoded = try decode(
            #"{"format":"png","destination":{"clipboard":true},"fileNamePrefix":"Shots","downscaleMode":"squish"}"#
        )
        XCTAssertEqual(decoded.downscaleMode, .off)
        XCTAssertEqual(decoded.fileNamePrefix, "Shots")
    }

    func testGarbageMaxSaveWidthInBlobNeverStoresAZero() throws {
        let decoded = try decode(
            #"{"format":"png","destination":{"clipboard":true},"fileNamePrefix":"Shots","maxSaveWidth":0}"#
        )
        XCTAssertEqual(decoded.maxSaveWidth, 1)
        let wrongType = try decode(
            #"{"format":"png","destination":{"clipboard":true},"fileNamePrefix":"Shots","maxSaveWidth":"wide"}"#
        )
        XCTAssertEqual(wrongType.maxSaveWidth, CapturePreference.defaultMaxSaveWidth)
        XCTAssertEqual(wrongType.downscaleMode, .off)
    }
}
