import AppKit
import XCTest

@testable import Stare
import StareCore

/// S7 (round three): "Si tengo abierto cualquier modo, ya sea dibujo, pizarra,
/// historial y presiono la combinación command+, debería abrir settings que
/// hoy no lo hace".
///
/// The recorded cause, re-derived: Stare is an `.accessory` app, so it ships
/// without a standard AppKit main menu at all — and ⌘, is delivered through
/// the main menu's key equivalents. With no menu, the keystroke died in every
/// mode that held the keyboard: a drawing session, the board, the history
/// sheet. The app menu now carries `Settings…` with ⌘, routed through the ONE
/// open path the status bar and the setup guide already share, and the open
/// lifts the window above the app's own overlay surfaces while a mode holds
/// the screen — at its normal level the window would sit behind the
/// `.screenSaver` panels and the shortcut would still look dead.
///
/// The honest limit, recorded here rather than hidden: a global registration
/// of ⌘, (a Carbon/CGEvent hotkey) would take the keystroke away from every
/// other app in the system, so ⌘, reaches Settings exactly when Stare is the
/// active app — which a screen-holding mode always makes it (the modes call
/// `NSApp.activate`; the history sheet also does). When NOTHING is open Stare
/// is background, and the reachable route into Settings is the status-bar
/// menu, which already carries `Settings…`. These tests drive
/// `NSMenu.performKeyEquivalent` — the dispatch `NSApplication` itself uses
/// for key equivalents — in each of the four states, because the dispatch is
/// not gated on any window or mode: it is the app-wide menu route.
@MainActor
final class SettingsShortcutTests: XCTestCase {

    private final class InMemoryPreferenceStore: PreferenceStore {
        private var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    private struct StubClient: ScreenRecordingClient {
        func preflight() -> Bool { true }
        func request() -> Bool { true }
        func canCapture() -> Bool { true }
        func openPrivacySettings() {}
    }

