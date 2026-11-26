import AppKit
import SwiftUI
import XCTest

@testable import Stare
import StareCore

/// Finding R3-clipboard-template-editable: the file-name template field is
/// disabled while the capture goes to the clipboard — templates apply to
/// folder saves only, so an editable control there is silently inert — and
/// enabled when the destination is a folder, exactly like its neighbouring
/// backdrop fields. Rendered through `SettingsView.pane(for: .capture, …)`,
/// the same entry the bar-preview probe uses, into a real window; each field
/// is identified by its on-screen string (the fixture binds a canary into
/// the prefix and the template), so no view-tree ordering is assumed. S4
/// re-derived the prefix row's pins: the Name prefix row is gone, so the
/// suite pins that absence by its canary string and no longer pins a
/// disabled rule for a control that no longer exists — the fallback's
/// truth lives in `CapturePrefixAndTemplateTests`.
@MainActor
final class SettingsCapturePaneDisabledStateTests: XCTestCase {

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

    // MARK: - The assertions

    func testClipboardDisablesTheTemplateFieldAndTheBackdropFields() throws {
        let pane = try Self.read(destination: .clipboard)
        XCTAssertEqual(
            pane.template.isEnabled, false,
            "the template field must be disabled on the clipboard destination — templates apply to folder saves only"
        )
        XCTAssertEqual(pane.template.stringValue, "{date}",
            "the disabled field must be the template one, identified by its bound canary, never by tree order")
        XCTAssertTrue(
            pane.backdropFields.allSatisfy { !$0.isEnabled },
            "the adjacent backdrop fields share the same condition and are disabled with it"
        )
        XCTAssertFalse(
            pane.hasPrefixRow,
            "S4: the Name prefix row is gone on the clipboard too — the pane carries no control the template always overrides"
        )
        XCTAssertFalse(
            pane.hasChainNameField,
            "S4: the chain's rendered name is a static text, never an editable field, in the template-governs state"
        )
    }

    func testFolderDestinationEnablesTheTemplateFieldAndTheBackdropFields() throws {
        let pane = try Self.read(destination: .folder(path: "~/Pictures/Stare"))
        XCTAssertEqual(
            pane.template.isEnabled, true,
            "the template field is editable where the template is actually used"
        )
        XCTAssertEqual(pane.template.stringValue, "{date}",
            "the enabled field must be the template one, identified by its bound canary, never by tree order")
        XCTAssertTrue(
            pane.backdropFields.allSatisfy(\.isEnabled),
            "the adjacent backdrop fields share the same condition and are enabled with it"
        )
        XCTAssertFalse(
            pane.hasPrefixRow,
            "S4: the Name prefix row is gone on the folder destination too — its disabled-while-a-template-governs rule retired with the row"
        )
        XCTAssertFalse(
            pane.hasChainNameField,
            "S4: the chain's rendered name is a static text, never an editable field, in the template-governs state"
        )
    }

    // MARK: - The render the assertions read

    /// What the capture pane's controls look like at one destination: the
    /// template field (named by its on-screen string), the two unnamed
    /// backdrop fields, and the absences S4 makes true — no prefix row and
    /// no editable name field for the chain.
    struct Fields {
        let template: NSTextField
        /// The padding and radius fields — same condition, unnamed.
        let backdropFields: [NSTextField]
        let hasPrefixRow: Bool
        let hasChainNameField: Bool
    }

    /// The capture pane rendered offscreen at the given destination, its text
    /// fields located by their on-screen strings, the shadow switch by its
    /// control type.
    static func read(destination: CaptureDestination) throws -> Fields {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.capture = CapturePreference(
            format: .png,
            destination: destination,
            fileNamePrefix: "Stare"
        )
        // Canaries: the template field must be told apart from its
        // same-width prefix neighbour by content, not by tree order.
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

        let named = Dictionary(grouping: textFields, by: { $0.stringValue })
        let template = try XCTUnwrap(named["{date}"]?.first, "the template field must render its bound string")
        let backdrops = textFields.filter { $0 !== template }
        XCTAssertEqual(
            backdrops.count, 2,
            "the pane carries exactly the padding and radius fields beyond the template — S4: the prefix row is gone, so no third unnamed name field exists"
        )
        // The adjacent backdrop fields share the destination condition; their
        // enabled states are what the assertions above compare. The shadow
        // toggle needs no separate identity here: the fixture's job is the
        // template field, and the two backdrop text fields carry the shared
        // condition already.
        return Fields(
            template: template,
            backdropFields: backdrops,
            hasPrefixRow: named.contains(where: { $0.key == "Shots" }),
            hasChainNameField: named.contains(where: { $0.key == "2026-11-21.png" })
        )
    }
}
