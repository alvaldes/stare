import Foundation
import XCTest

import StareCore
@testable import Stare

/// The preview and the save path are one answer (S4): the Settings row and
/// the capture editor's save panel both name the file through the same
/// `CapturePreference.fileName(at:calendar:app:display:)` call with the same
/// inputs, so a template is never previewed under one name and saved under
/// another. Neither the editor nor the preview can know the capture's app or
/// display — the capture instant is gone by the time a panel exists, and the
/// only resolver the capture path has (`CaptureAppIdentity`) refuses `{app}`
/// while Stare itself is frontmost — so both pass none, and an `{app}` or
/// `{display}` token previews and saves the same fallback: the prefix name.
final class CaptureFileNamePreviewTests: XCTestCase {
    /// Gregorian UTC calendar and a fixed instant, so the names are pinned
    /// exactly and nothing is injected from the environment.
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private lazy var sample: Date = {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 14, minute: 5, second: 33))!
    }()

    // MARK: The shipped default through the editor seam

    func testShippedDefaultRendersTheDocumentedExample() {
        // The name field of an editor save panel defaults to exactly the
        // name the Settings preview row documents.
        XCTAssertEqual(
            CaptureEditorCanvas.savePanelFileName(preference: .standard, at: sample, calendar: calendar),
            "Stare-2026-11-21-at-14-05-33.png"
        )
    }

    // MARK: The seam follows the template as it changes

    func testSavePanelNameFollowsTheTemplateAsItChanges() {
        var preference = CapturePreference.standard
        XCTAssertEqual(
            CaptureEditorCanvas.savePanelFileName(preference: preference, at: sample, calendar: calendar),
            "Stare-2026-11-21-at-14-05-33.png"
        )
        preference.fileNameTemplate = "{date}_{time}"
        XCTAssertEqual(
            CaptureEditorCanvas.savePanelFileName(preference: preference, at: sample, calendar: calendar),
            "2026-11-21_14-05-33.png"
        )
        // An `{app}` template with no app to substitute — the editor's own
        // honest position — degrades to the prefix name instead of writing a
        // hole or a guess into the file name.
        preference.fileNameTemplate = "{app}"
        XCTAssertEqual(
            CaptureEditorCanvas.savePanelFileName(preference: preference, at: sample, calendar: calendar),
            "Stare-2026-11-21-at-14-05-33.png"
        )
    }

    // MARK: Preview and save panel are one call with the same inputs

    func testPreviewAndSavePanelAreTheSameCallWithTheSameInputs() {
        // Whichever way the template changes, the editor's save-panel name
        // and the preview name are produced by the same call with the same
        // inputs: none of app and none of display.
        for template in ["", "{date}", "{date}-at-{time}", "{app}", "{app}-{display}", "{date}_{time}_{app}_{display}"] {
            var preference = CapturePreference.standard
            preference.fileNameTemplate = template
            XCTAssertEqual(
                CaptureEditorCanvas.savePanelFileName(preference: preference, at: sample, calendar: calendar),
                preference.fileName(at: sample, calendar: calendar, app: nil, display: nil),
                "template \(String(describing: template)): the panel and the preview must be one call"
            )
        }
    }
}
