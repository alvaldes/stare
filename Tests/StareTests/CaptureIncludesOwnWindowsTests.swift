import AppKit
import ScreenCaptureKit
import XCTest

@testable import Stare
import StareCore

/// S8 (round three): "Aunque tenga settings abiertos, el historial debería
/// permitir hacer capturas sobre estas pantallas y no lo que hace ahora mismo
/// que hago la captura y no toma settings como parte de la captura".
///
/// The recorded cause: the capture filter excluded EVERY window of Stare's
/// own process (`ScreenContent.prepare`, `owningApplication?.processID == own
/// pid`) — the exclusion that legitimately keeps the drawing panels, the
/// palette, the capture cards and the pointer highlight out of the pixels
/// also took the Settings window down when it was open on screen. The filter
/// now excludes every own window EXCEPT the one the owner captures over:
/// the Settings window, keyed on the title constant both the controller and
/// the filter read.
///
/// Kinds, stated now rather than implied — where the rule applies:
/// - the whole-display capture and the frozen area base ride the same
///   `ScreenContent.prepare`, so Settings appears in both, compositor and
///   crop keeping whatever of it falls inside the framed region;
/// - the live-blur frame source rides the same prepare too (harmless: blur
///   refresh only reads the pixels);
/// - the ⌥S window capture is LEFT OUT deliberately: it resolves the
///   front-most window of ANOTHER app and crops that window out of the
///   display image — "Stare's windows are never that capture's target" is the
///   documented contract of `WindowCaptureTarget`; and a window capture of
///   the Settings window itself would be a new feature, not this fix.
///
/// What happens when Settings overlaps the region being captured (asked
/// explicitly by the round): its pixels ARE the screen's pixels — the
/// capture records what the screen shows, and an overlapping window enters
/// the image wherever it covers the region, exactly as a window of another
/// app would. There is no per-window subtraction a screen capture can do.
final class CaptureIncludesOwnWindowsTests: XCTestCase {

    // MARK: The pure rule the filter runs

    /// The matrix the filter decides on: own chrome out, Settings in, other
    /// apps never touched.
    func testTheExclusionLeavesExactlyTheSettingsWindowOfStareOwn() {
        let ownPID: Int32 = 4711
        let otherPID: Int32 = 9002
        let settingsTitle = ScreenContent.settingsWindowTitle

        // The Settings window: kept in.
        XCTAssertFalse(ScreenContent.excludesOwnWindow(
            ownerPID: ownPID, title: settingsTitle, ownPID: ownPID,
            settingsWindowTitle: settingsTitle
        ))
        // Every other own surface is chrome the capture must never itself
        /// photograph: an untitled panel (the drawing canvases, the cards), a
        /// window with any other title (the palette, the history sheet).
        XCTAssertTrue(ScreenContent.excludesOwnWindow(
            ownerPID: ownPID, title: nil, ownPID: ownPID, settingsWindowTitle: settingsTitle
        ), "an untitled own window — the drawing panel — stays out")
        XCTAssertTrue(ScreenContent.excludesOwnWindow(
            ownerPID: ownPID, title: "More tools", ownPID: ownPID,
            settingsWindowTitle: settingsTitle
        ), "an own window with a title that is not Settings' stays out")
        // Another app's window is never the exclusion's business, whatever it is titled.
        XCTAssertFalse(ScreenContent.excludesOwnWindow(
            ownerPID: otherPID, title: settingsTitle, ownPID: ownPID,
            settingsWindowTitle: settingsTitle
        ), "a foreign window titled like Settings is that app's window")
        XCTAssertFalse(ScreenContent.excludesOwnWindow(
            ownerPID: nil, title: settingsTitle, ownPID: ownPID,
            settingsWindowTitle: settingsTitle
        ), "a window with no owning application is captured")
        // The Settings window's own title is one constant with the controller's
        // window title; pin the exact string the window server reports.
        XCTAssertEqual(settingsTitle, "Stare Settings")
    }

    // MARK: The window the rule keys on is the one the controller shows

