import AppKit
import XCTest

@testable import Stare

/// The panel's keyboard through the window's real event path: `showPanel`
/// makes the panel key with the hosting view as first responder, so Esc, the
/// arrows and Return work through `panel.sendEvent` — not only when a test
/// calls the model directly. Arrow mapping: ↓/→ walk toward the older
/// entries (next), ↑/← toward the newer ones (previous).
@MainActor
final class CaptureHistoryPanelKeyboardTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    // MARK: Helpers

    private func makeStoreDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stare-history-keyboard-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeImage(width: Int = 8, height: Int = 6) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makeStore(entries: Int = 0) -> CaptureHistoryStore {
        let store = CaptureHistoryStore(directory: makeStoreDirectory())
        for index in 0..<entries {
            _ = store.add(makeImage(width: 10 + index, height: 8), date: Date(timeIntervalSince1970: TimeInterval(index + 1)))
        }
        return store
    }

    private func keyEvent(_ keyCode: UInt16, for window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    // MARK: First responder

    func testShowPanelMakesTheHostingViewTheFirstResponderSoTheKeysHaveSomewhereToGo() throws {
        try XCTSkipIf(NSScreen.main == nil, "no primary screen in this environment")
        let panel = CaptureHistoryPanel(store: makeStore(entries: 1))

        panel.showPanel()

        defer { panel.hide() }
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.isKeyWindow, "becoming key is intended; the style stays non-activating")
        XCTAssertTrue(
            panel.firstResponder is CaptureHistoryPanelHostingView,
            "the hosting view must be first responder, or every key event is dropped"
        )
    }

    // MARK: Esc through the real event path

    func testEscapeThroughTheRealEventPathClosesThePanel() throws {
        try XCTSkipIf(NSScreen.main == nil, "no primary screen in this environment")
        var picks = 0
        let panel = CaptureHistoryPanel(store: makeStore(entries: 1), onPick: { _ in picks += 1 })

        panel.showPanel()
        panel.sendEvent(keyEvent(53, for: panel)) // Esc

        XCTAssertFalse(panel.isVisible, "Esc closes the panel through the window's event path")
        XCTAssertEqual(picks, 0, "Esc never picks")
    }

    // MARK: Arrows and Return through the real event path

    func testDownAndRightArrowsWalkToOlderAndReturnPicksThroughTheRealEventPath() throws {
        try XCTSkipIf(NSScreen.main == nil, "no primary screen in this environment")
        var pickedWidths: [Int] = []
        let panel = CaptureHistoryPanel(store: makeStore(entries: 3), onPick: { pickedWidths.append($0.width) })

        panel.showPanel()
        panel.sendEvent(keyEvent(125, for: panel)) // ↓: next, older
        XCTAssertEqual(panel.model.selectedIndex, 1, "↓ moves to the next (older) entry")
        panel.sendEvent(keyEvent(124, for: panel)) // →: next, older
        XCTAssertEqual(panel.model.selectedIndex, 2)
        panel.sendEvent(keyEvent(36, for: panel)) // Return

        XCTAssertEqual(pickedWidths, [10], "Return picks the selection's own capture (the oldest of three)")
        XCTAssertFalse(panel.isVisible, "picking closes the panel")
    }

    func testUpAndLeftArrowsWalkBackToNewerThroughTheRealEventPath() throws {
        try XCTSkipIf(NSScreen.main == nil, "no primary screen in this environment")
        let panel = CaptureHistoryPanel(store: makeStore(entries: 3), onPick: { _ in })

        panel.showPanel()
        panel.sendEvent(keyEvent(125, for: panel)) // ↓ to the second (older)
        XCTAssertEqual(panel.model.selectedIndex, 1, "↓ moved: the walk back below is real")
        panel.sendEvent(keyEvent(123, for: panel)) // ←: previous, newer
        XCTAssertEqual(panel.model.selectedIndex, 0, "← moves back toward the newer entries")
        panel.sendEvent(keyEvent(125, for: panel)) // ↓ again
        panel.sendEvent(keyEvent(126, for: panel)) // ↑: previous, newer
        XCTAssertEqual(panel.model.selectedIndex, 0, "↑ moves back toward the newer entries")
        panel.sendEvent(keyEvent(123, for: panel)) // ← clamps at the newest
        XCTAssertEqual(panel.model.selectedIndex, 0, "the walk never leaves the entries")
    }
}
