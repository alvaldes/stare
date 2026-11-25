import AppKit
import SwiftUI
import XCTest

@testable import Stare

/// Tests for the capture history panel (S2/S2a): the model's ordering, empty
/// state and keyboard routing, the pick seam (default clipboard, injectable
/// for T2b), and the panel's level above every other Stare surface.
@MainActor
final class CaptureHistoryPanelTests: XCTestCase {
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
            .appendingPathComponent("stare-history-panel-tests-\(UUID().uuidString)", isDirectory: true)
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
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
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

    // MARK: Ordering and empty state

    func testThePanelModelShowsNewestFirstAndStartsSelectedOnTheNewest() {
        let store = makeStore(entries: 3)
        let model = CaptureHistoryPanelModel(store: store, onPick: { _ in }, onClose: {})

        model.refresh()

        XCTAssertFalse(model.isEmpty)
        XCTAssertEqual(model.entries.map(\.pixelWidth), [12, 11, 10], "newest capture first")
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.selectedEntry?.pixelWidth, 12)
    }

    func testThePanelModelReportsAnEmptyStateWithNothingStored() {
        let model = CaptureHistoryPanelModel(store: makeStore(), onPick: { _ in }, onClose: {})

        model.refresh()

        XCTAssertTrue(model.isEmpty)
        XCTAssertNil(model.selectedIndex)
        XCTAssertNil(model.selectedEntry)
    }

    // MARK: Keyboard navigation

    func testArrowNavigationMovesTheSelectionAndClampsAtTheEnds() {
        let model = CaptureHistoryPanelModel(store: makeStore(entries: 3), onPick: { _ in }, onClose: {})
        model.refresh()

        model.moveSelection(1)
        XCTAssertEqual(model.selectedIndex, 1)
        model.moveSelection(1)
        model.moveSelection(1)
        XCTAssertEqual(model.selectedIndex, 2, "the move clamps at the oldest entry")
        model.moveSelection(-1)
        XCTAssertEqual(model.selectedIndex, 1)
        model.moveSelection(-1)
        model.moveSelection(-1)
        XCTAssertEqual(model.selectedIndex, 0, "the move clamps at the newest entry")
    }

    func testKeyboardNavigationDoesNothingOnAnEmptyHistory() {
        let model = CaptureHistoryPanelModel(store: makeStore(), onPick: { _ in }, onClose: {})
        model.refresh()

        model.moveSelection(1)
        model.pickSelected()

        XCTAssertNil(model.selectedIndex)
    }

    // MARK: Picking

    func testReturnPicksTheSelectedCaptureAndClosesThePanel() {
        let store = makeStore(entries: 2)
        var picked: CGImage?
        var closeCount = 0
        let model = CaptureHistoryPanelModel(
            store: store,
            onPick: { picked = $0 },
            onClose: { closeCount += 1 }
        )
        model.refresh()
        model.moveSelection(1)

        model.pickSelected()

        XCTAssertEqual(picked?.width, 10, "the selection's own capture (the older one) is picked, not the newest")
        XCTAssertEqual(closeCount, 1)
    }

    func testTheDefaultDeliveryCopiesPNGAndTIFFToThePasteboard() {
        NSPasteboard.general.clearContents()
        CaptureHistoryPanel.copyToPasteboard(makeImage())

        XCTAssertTrue(NSPasteboard.general.types?.contains(.png) ?? false)
        XCTAssertTrue(NSPasteboard.general.types?.contains(.tiff) ?? false)
    }

    // MARK: Clear

    func testThePanelClearButtonEmptiesTheModelAndTheStore() {
        let store = makeStore(entries: 2)
        let model = CaptureHistoryPanelModel(store: store, onPick: { _ in }, onClose: {})
        model.refresh()

        model.clearHistory()

        XCTAssertTrue(model.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNil(model.selectedIndex)
    }

    // MARK: Level above every Stare surface

    func testThePanelSitsAboveTheBoardTheToolbarAndTheCaptureCards() {
        // Overlay/board windows: .screenSaver; the toolbar: +1; cards: +2.
        let cardLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        XCTAssertGreaterThan(CaptureHistoryPanel.panelLevel.rawValue, cardLevel.rawValue)
    }

    // MARK: Placement

    func testThePanelCentersOnTheScreenUnderThePointer() throws {
        try XCTSkipIf(NSScreen.main == nil, "no primary screen in this environment")
        let store = makeStore(entries: 1)
        let panel = CaptureHistoryPanel(store: store)

        panel.showPanel()

        defer { panel.hide() }
        let pointer = NSEvent.mouseLocation
        // The panel centres on the screen under the pointer, so that is the one
        // to measure against — on a multi-display desk it is often not the
        // primary, and asserting the primary made this test fail there.
        let target = NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let screen = try XCTUnwrap(target)
        XCTAssertTrue(screen.frame.contains(panel.frame), "the panel opens inside the screen under the pointer")
    }

    // MARK: Pick route through the overlay (board open without a board view)

    /// A real OverlayController with a real board, mirroring
    /// WhiteboardClearRoutingTests' harness: the pick route runs through the
    /// controller, which is what the panel's `onPick` calls. The view
    /// returned is the one the controller's pick resolves — the board canvas
    /// under the pointer, or the first live one, exactly `selfTestViews`'
    /// order.
    private func makeBoardController() throws -> (controller: OverlayController, view: WhiteboardView) {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screens: the board canvases need one")
        // xctest runs without an initialized NSApplication: the controller's
        // board lifecycle talks to NSApp, so create it here first.
        _ = NSApplication.shared
        let controller = OverlayController(captureService: CaptureService())
        controller.toggleBoard()
        guard controller.isBoardActive,
              let boardView = controller.selfTestViews.compactMap({ $0 as? WhiteboardView }).first(where: {
                  $0.window?.frame.contains(NSEvent.mouseLocation) == true
              }) ?? controller.selfTestViews.compactMap({ $0 as? WhiteboardView }).first
        else {
            controller.toggleBoard()
            throw XCTSkip("board canvas could not be created")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        return (controller, boardView)
    }

    func testAPickWhileTheBoardIsOpenPastesOntoThePageAndNeverTouchesThePasteboard() throws {
        let (controller, view) = try makeBoardController()
        defer { controller.toggleBoard() }
        NSPasteboard.general.clearContents()

        controller.deliverHistoryPick(makeImage(width: 30, height: 20))

        XCTAssertNotNil(view.board.currentPage.image, "the pick pastes the capture as the page's image layer")
        XCTAssertFalse(
            NSPasteboard.general.types?.contains(.png) ?? false,
            "the board paste never also writes the clipboard"
        )
    }

    func testAPickWithNoBoardOpenCopiesToThePasteboard() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screens: the controller needs one")
        _ = NSApplication.shared
        let controller = OverlayController(captureService: CaptureService())
        NSPasteboard.general.clearContents()

        controller.deliverHistoryPick(makeImage())

        XCTAssertTrue(NSPasteboard.general.types?.contains(.png) ?? false)
        // The type alone does not prove a picture landed: Return used to leave
        // an empty PNG behind, so decode what was actually copied.
        let png = try XCTUnwrap(NSPasteboard.general.data(forType: .png))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(bitmap.pixelsWide, 8)
        XCTAssertEqual(bitmap.pixelsHigh, 6)
        let colour = try XCTUnwrap(bitmap.colorAt(x: 4, y: 3)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(colour.blueComponent, 0.8, "the copied PNG carries the capture, not a blank plate")
        XCTAssertLessThan(colour.redComponent, 0.2)
    }

    func testHidingTheCaptureHistoryHandsKeyFocusBackToTheSurfaceThatWasWorkingBeforeIt() throws {
        let (controller, view) = try makeBoardController()
        defer { controller.toggleBoard() }
        guard let boardPanel = view.window else {
            throw XCTSkip("the board canvas has no window")
        }
        XCTAssertEqual(boardPanel.firstResponder, view, "the board canvas owns focus before the history opens")

        controller.toggleCaptureHistory()
        XCTAssertTrue(controller.isCaptureHistoryVisible)
        // Esc through the panel's real event path: it hides the panel and the
        // focus comes back to the board canvas.
        let escape = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: controller.captureHistoryPanel.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53
        )!
        controller.captureHistoryPanel.sendEvent(escape)

        XCTAssertFalse(controller.isCaptureHistoryVisible, "Esc closes the panel")
        XCTAssertEqual(boardPanel.firstResponder, view, "the surface that was working before the panel is first responder again")
    }
}

