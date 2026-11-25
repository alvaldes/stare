import AppKit
import SwiftUI
import XCTest

@testable import Stare
import StareCore

/// The prefix rule (S4 follow-up, option A — destination-independent): the
/// Name prefix field is enabled exactly when the name template is empty.
/// While a template is set the template builds the WHOLE file name, so the
/// prefix stands down wherever the capture goes — clipboard or folder — and
/// no control in the pane is silently dead: the control that governs is the
/// one that looks alive. Clearing the template brings the prefix back with
/// the legacy prefix name. Rendered through
/// `SettingsView.pane(for: .capture, …)` into a real window, the way the
/// neighbouring Settings render tests do; the prefix is identified by its
/// bound on-screen string ("Shots"), never by tree order. The name the
/// pane's own text promises is read through the very call the pane's preview
/// row makes (`CaptureEditorCanvas.savePanelFileName`) against the same
/// model capture, at a fixed instant — SwiftUI `Text` is not an
/// `NSTextField` in the hosting tree, so the displayed string cannot be
/// walked, but the value is exactly what the pane renders.
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

    // MARK: - The rule

    func testTemplateSetDisablesThePrefixForEachDestinationAndTheTemplateNamesTheFile() throws {
        for destination in [CaptureDestination.clipboard, .folder(path: "~/Pictures/Stare")] {
            let pane = try Self.read(destination: destination, template: "{date}")
            XCTAssertFalse(
                pane.prefix.isEnabled,
                "\(Self.label(for: destination)): with a template set it builds the whole file name, so the prefix stands down wherever the capture goes"
            )
            XCTAssertEqual(
                CaptureEditorCanvas.savePanelFileName(
                    preference: pane.capture, at: Self.sample, calendar: Self.calendar
                ),
                "2026-11-21.png",
                "\(Self.label(for: destination)): the pane's own text promises the template's name — the prefix never touches it while the template is set"
            )
        }
    }

    func testTemplateEmptyEnablesThePrefixForEachDestinationAndThePrefixNamesTheFile() throws {
        for destination in [CaptureDestination.clipboard, .folder(path: "~/Pictures/Stare")] {
            let pane = try Self.read(destination: destination, template: "")
            XCTAssertTrue(
                pane.prefix.isEnabled,
                "\(Self.label(for: destination)): with the template cleared the legacy prefix name governs again, so the prefix is editable wherever the capture goes"
            )
            XCTAssertEqual(
                CaptureEditorCanvas.savePanelFileName(
                    preference: pane.capture, at: Self.sample, calendar: Self.calendar
                ),
                "Shots-2026-11-21-at-14-05-33.png",
                "\(Self.label(for: destination)): the pane's own text promises the prefix's name — exactly what the prefix edits while the template is empty"
            )
        }
    }

    // MARK: - The render the assertions read

    private struct Fields {
        let prefix: NSTextField
        /// The capture the rendered pane was built from, so the test computes
        /// the promised name through the pane's own preview call.
        let capture: CapturePreference
    }

    private static func label(for destination: CaptureDestination) -> String {
        if case .folder = destination { return "folder" }
        return "clipboard"
    }

    /// The capture pane rendered offscreen at the given destination and
    /// template, its prefix field located by its on-screen string.
    private static func read(destination: CaptureDestination, template: String) throws -> Fields {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.capture = CapturePreference(
            format: .png,
            destination: destination,
            fileNamePrefix: "Stare"
        )
        // The prefix is bound to "Shots": the field must be found by content
        // on screen, not by tree order ("Stare" stays the fallback prefix in
        // the same blob, so a lookup by "Shots" proves it is the row's field).
        model.capture.fileNamePrefix = "Shots"
        model.capture.fileNameTemplate = template

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

        let named = Dictionary(grouping: textFields, by: { $0.stringValue })
        let prefix = try XCTUnwrap(named["Shots"]?.first, "the prefix field must render its bound string")
        return Fields(prefix: prefix, capture: model.capture)
    }
}
