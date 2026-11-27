import AppKit
import XCTest

@testable import Stare

/// The panel's keyboard through the window's real event path: `showPanel`
/// makes the panel key with the hosting view as first responder, so Esc, the
/// arrows and Return work through `panel.sendEvent` — not only when a test
/// calls the model directly. Arrow mapping: ↓/→ walk toward the older
/// entries (next), ↑/← toward the newer ones (previous). B3 note: the slide
/// animation is app-only (`NSApp.isRunning`); in a `swift test` run the open
/// lands its final anchored frame synchronously, so every assertion here
/// sees the same panel state the shipped keyboard map produced before it.
@MainActor
final class CaptureHistoryPanelKeyboardTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    /// The process state before the class ran, restored in teardown (the
    /// shared `LeaveAsFound` hooks, round four's cross-test contamination
    /// follow-ups): `showPanel` keys the sheet, so the class leaves an active
    /// app and a standing key window behind, and TextSelectionWindowTests
    /// shares both reads with this process.
    private var foundState: LeaveAsFound.State!

    override func setUp() {
        super.setUp()
        foundState = LeaveAsFound.capture()
    }

    override func tearDown() {
        LeaveAsFound.restore(foundState)
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

    /// The walk tests' unit: the arrow map's ↓/↑ move a ROW of
    /// `model.columnCount`, which on a full-width sheet is the measured width
    /// of the machine's screen (ten columns on a 1920-wide display — see the
    /// sheet's row-move test in CaptureHistoryPanelTests). What these walks
    /// mean is “one ENTRY per → and a pick per ⏎”, so each pins its grid to
    /// ONE column explicitly instead of leaning on the narrow 640-panel the
    /// pre-B3 sheet happened to press accidentally (its grid never measured
    /// before the first assert).
    private func pinOneColumnGrid(_ panel: CaptureHistoryPanel) {
        panel.model.updateColumnCount(forGridWidth: CGFloat(panel.model.thumbnailSize))
        XCTAssertEqual(panel.model.columnCount, 1, "the walk's row unit is one entry here")
    }

    func testDownAndRightArrowsWalkToOlderAndReturnPicksThroughTheRealEventPath() throws {
        try XCTSkipIf(NSScreen.main == nil, "no primary screen in this environment")
        var pickedWidths: [Int] = []
        let panel = CaptureHistoryPanel(store: makeStore(entries: 3), onPick: { pickedWidths.append($0.width) })

        panel.showPanel()
        pinOneColumnGrid(panel)
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
        pinOneColumnGrid(panel)
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

/// Canary (S2): the context menu never disturbs the keyboard. Arming a
/// Delete on one cell leaves the panel's real event path exactly as shipped
/// — Esc closes, the arrows walk and disarm, Return still picks.
@MainActor
final class CaptureHistoryMenuKeyboardSurvivalTests: XCTestCase {
    /// The same leave-as-found hooks as the keyboard class above: `showPanel`
    /// keys the sheet here too, so the class hands back the activation, the
    /// key window and the cursor it found.
    private var foundState: LeaveAsFound.State!

    override func setUp() {
        super.setUp()
        foundState = LeaveAsFound.capture()
    }

    override func tearDown() {
        LeaveAsFound.restore(foundState)
        super.tearDown()
    }

    private func makeImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 8, height: 6, bitsPerComponent: 8,
            bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        return context.makeImage()!
    }

    private func makePanel(entries: Int) -> (CaptureHistoryPanel, CaptureHistoryStore) {
        let store = CaptureHistoryStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("stare-history-menu-keys-\(UUID().uuidString)", isDirectory: true)
        )
        for index in 0..<entries {
            _ = store.add(makeImage(), date: Date(timeIntervalSince1970: TimeInterval(index + 1)))
        }
        return (CaptureHistoryPanel(store: store, onPick: { _ in }), store)
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

    func testArmedDeleteLeavesTheKeyboardMapExactlyAsItWas() throws {
        try XCTSkipIf(NSScreen.main == nil, "no primary screen in this environment")
        let (panel, _) = makePanel(entries: 3)
        panel.showPanel()
        defer { panel.hide() }

        XCTAssertEqual(panel.model.menuItems(for: 0).first?.title, "Edit", "the cell menu exists beside the keys")
        // Pin the grid to one column, exactly as the walk tests above do:
        // one ENTRY per arrow, so the armed state is read on known indices.
        panel.model.updateColumnCount(forGridWidth: CGFloat(panel.model.thumbnailSize))
        XCTAssertEqual(panel.model.columnCount, 1)
        panel.model.perform(.delete, at: 0) // arm
        XCTAssertNotNil(panel.model.armedForDelete)

        panel.sendEvent(keyEvent(125, for: panel)) // ↓ walks older

        XCTAssertEqual(panel.model.selectedIndex, 1, "the walk still works")
        XCTAssertNil(panel.model.armedForDelete, "the walk disarms the pending delete")
        XCTAssertEqual(panel.model.menuItems(for: 0).last?.title, "Delete", "the disarm is visible in the menu")
        panel.sendEvent(keyEvent(36, for: panel)) // Return picks
        XCTAssertEqual(panel.model.selectedIndex, 1, "Return picked through the armed session too")
    }
}