    /// The rule matches a TITLE; this pins the link: the real window the
    /// controller opens carries exactly the title the filter looks for.
    @MainActor
    func testTheSettingsWindowCarriesTheTitleTheCaptureRuleKeysOn() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display: a window cannot be ordered on screen")
        let settings = self.makeSettingsController()
        settings.show()
        let window = try XCTUnwrap(
            NSApp.windows.first { $0.title == ScreenContent.settingsWindowTitle },
            "the Settings window must carry the title the capture rule keys on — otherwise the filter excludes or keeps the wrong windows"
        )
        window.orderOut(nil)
        XCTAssertEqual(window.title, "Stare Settings")
    }

    // MARK: The real pixels (needs Screen Recording; skipped without it)

    /// The closest honest proof of the capture itself: with the permission
    /// actually granted (never prompted at test time — the preflight only
    /// reads), a Settings-named window on screen is IN the captured image and
    /// Stare's own overlay surface is NOT. This runner normally has no
    /// permission, in which case the two pins above carry the proof and the
    /// skip says so.
    @MainActor
    func testWhenSettingsIsOnScreenTheCaptureHoldsItsContentAndTheOverlayDoesNot() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display: a capture needs one")
        let service = CaptureService()
        guard service.hasPermission else {
            throw XCTSkip(
                "Screen Recording is not granted to this runner: the rule matrix and the window-title pin above carry the proof, and the preflight is only ever read, never asked"
            )
        }
        let settingColour = NSColor(calibratedRed: 0.95, green: 0.08, blue: 0.08, alpha: 1)
        let overlayColour = NSColor(calibratedRed: 0.06, green: 0.95, blue: 0.4, alpha: 1)

        let screen = try XCTUnwrap(NSScreen.main)
        let frame = CGRect(x: screen.frame.minX + 60, y: screen.frame.minY + 160, width: 220, height: 150)
        let settingsHelper = self.titledWindow(frame: frame, title: ScreenContent.settingsWindowTitle, backing: settingColour)
        let overlayHelper = self.titledWindow(frame: frame.offsetBy(dx: 260, dy: 0), title: nil, backing: overlayColour)
        defer { settingsHelper.orderOut(nil); overlayHelper.orderOut(nil) }

        let displayID = try XCTUnwrap(
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        )

        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        let image = try service.captureDisplay(displayID)

        XCTAssertGreaterThan(self.pixelCount(of: image, closeTo: settingColour), 4_000,
                             "round three S8: the Settings window's own content is IN the capture")
        XCTAssertEqual(self.pixelCount(of: image, closeTo: overlayColour), 0,
                       "round three S8: Stare's own overlay surface stays out of the capture")
    }

    // MARK: Fixtures

    @MainActor
    private func makeSettingsController() -> SettingsWindowController {
        final class Store: PreferenceStore {
            var values: [String: Any] = [:]
            func object(forKey key: String) -> Any? { values[key] }
            func set(_ value: Any?, forKey key: String) { values[key] = value }
        }
        final class Client: ScreenRecordingClient {
            func preflight() -> Bool { true }
            func request() -> Bool { true }
            func canCapture() -> Bool { true }
            func openPrivacySettings() {}
        }
        return SettingsWindowController(
            model: PreferencesModel(store: Store()),
            permission: ScreenRecordingPermission(client: Client())
        )
    }

    private func titledWindow(frame: CGRect, title: String?, backing: NSColor) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: title == nil ? [.borderless] : [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = title ?? ""
        window.backgroundColor = backing
        window.isOpaque = true
        window.orderFrontRegardless()
        return window
    }

    /// Pixels of `image` whose colour sits within a narrow band of `colour`.
    /// The count is compared over the WHOLE capture, so the assertion does no
    /// display-scale arithmetic (Retina, docked edges, wallpaper beneath —
    /// none can confuse the two very distant colours).
    private func pixelCount(of image: CGImage, closeTo colour: NSColor) -> Int {
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return -1 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return -1 }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let target = colour.usingColorSpace(.sRGB) ?? NSColor.white
        let red = target.redComponent * 255, green = target.greenComponent * 255,
            blue = target.blueComponent * 255
        var count = 0
        for index in stride(from: 0, to: width * height * 4, by: 4) {
            if abs(Double(bytes[index]) - red) < 24,
               abs(Double(bytes[index + 1]) - green) < 24,
               abs(Double(bytes[index + 2]) - blue) < 24 {
                count += 1
            }
        }
        return count
    }
}
