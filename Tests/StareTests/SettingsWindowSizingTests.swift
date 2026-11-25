import AppKit
import XCTest

@testable import Stare
import StareCore

/// B7: Settings has a floor the user cannot shrink past, the floor is ONE
/// number shared by the AppKit window and the SwiftUI root, and reopening the
/// window keeps the size the user chose instead of snapping back to the
/// default.
@MainActor
final class SettingsWindowSizingTests: XCTestCase {

    private final class InMemoryPreferenceStore: PreferenceStore {
        private var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    private func makeController() -> SettingsWindowController {
        SettingsWindowController(
            model: PreferencesModel(store: InMemoryPreferenceStore()),
            permission: ScreenRecordingPermission(client: StubClient())
        )
    }

    private struct StubClient: ScreenRecordingClient {
        func preflight() -> Bool { true }
        func request() -> Bool { true }
        func canCapture() -> Bool { true }
        func openPrivacySettings() {}
    }

    /// The window the controller shows, located by its title — the controller
    /// keeps its window private, and the window is what the user drags.
    private func settingsWindow() throws -> NSWindow {
        let window = try XCTUnwrap(
            NSApp.windows.first { $0.title == "Stare Settings" },
            "the controller must have shown its window"
        )
        return window
    }

    func testTheWindowStopsAtTheSharedMinimum() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display: a window cannot be ordered on screen")
        let controller = makeController()
        controller.show()
        let window = try settingsWindow()
        defer { window.orderOut(nil) }

        XCTAssertEqual(window.contentMinSize, SettingsWindowController.minimumContentSize,
            "the window's floor is the shared constant, not a second number of its own")
        XCTAssertGreaterThan(window.contentMinSize.width, 0)
        XCTAssertGreaterThan(window.contentMinSize.height, 0)
    }

    /// The floor has to survive a live resize, and the content minimum alone
    /// does not: AppKit re-derives it from the content view's constraints, and
    /// the hosting view carries none — which is why the first two attempts at
    /// this floor were still draggable to nothing (the owner's second pass).
    /// The delegate is the place a drag actually passes.
    func testALiveResizeIsClampedToTheMinimumFrame() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display: a window cannot be ordered on screen")
        let controller = makeController()
        controller.show()
        let window = try settingsWindow()
        defer { window.orderOut(nil) }

        let clamped = controller.windowWillResize(window, to: NSSize(width: 200, height: 120))
        let minimum = window.frameRect(
            forContentRect: CGRect(origin: .zero, size: SettingsWindowController.minimumContentSize)
        ).size
        XCTAssertEqual(clamped, minimum, "a drag below the floor stops at the floor")
        XCTAssertGreaterThanOrEqual(window.minSize.height, minimum.height, "and the window carries the same frame floor")
        XCTAssertGreaterThanOrEqual(window.minSize.width, minimum.width)
    }

    func testReopeningSettingsKeepsTheSizeTheUserChose() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display: a window cannot be ordered on screen")
        let controller = makeController()
        controller.show()
        let window = try settingsWindow()
        defer { window.orderOut(nil) }

        // A size the user picked, above the floor and below the default.
        let chosen = CGSize(width: 900, height: 620)
        window.setContentSize(chosen)
        XCTAssertEqual(window.contentView?.frame.size, chosen)

        controller.show()
        XCTAssertEqual(window.contentView?.frame.size, chosen,
            "reopening must not throw the resize away by forcing the default size back")
    }
}