    /// A real ⌘, key event, the way the window server would synthesise it.
    private func commandComma() -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            characters: ",", charactersIgnoringModifiers: ",",
            isARepeat: false, keyCode: 43
        )!
    }

    private func makeSettingsController() -> SettingsWindowController {
        SettingsWindowController(
            model: PreferencesModel(store: InMemoryPreferenceStore()),
            permission: ScreenRecordingPermission(client: StubClient())
        )
    }

    private func controller() -> OverlayController {
        OverlayController(captureService: CaptureService(), editorHandoff: { _, _ in })
    }

    private final class OpensBox { var opens = 0 }

    /// The menu item holds its target weakly (NSMenuItem's contract), so the
    /// test retains it exactly the way the AppDelegate does — otherwise the
    /// target dies with the helper that created it and the dispatch reads a
    /// nil target.
    private var menuTarget: SettingsShortcutMenuTarget?

    private func makeMenuOpensInto(_ box: OpensBox) -> NSMenu {
        // xctest runs without an initialized NSApplication, so create it here
        // first — the same note the card-cursor tests make.
        _ = NSApplication.shared
        let target = SettingsShortcutMenuTarget { box.opens += 1 }
        self.menuTarget = target
        let menu = AppDelegate.makeMainMenu(openSettings: target)
        NSApp.mainMenu = menu
        return menu
    }

    override func tearDown() {
        NSApp.mainMenu = nil
        self.menuTarget = nil
        super.tearDown()
    }

    /// The controller's own window, located the way the sizing tests locate
    /// theirs — by the title constant, the one the capture filter keys on.
    private func settingsWindow() throws -> NSWindow {
        try XCTUnwrap(
            NSApp.windows.first { $0.title == ScreenContent.settingsWindowTitle },
            "the controller must have shown its window"
        )
    }

    // MARK: The item the whole app's keyboard goes through

    func testTheAppMenuCarriesSettingsOnCommandCommaAndDispatchesIntoTheOpenPath() throws {
        let box = OpensBox()
        _ = self.makeMenuOpensInto(box)

        let appMenu = try XCTUnwrap(NSApp.mainMenu?.items.first?.submenu, "the menu's first submenu is the app menu")
        let item = try XCTUnwrap(appMenu.items.first, "the app menu carries one item")
        XCTAssertEqual(item.title, "Settings…")
        XCTAssertEqual(item.keyEquivalent, ",")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command])
        XCTAssertTrue(item.target is SettingsShortcutMenuTarget, "the item routes to the one open path, not to nil-target validation")
        XCTAssertEqual(item.action, #selector(SettingsShortcutMenuTarget.openSettings(_:)))

        // The dispatch NSApplication runs for every key down before any
        // responder sees it — this is the exact step the drawing session's,
        // the board's and the history sheet's ⌘, all take.
        XCTAssertTrue(NSApp.mainMenu?.performKeyEquivalent(with: commandComma()) ?? false)
        XCTAssertEqual(box.opens, 1, "⌘, opened Settings")
    }

    // MARK: ⌘, from every mode

    /// The drawing session holds the keyboard and the screen; ⌘, opens
    /// Settings and the session is left as it stands — not silently cleared
    /// or disarmed.
    func testCommandCommaOpensSettingsWhileADrawingSessionIsOpen() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen in this environment")
        let box = OpensBox()
        _ = self.makeMenuOpensInto(box)
        let controller = self.controller()
        controller.activate()
        XCTAssertTrue(controller.isActive, "the drawing session has to be the one under test")
        defer { controller.deactivate() }

        XCTAssertTrue(NSApp.mainMenu?.performKeyEquivalent(with: commandComma()) ?? false, "round three S7: ⌘, must answer while a drawing session holds the keyboard")
        XCTAssertEqual(box.opens, 1)
        XCTAssertTrue(controller.isActive, "opening Settings does not cancel the session")
    }

    func testCommandCommaOpensSettingsWhileTheBoardIsOpen() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen in this environment")
        let box = OpensBox()
        _ = self.makeMenuOpensInto(box)
        let controller = self.controller()
        controller.toggleBoard()
        XCTAssertTrue(controller.isBoardActive, "the board has to be the one under test")
        defer { controller.toggleBoard() }

        XCTAssertTrue(NSApp.mainMenu?.performKeyEquivalent(with: commandComma()) ?? false, "round three S7: ⌘, must answer while the board holds the keyboard")
        XCTAssertEqual(box.opens, 1)
        XCTAssertTrue(controller.isBoardActive, "opening Settings does not close the board or its pages")
    }

    func testCommandCommaOpensSettingsWhileTheHistorySheetIsOpen() throws {
        let box = OpensBox()
        _ = self.makeMenuOpensInto(box)
        let controller = self.controller()
        controller.toggleCaptureHistory()
        XCTAssertTrue(controller.isCaptureHistoryVisible, "the history sheet has to be the one under test")
        defer { controller.toggleCaptureHistory() }

        XCTAssertTrue(NSApp.mainMenu?.performKeyEquivalent(with: commandComma()) ?? false, "round three S7: ⌘, must answer while the history sheet holds the keyboard")
        XCTAssertEqual(box.opens, 1)
        XCTAssertTrue(controller.isCaptureHistoryVisible, "opening Settings does not dismiss the sheet")
    }

    /// Nothing open: Stare is background, so a local keystroke cannot arrive
    /// — the honest closest proof is that the menu item is there and the
    /// dispatch answers ⌘, whatever the app's windowing history is, and
    /// routes into the one open path. The status-bar menu is the background
    /// route (and it already carries its own `Settings…`).
    func testCommandCommaDispatchesWhenNothingIsOpen() {
        let box = OpensBox()
        _ = self.makeMenuOpensInto(box)
        let controller = self.controller()
        XCTAssertFalse(controller.isAnyOverlaySurfaceActive, "no mode is on screen")

        XCTAssertTrue(NSApp.mainMenu?.performKeyEquivalent(with: commandComma()) ?? false)
        XCTAssertEqual(box.opens, 1, "⌘, opened Settings")
        XCTAssertFalse(controller.isAnyOverlaySurfaceActive)
    }

    // MARK: The open is visible from every mode

    /// While a mode holds the screen the open lifts Settings above the app's
    /// own surfaces; and the mode survives the open — nothing is cancelled
    /// behind the user's back, the convention the status bar and the guide
    /// already keep when they open the same window.
    func testOpeningSettingsWhileADrawingSessionIsOpenLiftsTheWindowAndKeepsTheMode() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display: a window cannot be ordered on screen")
        let controller = self.controller()
        controller.activate()
        defer { controller.deactivate() }

        let settings = self.makeSettingsController()
        settings.show(aboveOverlay: controller.isAnyOverlaySurfaceActive)
        let window = try self.settingsWindow()
        defer { window.orderOut(nil) }

        XCTAssertEqual(window.level, SettingsWindowController.overlaySurfaceLevel, "round three S7: Settings sits in the overlay band; at its normal level the `.screenSaver` panels would cover it")
        XCTAssertTrue(controller.isActive, "opening Settings does not cancel the drawing session")
    }

    /// With nothing of Stare's own on screen, an open is back at the window's
    /// ordinary level — the lift is only ever earned while a mode holds the
    /// screen, never kept after the modes closed.
    func testOpeningSettingsWithNothingOpenKeepsTheNormalLevel() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display: a window cannot be ordered on screen")
        let settings = self.makeSettingsController()
        settings.show(aboveOverlay: false)
        let window = try self.settingsWindow()
        defer { window.orderOut(nil) }

        XCTAssertEqual(window.level, .normal)
    }
}