/// B1: the panel's grid cell width comes from the preference, read on every
/// open — a Settings change reaches the next ⌥⇧I instead of waiting for a
/// relaunch, which is what a captured-at-launch value would do.
@MainActor
final class CaptureHistoryThumbnailSizeTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        var value: Double
        init(_ value: Double) { self.value = value }
    }

    func testThePanelReadsTheThumbnailSizeEveryTimeItRefreshes() {
        let box = Box(240)
        let model = CaptureHistoryPanelModel(
            store: CaptureHistoryStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)),
            thumbnailSize: { box.value },
            onPick: { _ in },
            onClose: {}
        )

        model.refresh()
        XCTAssertEqual(model.thumbnailSize, 240, "the first open reads the preference")

        box.value = 130
        model.refresh()
        XCTAssertEqual(model.thumbnailSize, 130, "the next open picks up the change without a relaunch")
    }
}

/// The grid's row arithmetic: in a three-column grid the cell under the first
/// is the FOURTH, so the vertical arrows move by a row, never by one.
@MainActor
final class CaptureHistoryGridNavigationTests: XCTestCase {
    private func model(entries: Int, columns: Int) -> CaptureHistoryPanelModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = CaptureHistoryStore(directory: directory)
        for index in 0..<entries {
            let context = CGContext(
                data: nil, width: 10, height: 10, bitsPerComponent: 8,
                bytesPerRow: 40, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context?.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
            if let image = context?.makeImage() {
                _ = store.add(image, date: Date().addingTimeInterval(TimeInterval(-index)))
            }
        }
        let model = CaptureHistoryPanelModel(store: store, onPick: { _ in }, onClose: {})
        model.refresh()
        // The same arithmetic the view reports: width = columns * minimum + gaps.
        let spacing: CGFloat = 10
        let minimum = CGFloat(model.thumbnailSize)
        model.updateColumnCount(forGridWidth: CGFloat(columns) * minimum + CGFloat(columns - 1) * spacing)
        return model
    }

