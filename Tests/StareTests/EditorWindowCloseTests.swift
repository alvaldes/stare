import AppKit
import XCTest

@testable import Stare
import StareCore

/// Round four S8 (odd/tasks/round-four.md): "porque cmd+w no cierra la
/// ventana del editor?"
///
/// The cause: Stare's menu家园-less accessory app gets its key equivalents
/// through the main menu's own key pass — before any responder — and the
/// menu never carried ⌘W, so the keystroke died there and never reached the
/// editor window at all. The editor's own keyDown never swallowed `w`, and
/// the window had no Close route of its own. The fix is the window's own
/// close button's route: a `Close Editor` (⌘W) item whose retained target
/// closes the CAPTURE EDITOR window only — the key window when the key
/// window IS an editor's — and leaves the Settings window, a floating panel
/// and the app itself alone: the gate reads nil for every other key window
/// and the item's action is a silent no-op for them.
///
/// The headless harness cannot make a regular window the key window (the
/// runner app never activates), so the route tests witness the gate the way
/// production reads it — the exact key-window question — and assert the
/// outcome on the close tail. The key-window lookup's real effect is the
/// owner's runtime eye, as with the Dock icon in S6.
@MainActor
final class CaptureEditorWindowCloseTests: XCTestCase {
    private var settingsTarget: SettingsShortcutMenuTarget?
    private var editorTarget: EditorCloseShortcutTarget?

    override func tearDown() {
        NSApp.mainMenu = nil
        settingsTarget = nil
        editorTarget = nil
        super.tearDown()
    }

    private func solidImage(width: Int = 30, height: Int = 20) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func commandW() throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "w", charactersIgnoringModifiers: "w",
            isARepeat: false, keyCode: 13))
    }

    private func editorWindow(onClose: @escaping () -> Void = {}) -> CaptureEditorWindow {
        let window = CaptureEditorWindow(
            image: solidImage(), capture: .standard, redactionStyle: .blur,
            onDeliver: nil) { _ in onClose() }
        window.confineToPrimaryScreen()
        return window
    }

    /// The same menu make-built the way the launch builds it, with the
    /// wired targets. The targets are retained in properties — NSMenuItem's
    /// weak target contract (the settings tests' note).
    private func menu(closeEditor target: EditorCloseShortcutTarget) -> NSMenu {
        _ = NSApplication.shared
        let settings = SettingsShortcutMenuTarget {}
        settingsTarget = settings
        editorTarget = target
        return AppDelegate.makeMainMenu(openSettings: settings, closeEditor: target)
    }

    // MARK: The menu shape

    /// The dispatch route exists, named exactly: `Close Editor` on ⌘W,
    /// routed through the one editor-only target — never nil-target
    /// validation, which would close whatever NON-editor window held the key.
    func testTheAppMenuCarriesCloseEditorOnCommandW() throws {
        let menu = menu(closeEditor: EditorCloseShortcutTarget())
        NSApp.mainMenu = menu

        let close = try XCTUnwrap(
            menu.items.first?.submenu?.items.first {
                $0.action == #selector(EditorCloseShortcutTarget.closeEditorWindow(_:))
            },
            "S8 canary: the app menu carries the Close Editor item")
        XCTAssertEqual(close.title, "Close Editor")
        XCTAssertEqual(close.keyEquivalent, "w")
        XCTAssertEqual(close.keyEquivalentModifierMask, [.command])
        XCTAssertTrue(
            close.target is EditorCloseShortcutTarget,
            "the item routes to the editor-only target")
        // The Settings half stays exactly round three S7 left it.
        XCTAssertEqual(menu.items.first?.submenu?.items.first?.title, "Settings…")
    }

    // MARK: The close route

    /// ⌘W with the editor holding the key closes IT — the way the window's
    /// own close button already does, through the window's close tail
    /// (exactly one close), while any other standing window stays open. The
    /// gate is driven with the key window production reads: an editor
    /// window.
    func testCommandWClosesTheEditorWindowThroughItsOwnCloseTail() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display: a window cannot be shown")
        var tail = 0
        let editor = editorWindow { tail += 1 }
        let gate: () -> CaptureEditorWindow? = { [editor] in editor }
        let menu = menu(closeEditor: EditorCloseShortcutTarget(keyEditorWindow: gate))
        NSApp.mainMenu = menu

        let other = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 160),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        other.confineToPrimaryScreen()
        other.orderFrontRegardless()
        defer { other.orderOut(nil) }

        XCTAssertTrue(
            menu.performKeyEquivalent(with: try commandW()),
            "⌘W belongs to the menu's Close Editor now")
        XCTAssertEqual(tail, 1, "S8: ⌘W closes the editor through its own close tail, exactly once")
        XCTAssertFalse(editor.isVisible, "S8: the editor window is gone")
        XCTAssertTrue(other.isVisible, "S8: ⌘W touches only the editor window")
        if editor.isVisible { editor.orderOut(nil) }
    }

    /// A non-editor window holding the key keeps its own trade: the gate
    /// reads nil for it (exactly production's `NSApp.keyWindow as?
    /// CaptureEditorWindow` declining) — the Settings window, a floating
    /// panel and the app itself are never closed, and the standing editor
    /// is left open.
    func testCommandWLeavesANonEditorKeyWindowAndAFloatingPanelAlone() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display: a window cannot be shown")
        // The default gate — production's own — answers nil here because the
        // key window is not an editor's (headless: no window can be key).
        let menu = menu(closeEditor: EditorCloseShortcutTarget())
        NSApp.mainMenu = menu

        var tail = 0
        let editor = editorWindow { tail += 1 }
        editor.orderFrontRegardless()
        let other = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 160),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        other.confineToPrimaryScreen()
        other.orderFrontRegardless()
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
        panel.confineToPrimaryScreen()
        panel.orderFrontRegardless()
        defer {
            other.orderOut(nil)
            panel.orderOut(nil)
            editor.orderOut(nil)
        }

        XCTAssertTrue(
            menu.performKeyEquivalent(with: try commandW()),
            "the item exists and answers, but its target's gate declined")
        XCTAssertTrue(other.isVisible, "S8: ⌘W never closes the Settings window's kind of trade")
        XCTAssertTrue(panel.isVisible, "S8: ⌘W never closes a floating panel either")
        XCTAssertTrue(editor.isVisible, "S8: ⌘W closed no editor without one holding the key")
        XCTAssertEqual(tail, 0)
    }

    // MARK: The launch wiring (canary)

    /// The real menu the app runs with must carry the target — a menu built
    /// only in a test proves nothing about the app's own key pass.
    func testTheLaunchWiresTheRealMenuWithTheEditorCloseTarget() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        let source = try String(
            contentsOf: url.appendingPathComponent("Sources/Stare/AppDelegate.swift"),
            encoding: .utf8)
        XCTAssertTrue(
            source.contains("makeMainMenu(openSettings: target, closeEditor:"),
            "S8 canary: the launch builds the menu with the editor close target wired")
        XCTAssertTrue(
            source.contains("NSApp.keyWindow as? CaptureEditorWindow"),
            "S8 canary: the gate reads the key window the way production dispatches ⌘W")
    }
}
