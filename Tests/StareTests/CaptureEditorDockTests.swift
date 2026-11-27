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

    /// The process state before the class ran, restored in teardown (the
    /// shared `LeaveAsFound` hooks): the Dock tests flip the activation
    /// policy repeatedly and open real user-facing windows, and a policy
    /// cycle left standing has poisoned the LATER classes' keying in a wider
    /// run before (round four S7 follow-ups, the same AppKit family the
    /// census runtime test below turns into a red composition).
    private var foundState: LeaveAsFound.State!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stare-editor-dock-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        foundState = LeaveAsFound.capture()
    }

    override func tearDown() {
        LeaveAsFound.restore(foundState)
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

    /// Round four S10 test fixtures: an in-memory preference store and a
    /// stubbed permission client, so a real `SettingsWindowController` rides
    /// the census tests without touching stored state or a system prompt.
    private final class InMemoryPreferenceStore: PreferenceStore {
        private var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    private struct StubPermissionClient: ScreenRecordingClient {
        func preflight() -> Bool { true }
        func request() -> Bool { true }
        func canCapture() -> Bool { true }
        func openPrivacySettings() {}
    }

    private func makeSettingsController() -> SettingsWindowController {
        SettingsWindowController(
            model: PreferencesModel(store: InMemoryPreferenceStore()),
            permission: ScreenRecordingPermission(client: StubPermissionClient())
        )
    }

    /// The controller's own window, located by the title constant — the one
    /// the capture filter keys on (the SettingsShortcutTests locator).
    private func settingsWindow() throws -> NSWindow {
        try XCTUnwrap(
            NSApp.windows.first { $0.title == ScreenContent.settingsWindowTitle },
            "the settings controller must have shown its window")
    }

    /// The rule as a value (S10, re-derived from S6 — the re-derivation's
    /// own canary: the census is now the app's user-facing windows open,
    /// WHATEVER kind they are, one number decided once): no windows, the
    /// accessory menu-bar app; any one window open — editor or Settings — a
    /// regular Dock app; back to accessory only when the LAST of all closes.
    func testTheDockPolicyRuleAnswersByTheUserWindowCount() {
        XCTAssertEqual(
            CaptureEditorController.dockActivationPolicy(forUserWindowCount: 0), .accessory,
            "S10: no user-facing window on screen — the accessory menu-bar app Stare has always been")
        XCTAssertEqual(
            CaptureEditorController.dockActivationPolicy(forUserWindowCount: 1), .regular,
            "S10: one user-facing window on screen — editor OR Settings — in the Dock like another app")
        XCTAssertEqual(
            CaptureEditorController.dockActivationPolicy(forUserWindowCount: 2), .regular,
            "S10: editor AND Settings open — one count, one Dock presence, not two rules that fight")
        XCTAssertEqual(
            CaptureEditorController.dockActivationPolicy(forUserWindowCount: 3), .regular,
            "S10: several user-facing windows, one Dock presence — back to accessory only when the LAST closes")
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

    /// The runtime half (S10), driven through the REAL census both window
    /// kinds ride, wired the way the app delegate wires it: no windows →
    /// accessory; the editor alone → regular (S6 kept); the Settings window
    /// joins, both open → regular; closing ONE of the two leaves the app
    /// regular; the Settings window alone keeps it regular; the last of all
    /// closing returns the accessory contract. One census, whatever kind the
    /// windows are — the owner's second report: "settings tambien tiene que
    /// tener icono en el dock como el editor".
    func testTheDockCensusCountsEditorsAndSettingsWindowsWhateverKind() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no display: a user-facing window cannot be opened")
        _ = NSApplication.shared
        let previous = NSApp.activationPolicy()
        defer { NSApp.setActivationPolicy(previous) }
        NSApp.setActivationPolicy(.accessory)

        let editorController = CaptureEditorController()
        defer {
            for window in editorController.windowsForTesting {
                window.orderOut(nil)
                window.close()
            }
        }
        let settings = self.makeSettingsController()
        // The app delegate's wiring (S10): the census is ONE number — the
        // editor's windows PLUS the Settings window's 0/1 — and both sides'
        // open/close re-run the ONE reflection.
        editorController.otherUserWindowCount = { settings.isWindowOpen ? 1 : 0 }
        settings.dockPresenceDidChange = { editorController.refreshDockPresence() }

        // No windows.
        XCTAssertEqual(NSApp.activationPolicy(), .accessory, "S10: nothing of the app's user-facing windows open — the accessory contract stands")

        // Editor only (S6 kept).
        editorController.open(image: solid(20, 10))
        XCTAssertEqual(NSApp.activationPolicy(), .regular, "S10: the editor alone keeps the app in the Dock, exactly as round four S6 built")

        // Both: the Settings window joins the SAME ONE count.
        settings.show(aboveOverlay: false)
        let window = try self.settingsWindow()
        XCTAssertEqual(NSApp.activationPolicy(), .regular, "S10: the Settings window open — editor AND Settings — the one census answers regular")
        XCTAssertTrue(settings.isWindowOpen, "S10: the Settings window's 0/1 rides the census")

        // Closing ONE of two: the app stays regular.
        editorController.windowsForTesting.first?.close()
        XCTAssertEqual(NSApp.activationPolicy(), .regular, "S10: closing ONE of two user-facing windows (the editor) leaves the app regular")

        // Settings only now — the second reported half.
        XCTAssertTrue(editorController.windowsForTesting.isEmpty)
        XCTAssertEqual(NSApp.activationPolicy(), .regular, "S10: the Settings window ALONE keeps the app in the Dock, like the editor does")

        // The last of all closing: the accessory contract returns. The
        // window is released with its close, so the run leaves no standing
        // "Stare Settings" window behind for the classes that share this
        // process — a closed one still listed in `NSApp.windows` would be
        // the one their title locator finds first.
        window.isReleasedWhenClosed = true
        window.close()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory, "S10: the last user-facing window closing — editor, Settings, or both — returns the accessory contract")
    }

    /// Canary (S10): the app delegate is the owner that sees BOTH
    /// user-facing window kinds, so it is the one that must feed the
    /// Settings window's 0/1 into the ONE census and re-run the ONE
    /// reflection when the Settings window opens or closes — otherwise
    /// Settings alone would never reach the Dock.
    func testTheAppDelegateWiresTheSettingsWindowIntoTheOneDockCensus() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("Sources/Stare/AppDelegate.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("setDockCensusOfOtherUserWindows"), "S10: the app delegate feeds the Settings window's 0/1 into the ONE census")
        XCTAssertTrue(source.contains("dockPresenceDidChange"), "S10: the Settings window's open/close re-runs the ONE reflection")
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