    func testDownMovesOneRowNotOneCell() {
        let model = model(entries: 4, columns: 3)
        XCTAssertEqual(model.columnCount, 3)
        model.select(at: 0)
        model.moveSelection(model.columnCount)
        XCTAssertEqual(model.selectedIndex, 3, "in a three-column grid the cell below the first is the fourth")
    }

    func testUpMovesOneRowBackAndClampsAtTheTop() {
        let model = model(entries: 4, columns: 3)
        model.select(at: 3)
        model.moveSelection(-model.columnCount)
        XCTAssertEqual(model.selectedIndex, 0)
        model.moveSelection(-model.columnCount)
        XCTAssertEqual(model.selectedIndex, 0, "there is no row above the first")
    }

    func testSingleColumnGridMovesOneCellPerRow() {
        let model = model(entries: 3, columns: 1)
        XCTAssertEqual(model.columnCount, 1)
        model.select(at: 0)
        model.moveSelection(model.columnCount)
        XCTAssertEqual(model.selectedIndex, 1)
    }
}

/// B2: the history closes on the first click anywhere else, the way a
/// paste-style palette does. The decision is a value rule — the monitors only
/// feed it — so it is pinned without windows, screens or event taps.
@MainActor
final class CaptureHistoryOutsideClickTests: XCTestCase {
    func testAClickOutsideClosesThePanel() {
        XCTAssertTrue(
            CaptureHistoryPanel.hides(forClickOnPanelWindow: false, insidePanelFrame: false),
            "a click on another window or another app closes the history"
        )
    }

    func testAClickOnThePanelOrInsideItsFrameLeavesItUp() {
        XCTAssertFalse(
            CaptureHistoryPanel.hides(forClickOnPanelWindow: true, insidePanelFrame: false),
            "the panel's own click is the panel's"
        )
        XCTAssertFalse(
            CaptureHistoryPanel.hides(forClickOnPanelWindow: false, insidePanelFrame: true),
            "a click inside the panel's frame is still the panel's, even if the window beneath took it"
        )
    }

    func testOpeningAndClosingThePanelLeavesNoMonitorsBehind() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display: the panel cannot be ordered on screen")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let panel = CaptureHistoryPanel(store: CaptureHistoryStore(directory: directory))
        var hidden = 0
        panel.onHidden = { hidden += 1 }

        panel.showPanel()
        panel.hide()
        panel.showPanel()
        panel.hide()

        XCTAssertEqual(hidden, 2, "each close runs the hook once")
        XCTAssertFalse(panel.isVisible)
    }
}
