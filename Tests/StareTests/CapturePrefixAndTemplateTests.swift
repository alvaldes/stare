import AppKit
import SwiftUI
import XCTest

@testable import Stare
import StareCore

/// S4 RE-DERIVED from the D4 naming pins: the Name prefix row is gone — the
/// template supersedes it, and a control the template always overrides has
/// no business in the pane — but the stored prefix keeps working EXACTLY as
/// it does today when the template is empty: that is the fallback path, a
/// user who clears the template still gets a name, and the pane keeps
/// saying what name will be written in both states through the very call
/// the save panel makes (`CaptureEditorCanvas.savePanelFileName`) against
/// the same model capture, at a fixed instant — SwiftUI `Text` is not an
/// `NSTextField` in the hosting tree, so the displayed string cannot be
/// walked, but the value is exactly what the pane renders. Rendered into a
/// real window, the way the neighbouring Settings render tests do; the
/// prefix's absence is asserted through its bound canary string ("Shots"),
/// never by tree order. Also S4's leftover from the earlier unit: switching
/// to the folder destination must prefill the folder a fresh install really
/// writes into, never the `~/Documents` a previous build shipped.
@MainActor
final class CapturePrefixAndTemplateTests: XCTestCase {

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
    /// promised names are pinned exactly and nothing is injected from the
    /// environment.
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

    // MARK: - The rule, re-derived for the row's removal (S4)

    func testTemplateSetNamesTheFileForEachDestinationAndThePrefixRowIsGone() throws {
        for destination in [CaptureDestination.clipboard, .folder(path: "~/Pictures/Stare")] {
            let pane = try Self.render(model: Self.model(destination: destination), template: "{date}")
            XCTAssertEqual(
                CaptureEditorCanvas.savePanelFileName(
                    preference: pane.model.capture, at: Self.sample, calendar: Self.calendar
                ),
                "2026-11-21.png",
                "\(Self.label(for: destination)): the pane's text promises the template's name — the prefix never touches it while the template is set"
            )
            XCTAssertFalse(
                pane.fields.hasPrefixRow,
                "S4: with a template set nothing may still be the prefix row — a control the template always overrides is gone from the pane"
            )
        }
    }

    func testTemplateEmptyHandsTheNameBackToTheStoredPrefixForEachDestination() throws {
        for destination in [CaptureDestination.clipboard, .folder(path: "~/Pictures/Stare")] {
            let pane = try Self.render(model: Self.model(destination: destination), template: "")
            XCTAssertEqual(
                CaptureEditorCanvas.savePanelFileName(
                    preference: pane.model.capture, at: Self.sample, calendar: Self.calendar
                ),
                "Shots-2026-11-21-at-14-05-33.png",
                "\(Self.label(for: destination)): the stored prefix keeps working exactly as it does today when the template is empty — that is the fallback path, and a user who clears the template still gets a name the pane states (S4)"
            )
            XCTAssertFalse(
                pane.fields.hasPrefixRow,
                "S4: the fallback needs no row to be real — the chain's source names the prefix, the stored value keeps naming"
            )
        }
    }

    // MARK: - The render the assertions read

    private struct Fields {
        /// Every text field in the hosting tree, in walk order.
        let allTextFields: [NSTextField]
        /// The prefix row's canary string is gone from the render (S4);
        /// read as a property so every state test pin asserts it the same
        /// way, by content never by tree order.
        var hasPrefixRow: Bool {
            allTextFields.contains { $0.stringValue == "Shots" }
        }
    }

    private struct Rendered {
        let pane: CapturePane
        let model: PreferencesModel
        let fields: Fields
    }

    private static func label(for destination: CaptureDestination) -> String {
        if case .folder = destination { return "folder" }
        return "clipboard"
    }

    private static func model(destination: CaptureDestination) -> PreferencesModel {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.capture = CapturePreference(
            format: .png,
            destination: destination,
            fileNamePrefix: "Stare"
        )
        // The prefix canary ("Shots"): bound into the blob so its ABSENCE
        // from the render proves the row's removal (the template canary is
        // whatever `template` the caller binds).
        model.capture.fileNamePrefix = "Shots"
        return model
    }

    private static func render(model: PreferencesModel, template: String) throws -> Rendered {
        // The template canary is bound by content, never by tree order.
        model.capture.fileNameTemplate = template

        let permission = PermissionProbe(
            permission: ScreenRecordingPermission(client: StubScreenRecordingClient())
        )
        let pane = CapturePane(model: model, cardsWidth: 766)
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

        return Rendered(pane: pane, model: model, fields: Fields(allTextFields: textFields))
    }

    // MARK: - The folder prefill's own render (S4 leftover)

    func testSwitchingToAFolderPrefillsTheFolderAFreshInstallActuallyWritesInto() throws {
        let model = Self.model(destination: .clipboard)
        let rendered = try Self.render(model: model, template: "{date}")
        let request = rendered.pane.destinationSelection
        request.wrappedValue = 1
        XCTAssertEqual(
            model.capture.destination,
            .folder(path: CapturePreference.defaultDestinationFolder),
            "S4 leftover: the folder copy must not contradict the default — a fresh install writes into \(CapturePreference.defaultDestinationFolder)"
        )
    }
}
