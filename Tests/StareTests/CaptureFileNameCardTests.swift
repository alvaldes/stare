import AppKit
import SwiftUI
import XCTest

@testable import Stare
import StareCore

/// T1/S1–S3 of D4, and S4: the file-name card reads as one chain — the
/// control that governs, then the name it writes — not four blocks of
/// prose. The chain's source is pinned as the pane's own decision
/// (`CapturePane.fileNameSource`), the copy as the pane's constants (the
/// seam `SettingsHiddenSectionTests` uses for the pool card), and the
/// pane's field count and enabled states by walking the real render the
/// way `SettingsCapturePaneDisabledStateTests` does, so nothing here
/// inspects SwiftUI internals. The name the chain shows keeps its pinned
/// promise: it is the very call the save panel makes
/// (`CaptureEditorCanvas.savePanelFileName`) at the pane's fixed sample
/// instant — the rendered name never changes for the same inputs.
@MainActor
final class CaptureFileNameCardTests: XCTestCase {

    /// An in-memory `PreferenceStore`, so the probe never touches the user's
    /// real preferences — the same isolation the render tests use.
    private final class InMemoryPreferenceStore: PreferenceStore {
        private var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    /// A permission client that answers without touching TCC: the probe is
    /// only there because the pane factory takes one.
    private struct StubScreenRecordingClient: ScreenRecordingClient {
        func preflight() -> Bool { true }
        func request() -> Bool { true }
        func canCapture() -> Bool { true }
        func openPrivacySettings() {}
    }

