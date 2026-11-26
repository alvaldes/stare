import AppKit
import CoreGraphics
import XCTest

@testable import Stare
import StareCore

/// The preview and the save panel are one answer (S4, and S5 makes it true
/// for {app}/{display}): every rendered name — the Settings chain's, the
/// capture editor's save panel's default field — comes from the ONE
/// `CaptureEditorCanvas.savePanelFileName` call, so a template is never
/// previewed under one name and saved under another. What S5 changed: the
/// capture's app and display are threaded through the editor handoff from
/// the ONE resolution the capture tail keeps (`OverlayController`'s
/// identity ledger, resolved at `deliver` exactly where the folder save
/// resolves them), so a capture the handoff knows is previewed with its
/// REAL app and display and written under that same name; an identity no
/// capture exists for — this editor's own composed variant, a capture
/// evicted from the bounded ledger or reopened from a previous session —
/// is none on BOTH paths, and the tokens refuse into the prefix-name
/// fallback the Settings preview documents, never a silent mismatch.
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

    /// A small premultiplied image, the way the editor tests build theirs.
    private static func solid(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func preferenceWith(_ template: String, prefix: String = "Stare") -> CapturePreference {
        var preference = CapturePreference(format: .png, destination: .clipboard, fileNamePrefix: prefix)
        preference.fileNameTemplate = template
        return preference
    }

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
        // An `{app}` template with NO captured identity — this editor's own
        // composed variant, or a capture the ledger never held — refuses the
        // token and degrades to the prefix name instead of writing a hole or
        // a guess into the file name (the unknown-identity half of S5: both
        // paths agree on the same value by arriving at the same none).
        preference.fileNameTemplate = "{app}"
        XCTAssertEqual(
            CaptureEditorCanvas.savePanelFileName(preference: preference, at: sample, calendar: calendar),
            "Stare-2026-11-21-at-14-05-33.png"
        )
    }

    // MARK: The seam is ONE call, values included (S5)

    func testPreviewAndSavePanelAreTheSameCallWithTheSameInputs() {
        // Whichever way the template or the identity changes, the editor's
        // save-panel name and the preview name are produced by the same call
        // with the same inputs: the identity the capture tail resolved, or
        // none — the call itself cannot disagree (S5, "both come from one
        // place").
        let identities: [(app: String?, displayName: String?)] = [
            (nil, nil), ("Finder", "Desk"), ("Xcode", nil),
        ]
        let templates = ["", "{date}", "{date}-at-{time}", "{app}", "{app}-{display}", "{date}_{time}_{app}_{display}"]
        for template in templates {
            for identity in identities {
                let preference = preferenceWith(template)
                XCTAssertEqual(
                    CaptureEditorCanvas.savePanelFileName(
                        preference: preference, at: sample, calendar: calendar,
                        app: identity.app, displayName: identity.displayName
                    ),
                    preference.fileName(
                        at: sample, calendar: calendar,
                        app: identity.app, display: identity.displayName
                    ),
                    "template '\(template)' with app \(String(describing: identity.app)) and display \(String(describing: identity.displayName)): the panel and the written name must be one call with the same values"
                )
            }
        }
    }

    // MARK: S5 — the threaded identity renders the REAL values

    /// The truth S5 asks for: with the identity threaded through the editor
    /// handoff, an `{app}` template previews the captured app's name and an
    /// `{display}` template the captured display's — real values, never the
    /// fallback — and the save-panel name is identical for the same inputs,
    /// which is the name the write under the panel's writing rule carries.
    @MainActor
    func testThreadedIdentityPreviewsTheCapturedAppAndDisplayName() {
        // {app}: the captured app's name, exactly as the capture tail
        // resolved it at delivery (`CaptureAppIdentity`'s resolution).
        var preference = preferenceWith("{app}", prefix: "Shots")
        XCTAssertEqual(
            CaptureEditorCanvas.savePanelFileName(
                preference: preference, at: sample, calendar: calendar, app: "Finder", displayName: "Desk"
            ),
            "Finder.png",
            "an {app} template with the captured identity previews the captured app's own name, never the fallback"
        )
        // {display}: the captured display's name, same rule.
        preference.fileNameTemplate = "{display}"
        XCTAssertEqual(
            CaptureEditorCanvas.savePanelFileName(
                preference: preference, at: sample, calendar: calendar, app: "Finder", displayName: "Desk"
            ),
            "Desk.png",
            "a {display} template with the captured identity previews the captured display's own name, never the fallback"
        )
        // The fallback must stay the fallback when the identity is real but
        // the template is empty: the stored prefix keeps working exactly as
        // it does today (S4's preserved fallback path).
        preference.fileNameTemplate = ""
        XCTAssertEqual(
            CaptureEditorCanvas.savePanelFileName(
                preference: preference, at: sample, calendar: calendar, app: "Finder", displayName: "Desk"
            ),
            "Shots-2026-11-21-at-14-05-33.png",
            "an empty template ignores the identity entirely — the legacy prefix name, byte for byte"
        )
    }

    /// The handoff's cargo: the identity travels CaptureEditorController →
    /// CaptureEditorWindow → CaptureEditorContent → the canvas's ONE naming
    /// context, and the save panel's default name is rendered from THAT —
    /// never from a second value any step could rewrite (S5's one place).
    @MainActor
    func testTheHandoffThreadsTheIdentityIntoTheEditorsNamingContext() throws {
        let content = CaptureEditorContent(
            image: Self.solid(40, 20), capture: .standard, redactionStyle: .blur,
            app: "Finder", displayName: "Desk"
        )
        XCTAssertEqual(
            content.canvas.fileNameContext, CaptureEditorIdentity(app: "Finder", displayName: "Desk"),
            "the threaded identity is the canvas's one naming context — the same values the folder save wrote with"
        )
        // And a handoff with nothing to say names nothing: the identity-less
        // opening leaves the context none, so the tokens refuse exactly as
        // the fallback contract says both paths agree on.
        let withoutIdentity = CaptureEditorContent(
            image: Self.solid(40, 21), capture: .standard, redactionStyle: .blur
        )
        XCTAssertEqual(
            withoutIdentity.canvas.fileNameContext, CaptureEditorIdentity.unknown,
            "no identity in the handoff is none in the context — both paths agree on the same none"
        )
    }

    /// The controller-level half of the thread: opening the editor through
    /// the real `CaptureEditorController.open` carries the identity into the
    /// window it opens, so the panel the user actually meets is rendered
    /// from the values the handoff carried.
    @MainActor
    func testTheEditorControllerThreadsTheIdentityThroughItsWindow() throws {
        try? XCTSkipIf(NSScreen.screens.isEmpty, "no screen: a window cannot be ordered on screen")
        let controller = CaptureEditorController()
        controller.open(
            image: Self.solid(20, 10),
            capture: .standard,
            redactionStyle: .blur,
            app: "Figma",
            displayName: "StudioDisplay"
        )
        defer {
            for window in controller.windowsForTesting {
                window.orderOut(nil)
                window.close()
            }
        }
        let content = try XCTUnwrap(
            controller.windowsForTesting.first?.contentView as? CaptureEditorContent,
            "the window the controller opened must carry the editor content")
        XCTAssertEqual(
            content.canvas.fileNameContext, CaptureEditorIdentity(app: "Figma", displayName: "StudioDisplay"),
            "the controller-level handoff forwards the identity intact (S5)")
    }

    // MARK: S5 — the capture tail keeps the identity for the handoff

    /// `deliver` resolves {app}/{display} ONCE — exactly where the folder
    /// save resolves them — and registers the pair per capture image, so a
    /// later editor handoff (the card's click, the session history's
    /// reopen) names THAT capture truthfully even when nothing was written
    /// to a folder. The ledger is keyed by object identity (a pixel-equal
    /// but distinct capture inherits nothing), retains what it keys on and
    /// is bounded, so a long session grows it no further than its cap.
    @MainActor
    func testTheCaptureTailKeepsTheIdentityPerImageForTheEditorHandoff() {
        let controller = OverlayController(
            captureService: CaptureService(), editorHandoff: { _, _ in })
        let first = Self.solid(8, 8)
        let second = Self.solid(8, 9)
        controller.registerCaptureIdentity(first, CaptureEditorIdentity(app: "Finder", displayName: "Desk"))
        controller.registerCaptureIdentity(second, CaptureEditorIdentity(app: "Xcode", displayName: nil))

        XCTAssertEqual(
            controller.editorIdentity(for: first), CaptureEditorIdentity(app: "Finder", displayName: "Desk"),
            "the handoff reads back the resolution the capture tail made for this capture")
        XCTAssertEqual(
            controller.editorIdentity(for: second), CaptureEditorIdentity(app: "Xcode", displayName: nil),
            "each capture keeps its own identity, never the last one's")
        XCTAssertEqual(
            controller.editorIdentity(for: Self.solid(8, 8)), CaptureEditorIdentity.unknown,
            "a pixel-equal but DISTINCT capture inherits nothing — the identity is the object's, never a guess")
        XCTAssertEqual(
            controller.editorIdentity(for: Self.solid(9, 9)), CaptureEditorIdentity.unknown,
            "an image the delivery never resolved observes none — the same none both paths agree on")

        // Bounded: registering beyond the cap evicts the oldest entries, so
        // the ledger can never outgrow the session history that already
        // holds these images.
        var newest: CGImage?
        for index in 0..<(OverlayController.identityLedgerLimit * 2) {
            let image = Self.solid(2, index + 1)
            newest = image
            controller.registerCaptureIdentity(
                image, CaptureEditorIdentity(app: "Evicted\(index)", displayName: nil))
        }
        XCTAssertEqual(
            controller.editorIdentity(for: first), CaptureEditorIdentity.unknown,
            "the oldest capture's identity is evicted once the ledger is full — falling back to the refused tokens, never to a stale name")
        XCTAssertEqual(
            controller.editorIdentity(for: try XCTUnwrap(newest)),
            CaptureEditorIdentity(app: "Evicted\(OverlayController.identityLedgerLimit * 2 - 1)", displayName: nil),
            "the newest capture's identity is still kept — the same object the tail registered, looked up as the handoff does")
    }
}
