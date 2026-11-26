import AppKit
import ImageIO
import XCTest

@testable import Stare
import StareCore

/// Round four S6: "el editor debe mostrarse en el dock como una app mas
/// porque sino se queda la ventana abirta y se puede perder. Ademas si se
/// abre desde finder una imagen debe salir la opcion de abrir con stare y
/// abra el editor". Three halves:
/// - the Dock policy: while an editor window exists the app answers as a
///   regular app; with the last editor closing it returns to the accessory
///   menu-bar app it always was;
/// - the open route: a file Finder hands Stare lands in the editor through
///   the ONE `openCaptureEditor` handoff (the one the capture cards and the
///   session history share);
/// - the document types: the bundled Info.plist declares the common image
///   types, so Finder's "Open With" offers Stare without stealing anyone's
///   default.
/// The owner's eye remains the proof the last half-cent closes: the Dock
/// icon's real visibility and the Finder menu cannot be driven headlessly.
@MainActor
final class CaptureEditorDockTests: XCTestCase {
    private var temporaryDirectory: URL = URL(fileURLWithPath: "")

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stare-editor-dock-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    private func solid(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func write(_ file: Data, named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try file.write(to: url)
        return url
    }

    // MARK: - The Dock policy

    /// The rule as a value: no editor, the accessory menu-bar app; any
    /// editor, a regular Dock app.
    func testTheDockPolicyRuleAnswersByTheEditorCount() {
        XCTAssertEqual(
            CaptureEditorController.dockActivationPolicy(forEditorCount: 0), .accessory,
            "no editor on screen: the accessory menu-bar app Stare has always been")
        XCTAssertEqual(
            CaptureEditorController.dockActivationPolicy(forEditorCount: 1), .regular,
            "one editor on screen: in the Dock like another app")
        XCTAssertEqual(
            CaptureEditorController.dockActivationPolicy(forEditorCount: 3), .regular,
            "several editors, one Dock presence — back to accessory only when the LAST closes")
    }

    /// The runtime half, driven through the REAL editor open path: opening
    /// the editor flips the live app to regular, and the last window's close
    /// returns it to accessory.
    func testOpeningAnEditorPutsStareInTheDockAndTheLastClosingTakesItBack() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no display: an editor window cannot be opened")
        _ = NSApplication.shared
        let previous = NSApp.activationPolicy()
        defer { NSApp.setActivationPolicy(previous) }
        NSApp.setActivationPolicy(.accessory)
        let controller = CaptureEditorController()
        defer {
            for window in controller.windowsForTesting {
                window.orderOut(nil)
                window.close()
            }
        }

        controller.open(image: solid(20, 10))

        XCTAssertEqual(NSApp.activationPolicy(), .regular, "the editor window is on screen, so the Dock shows Stare")

        // Two editors, closing one: the presence stands at the first close.
        controller.open(image: solid(30, 10))
        XCTAssertEqual(controller.windowsForTesting.count, 2)
        controller.windowsForTesting[0].close()
        XCTAssertEqual(NSApp.activationPolicy(), .regular, "the last editor closing is the only return to accessory")

        controller.windowsForTesting.first?.close()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory, "the last editor closing returns the accessory contract")
    }

    // MARK: - The open route (the "Open With" half)

    /// A file the system asked Stare to open becomes an editor handoff —
    /// the ONE `openCaptureEditor` the cards and the history share. Driven
    /// through the route seam with a witnessing handoff, so the route's
    /// cargo (the file's own pixels) is asserted without a window.
    func testAFinderImageOpenLandsInTheEditorThroughTheOneHandoff() throws {
        let image = solid(10, 8)
        let url = try write(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!,
            named: "opened.png")
        var handed: [CGImage] = []
        let controller = OverlayController(editorHandoff: { image, _ in handed.append(image) })

        let opened = controller.openFileInEditor(at: url)

        XCTAssertTrue(opened, "an image file decodes and takes the handoff")
        XCTAssertEqual(handed.count, 1, "one file, ONE editor handoff")
        XCTAssertEqual(handed.first?.width, 10, "the file's own pixels travel")
        XCTAssertEqual(handed.first?.height, 8)
    }

    /// A file that is not an image changes nothing: no refusal artefact, no
    /// handoff of a half-decoded blob.
    func testANonImageOpenRefusesTheHandoff() throws {
        let url = try write(Data("not an image".utf8), named: "opened.txt")
        var handed: [CGImage] = []
        let controller = OverlayController(editorHandoff: { image, _ in handed.append(image) })

        let opened = controller.openFileInEditor(at: url)

        XCTAssertFalse(opened)
        XCTAssertEqual(handed.count, 0, "no handoff for a file that is not an image")
    }

    /// The whole real route: a file lands in the editor (the default
    /// non-injected handoff opens the real window) AND the Dock policy flips
    /// with the editor's presence — one route, both S6 halves.
    func testTheRealRouteOpensTheEditorAndRaisesTheDockPresence() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no display: the editor window cannot be opened")
        _ = NSApplication.shared
        let previous = NSApp.activationPolicy()
        defer { NSApp.setActivationPolicy(previous) }
        NSApp.setActivationPolicy(.accessory)
        let controller = OverlayController(captureService: CaptureService())

        let url = try write(
            NSBitmapImageRep(cgImage: solid(10, 8)).representation(using: .png, properties: [:])!,
            named: "opened.png")
        let opened = controller.openFileInEditor(at: url)

        XCTAssertTrue(opened)
        XCTAssertEqual(controller.editorWindowsForTesting.count, 1, "the file's editor opened")
        let content = try XCTUnwrap(
            controller.editorWindowsForTesting.first?.contentView as? CaptureEditorContent,
            "the editor window hosts the editor content")
        XCTAssertEqual(content.canvas.image.width, 10, "the file's pixels are what the editor edits")
        XCTAssertEqual(content.canvas.image.height, 8)
        XCTAssertEqual(NSApp.activationPolicy(), .regular, "the file's editor is on screen: the Dock shows Stare")

        controller.editorWindowsForTesting.first?.close()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory, "the editor's close returns the accessory contract")
        for window in controller.editorWindowsForTesting { window.orderOut(nil) }
    }

    // MARK: - The document types (the bundled Info.plist)

    private static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url
    }()

    /// Finder's "Open With Stare" needs the bundle to declare the image
    /// types. The declared ones are common images claimed as an EDITOR-able
    /// handler at rank Alternate — offered in Finder's Open With, never
    /// stealing another app's default. The launch contract (LSUIElement, the
    /// accessory menu-bar app) is untouched: the Dock presence is the
    /// editor's runtime flip above, not a launch-wide regular app.
    func testTheBundledInfoPlistDeclaresTheCommonImageDocumentTypes() throws {
        let plistURL = Self.repoRoot.appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any])
        let types = try XCTUnwrap(
            plist["CFBundleDocumentTypes"] as? [[String: Any]],
            "the bundle must declare the document types the Finder half needs")
        for type in types {
            XCTAssertEqual(type["CFBundleTypeRole"] as? String, "Editor")
            XCTAssertEqual(type["LSHandlerRank"] as? String, "Alternate", "offered, never the default thief")
        }
        let claimed = Set(types.flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] })
        for required in ["public.png", "public.jpeg", "com.compuserve.gif", "public.tiff"] {
            XCTAssertTrue(claimed.contains(required), "Finder's Open With must offer Stare for \(required)")
        }
        // The launch contract stays untouched.
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true, "Stare launches as the accessory menu-bar app, as always")
    }

    /// Canary: the system's open-files event must be a declared delegate
    /// route in the app delegate, and it must land through the open route
    /// above — the bridge that makes Finder's choice reach the editor.
    func testTheAppDelegateBridgesTheSystemsOpenFilesIntoTheEditor() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("Sources/Stare/AppDelegate.swift"),
            encoding: .utf8)
        XCTAssertTrue(
            source.contains("func application(_ application: NSApplication, openFiles filenames: [String])"),
            "the system's open-files event is the declared delegate route")
        XCTAssertTrue(source.contains("openFileInEditor"), "the bridge lands the file through the ONE editor handoff")
    }
}