    /// Gregorian UTC calendar and the pane's fixed sample instant, so the
    /// names are pinned exactly and nothing is injected from the environment.
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static let sample: Date = {
        calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 21, hour: 14, minute: 5, second: 33
        ))!
    }()

    // MARK: S3 — the chain runs from the control that governs

    func testTheChainSourceFollowsTheGoverningControl() {
        XCTAssertEqual(
            CapturePane.fileNameSource(fileNameTemplate: "{date}"), .template,
            "while a template is set it builds the whole file name, so the chain runs from the template"
        )
        XCTAssertEqual(
            CapturePane.fileNameSource(fileNameTemplate: ""), .prefix,
            "a cleared template hands the name back to the prefix, so the chain runs from it"
        )
    }

    // MARK: S3, and S4 — the copy, cut to what typing needs

    /// The template row's detail is the tokens, the safe characters and
    /// the extension rule — the facts a user needs before typing. The rule
    /// lives in the caption under the rows, told about the STORED prefix:
    /// the prefix row itself is gone (S4) because the template supersedes
    /// it, so the caption names the still-real fallback without referring
    /// to a control that is no longer there. The {app}/{display} fallback
    /// hint lives under the chain where a refusal is seen; the old
    /// four-block prose is gone.
    func testTheCardCopyIsCutToWhatTypingNeeds() {
        XCTAssertEqual(CapturePane.templateRowDetail, """
        Tokens: {date} · {time} · {app} · {display}, plus letters, numbers, \
        hyphen, underscore and dot — anything else isn't kept. The .png or \
        .jpg extension is added automatically.
        """)
        XCTAssertEqual(CapturePane.templateRuleCaption, """
        Templates apply to folder saves. While a template is set it builds the \
        whole file name; clear it and the stored prefix names the files again.
        """, "S4: the caption talks about the stored prefix, never about a prefix control that is no longer in the pane")
        XCTAssertEqual(CapturePane.tokenFallbackHint, """
        {app} and {display} come from the capture itself; when they aren't \
        known, as in this preview, the name falls back to the prefix.
        """)
    }

    // MARK: S3 — the chain and its one error state

    /// The fallback hint is read at the moment it matters: only when the
    /// typed template names what no capture has been taken to know — or when
    /// the template is unusable, in which case the chain's fallback is visible
    /// already. A plain {date}/{time} template never shows it.
    func testTheFallbackHintShowsExactlyWhenTheTemplateNamesWhatOnlyACaptureKnows() {
        XCTAssertTrue(CapturePane.templateCanBeRefused("{app}"))
        XCTAssertTrue(CapturePane.templateCanBeRefused("{display}"))
        XCTAssertTrue(CapturePane.templateCanBeRefused("{app}-{display}"))
        XCTAssertTrue(CapturePane.templateCanBeRefused("{date}-{app}_{time}"))
        XCTAssertFalse(CapturePane.templateCanBeRefused("{date}"))
        XCTAssertFalse(CapturePane.templateCanBeRefused("Shots-{date}_at_{time}"))
        XCTAssertFalse(
            CapturePane.templateCanBeRefused(""),
            "an empty template does not govern the name, so the hint is not its reading"
        )
    }

    /// The little the chain says, pinned exactly: the governor is named by
    /// its own row's word.
    func testTheChainLabelsNameTheControls() {
        XCTAssertEqual(FileNameChain.templateLabel, "Template")
        XCTAssertEqual(FileNameChain.prefixLabel, "Prefix")
    }

    // MARK: The pinned field count — the prefix row is gone (S4); the chain adds no editable field

    func testThePaneCarriesExactlyItsThreeTextFieldsWithNoPrefixRowLeft() throws {
        let pane = try Self.read(destination: .folder(path: "~/Pictures/Stare"))
        XCTAssertEqual(
            pane.allTextFields.count, 3,
            "S4: the pane carries exactly the template and the two backdrop fields — the Name prefix row is gone, and the chain adds no TextField (the pane's field count is pinned)"
        )
        XCTAssertTrue(
            pane.allTextFields.contains { $0.stringValue == "{date}" },
            "the template row is the card's only name control, identified by its bound canary, never by tree order"
        )
        XCTAssertFalse(
            pane.allTextFields.contains { $0.stringValue == "Shots" },
            "S4: the Name prefix row is gone — a control the template always overrides has no business in the pane, and no other field may echo the stored prefix"
        )
        XCTAssertFalse(
            pane.allTextFields.contains { $0.stringValue == "2026-11-21.png" },
            "the chain's name renders as a static text, never as an editable field"
        )
    }

    // MARK: The chain's name is the save panel's name, for each token

    /// The preview promise keeping its seam (S2, restated for S5): for a
    /// template using each token, the name the chain shows — the pane's own
    /// `CaptureEditorCanvas.savePanelFileName` call at its fixed instant —
    /// is the name that comes from no capture. The Settings pane cannot
    /// know a FUTURE capture's app or display, so those tokens preview the
    /// prefix-name fallback here, exactly as the hint under the chain says.
    /// What a taken capture really names is pinned where its identity
    /// exists: `CaptureFileNamePreviewTests` drives the handoff threading
    /// its identity through.
    func testTheChainNameEqualsTheSavePanelNameForEachToken() throws {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.capture = CapturePreference(
            format: .png,
            destination: .folder(path: "~/Pictures/Stare"),
            fileNamePrefix: "Stare"
        )
        model.capture.fileNamePrefix = "Shots"
        let expected: [String: String] = [
            "": "Shots-2026-11-21-at-14-05-33.png",
            "{date}": "2026-11-21.png",
            "{time}": "14-05-33.png",
            "{date}_{time}": "2026-11-21_14-05-33.png",
            "{app}": "Shots-2026-11-21-at-14-05-33.png",
            "{display}": "Shots-2026-11-21-at-14-05-33.png",
        ]
        for (template, name) in expected.sorted(by: { $0.key < $1.key }) {
            model.capture.fileNameTemplate = template
            XCTAssertEqual(
                CaptureEditorCanvas.savePanelFileName(
                    preference: model.capture, at: Self.sample, calendar: Self.calendar
                ),
                name,
                "template '\(template)': the chain previews the name the save panel writes"
            )
        }
    }

    // MARK: - The render the field-count assertions read

    private struct Fields {
        /// Every text field in the hosting tree, in walk order.
        let allTextFields: [NSTextField]
    }

    /// The capture pane rendered offscreen at the given destination, its text
    /// fields walked from the hosting tree.
    private static func read(destination: CaptureDestination) throws -> Fields {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.capture = CapturePreference(
            format: .png,
            destination: destination,
            fileNamePrefix: "Stare"
        )
        // The canaries the sibling tests bind: the prefix and the template
        // field, when there was one, are told apart by content, never by
        // tree order. Since S4 only the template field exists, and the
        // prefix canary's ABSENCE is pinned above.
        model.capture.fileNamePrefix = "Shots"
        model.capture.fileNameTemplate = "{date}"

        let permission = PermissionProbe(
            permission: ScreenRecordingPermission(client: StubScreenRecordingClient())
        )
        let pane = SettingsView.pane(for: .capture, width: 766, model: model, permission: permission)
        let hosting = NSHostingView(rootView: pane)
        let size = CGSize(width: 766 + 2 * SettingsMetrics.panePadding, height: 680)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.appearance = NSAppearance(named: NSAppearance.Name.aqua)
        window.confineToPrimaryScreen()
        window.orderFrontRegardless()
        // The controls realize their AppKit backing on this run-loop hop,
        // the same settle time the other render tests use.
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        hosting.cacheDisplay(
            in: hosting.bounds,
            to: try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        )
        window.orderOut(nil)

        var textFields: [NSTextField] = []
        func walk(_ view: NSView) {
            if let field = view as? NSTextField {
                textFields.append(field)
            }
            for child in view.subviews { walk(child) }
        }
        walk(hosting)
        return Fields(allTextFields: textFields)
    }
}
