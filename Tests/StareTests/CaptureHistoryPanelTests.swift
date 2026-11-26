import AppKit
import StareCore
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

    // MARK: Placement (B3): the bottom sheet

    /// Re-derived (B3): the panel no longer CENTRES on the pointer's screen —
    /// it SPANS that screen's visible frame, flush to its bottom, at the fixed
    /// 0.42 height. The screen-selection rule survives (screen under the
    /// pointer); what changed is where on it the sheet sits and how wide.
    func testTheOpenSheetSpansTheVisibleFrameOfTheScreenUnderThePointerFlushToItsBottom() throws {
        try XCTSkipIf(NSScreen.main == nil, "no primary screen in this environment")
        let store = makeStore(entries: 1)
        let panel = CaptureHistoryPanel(store: store)

        panel.showPanel()

        defer { panel.hide() }
        let pointer = NSEvent.mouseLocation
        // The sheet opens on the screen under the pointer, so that is the one
        // to measure against — on a multi-display desk it is often not the
        // primary, and asserting the primary made this test fail there (the
        // screen choice is the one part of the old test that never changed).
        let target = NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let screen = try XCTUnwrap(target)
        let visible = screen.visibleFrame
        let frame = panel.frame
        XCTAssertEqual(frame.minX, visible.minX, accuracy: 0.5, "the sheet spans the visible frame's full width")
        XCTAssertEqual(frame.width, visible.width, accuracy: 0.5, "full visible width, on any display")
        XCTAssertEqual(frame.minY, visible.minY, accuracy: 0.5, "flush to the visible frame's BOTTOM edge (macOS y is up)")
        XCTAssertEqual(
            frame.height,
            max(visible.height * CaptureHistoryPanel.sheetHeightFraction,
                CaptureHistoryPanel.defaultMinimumShelfHeight),
            accuracy: 0.5,
            "the fixed height rule: 0.42 of the visible height, never below the shelf floor"
        )
        XCTAssertTrue(visible.contains(
            CGRect(origin: frame.origin, size: CGSize(width: frame.width - 1, height: frame.height - 1))
        ), "the sheet sits inside the visible frame: the Dock stays clear")
    }

    /// The value side of the same rule, on the reference 1440-tall display:
    /// a screen whose full frame is 1440 tall leaves a 1416-tall visible
    /// frame under the 24-pt menu bar. Pinned here so the rule is readable
    /// in numbers, not only through a real NSScreen.
    func testTheSheetFrameRuleOnAReference1440TallDisplay() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 1416)
        let frame = CaptureHistoryPanel.sheetFrame(inVisibleFrame: visible)
        XCTAssertEqual(frame.width, 1440, "full visible width")
        XCTAssertEqual(frame.minY, 0, "flush to the bottom edge — the visible frame's own minY")
        XCTAssertEqual(frame.maxY, 1416 * CaptureHistoryPanel.sheetHeightFraction, accuracy: 0.01, "one 0.42-sheet above the bottom edge, wallpaper still visible above")
        // Reported for the ledger (T1 evidence): the measured frame on the
        // reference 1440-tall display.
        print("[b3-geometry] 1440-tall display sheet frame: \(frame)")
    }

    /// The height rule's floor: on a very short visible frame (an attached TV
    /// in mirror mode, a Split cut) the 0.42 fraction must never crush a card
    /// row plus the header out of the shelf.
    func testAShortVisibleFrameNeverCrushesOneCardRowPlusTheHeader() {
        let visible = CGRect(x: 0, y: 0, width: 1200, height: 600)
        let floor = CaptureHistoryPanel.minimumShelfHeight(thumbnailSize: 170)
        XCTAssertTrue(floor > 170, "one card row (the thumbnail) plus the header chrome, not just the thumbnail")
        let frame = CaptureHistoryPanel.sheetFrame(inVisibleFrame: visible, minimumHeight: floor)
        XCTAssertEqual(frame.height, floor, "the floor wins when 0.42×height drops below it")
        XCTAssertLessThanOrEqual(frame.height, visible.height, "the floor never overflows the screen")
    }

    /// A screen-configuration or Space change while the sheet is visible
    /// re-derives the anchored frame (B3/S3). Driven through the real
    /// controller observers, which is what owns the re-place wiring.
    func testAScreenOrSpaceChangeRePlacesTheVisibleSheetAnchoredToTheBottom() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screens: the re-place needs one")
        _ = NSApplication.shared
        let controller = OverlayController(captureService: CaptureService())
        let panel = controller.captureHistoryPanel
        panel.showPanel()

        // Pretend the sheet was dragged or its screen replaced: re-place re-derives.
        panel.setFrame(CGRect(x: 200, y: 400, width: 500, height: 300), display: false)
        controller.screenParametersChanged()

        let visible = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        XCTAssertEqual(panel.frame.width, visible.width, accuracy: 0.5, "re-anchored: full visible width")
        XCTAssertEqual(panel.frame.minY, visible.minY, accuracy: 0.5, "re-anchored: flush to the bottom edge")

        controller.activeSpaceChanged()
        XCTAssertEqual(panel.frame.width, visible.width, accuracy: 0.5, "a Space change re-places too")
        XCTAssertEqual(panel.frame.minY, visible.minY, accuracy: 0.5)

        panel.hide()
        controller.screenParametersChanged()
        XCTAssertFalse(panel.isVisible, "the re-place never SHOWS a hidden sheet")
        XCTAssertTrue(visible.contains(
            CGRect(origin: panel.frame.origin, size: CGSize(width: panel.frame.width - 1, height: panel.frame.height - 1))
        ))
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

    // MARK: Round four S1: an acted menu action closes the sheet, focus follows

    /// Full-panel half of S1: an action performed through the sheet's own
    /// model closes the visible sheet, and the panel's hide runs the focus
    /// hook exactly once — the same dismissal the pick drives.
    func testAnActedMenuActionClosesTheVisibleSheetRunsTheFocusHookOnce() throws {
        try XCTSkipIf(NSScreen.main == nil, "no display: the panel cannot be shown")
        let store = makeStore(entries: 2)
        let panel = CaptureHistoryPanel(store: store)
        var hidden = 0
        panel.onHidden = { hidden += 1 }
        NSPasteboard.general.clearContents()
        panel.showPanel()
        XCTAssertTrue(panel.isVisible)

        panel.model.perform(.copyImage, at: 0)

        XCTAssertTrue(NSPasteboard.general.types?.contains(.png) ?? false, "the copy ran")
        XCTAssertFalse(panel.isVisible, "the acted action closed the sheet like a pick does")
        XCTAssertEqual(hidden, 1, "the focus-restoring hook ran once, exactly the pick's dismissal")
        panel.model.onClose = {} // the test's own panel: detach the hook from the shared production wiring
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

    /// B3: the sheet is full width, so the grid simply gets more columns —
    /// at the reference 1440-wide sheet with the default 170-pt cell it is
    /// SEVEN — and the vertical arrows must still move a row at that count.
    func testUpAndDownStillMoveARowAcrossTheFullWidthSheet() {
        // The measured width a 1440-wide sheet hands the model: the sheet
        // spans the visible frame minus the sheet's 16-pt side padding, and
        // (1408 + 10) / (170 + 10) ⌊ 7.87 ⌋ = 7 columns.
        let model = model(entries: 9, columns: 7)
        XCTAssertEqual(model.columnCount, 7)
        model.select(at: 0)
        model.moveSelection(model.columnCount)
        XCTAssertEqual(model.selectedIndex, 7, "↓ moves a full row in the seven-column shelf")
        model.moveSelection(-model.columnCount)
        XCTAssertEqual(model.selectedIndex, 0, "↑ moves a full row back and clamps at the newest")
    }
}

/// B2 re-derived (B3): the outside-click rule stays a value rule — the
/// monitors only feed it — so it is pinned without windows, screens or event
/// taps. The second clause's MEANING moved with the shape: the frame it
/// protects is now the full-width bottom strip, so a click anywhere in that
/// strip (the sheet's chrome, its blind margins) keeps the sheet open.
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

    /// Re-derived pin (B3): with the sheet spanning the bottom strip, a click
    /// anywhere inside the anchored frame keeps the sheet open. Tested through
    /// real strip points, not an abstract bool.
    func testAClickAnywhereInTheBottomStripKeepsTheSheetOpen() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 1416)
        let strip = CaptureHistoryPanel.sheetFrame(inVisibleFrame: visible)
        XCTAssertTrue(strip.height < visible.height, "it is the bottom strip, not a full-screen plate")
        for point in [
            CGPoint(x: strip.midX, y: strip.minY + 1), // the very edge above the Dock
            CGPoint(x: strip.minX + 1, y: strip.midY), // the left margin
            CGPoint(x: strip.maxX - 1, y: strip.midY), // the right margin
            CGPoint(x: strip.midX, y: strip.midY), // the chrome between the cards
        ] {
            XCTAssertTrue(strip.contains(point), "\(point) lands in the strip")
            XCTAssertFalse(
                CaptureHistoryPanel.hides(forClickOnPanelWindow: false, insidePanelFrame: strip.contains(point)),
                "a click in the bottom strip keeps the sheet open"
            )
        }
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

/// The history cell's right-click context menu (S2): the menu's shape, the
/// routing of each action through its seam, the two-click Delete, and the
/// disable-when-there-is-no-file rule that keeps every offered item honest.
/// No windows are opened: the cell's `.contextMenu` is derived from the
/// model's item list, so driving that list IS the menu's real path.
@MainActor
final class CaptureHistoryContextMenuTests: XCTestCase {
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
            .appendingPathComponent("stare-history-menu-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeImage(width: Int = 8, height: Int = 6, red: CGFloat = 1) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: red, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makeModel(entries: Int = 2) -> (CaptureHistoryPanelModel, CaptureHistoryStore, [PersistedCaptureEntry]) {
        let store = CaptureHistoryStore(directory: makeStoreDirectory())
        var added: [PersistedCaptureEntry] = []
        for index in 0..<entries {
            added.append(store.add(
                makeImage(width: 10 + index),
                date: Date(timeIntervalSince1970: TimeInterval(index + 1))
            ))
        }
        let model = CaptureHistoryPanelModel(store: store, onPick: { _ in }, onClose: {}, onEdit: { _ in })
        model.refresh()
        added.reverse() // newest first, the grid's order
        return (model, store, added)
    }

    private func capturesDirectory(of store: CaptureHistoryStore) -> URL {
        store.directory.appendingPathComponent("captures", isDirectory: true)
    }

    private func capturesDirectory(of directory: URL) -> URL {
        directory.appendingPathComponent("captures", isDirectory: true)
    }

    private func indexIDs(of store: CaptureHistoryStore) -> [UUID] {
        let url = store.directory.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PersistedCaptureEntry].self, from: data))?.map(\.id) ?? []
    }

    // MARK: The menu exists, six actions, Edit first

    /// Canary (S2): the cell's context menu lists the six honest actions in
    /// the decided order, Edit first — the owner asked for a right-click menu
    /// "opciones editar y otras mas".
    func testACellContextMenuListsTheSixActionsWithEditFirst() {
        let (model, _, entries) = makeModel(entries: 2)

        let items = model.menuItems(for: 0)

        XCTAssertEqual(items.map(\.title), [
            "Edit",
            "Copy Image",
            "Copy File Path",
            "Reveal in Finder",
            "Save a Copy…",
            "Delete",
        ])
        XCTAssertTrue(items.allSatisfy(\.isEnabled), "a wired menu over a healthy entry disables nothing")
        XCTAssertEqual(model.menuItems(for: 0)[0].action, .edit, "the first item is Edit")
        XCTAssertEqual(model.menuItems(for: 0).count, 6)
        XCTAssertNotEqual(entries.count, 0)
    }

    // MARK: - Round four S1: an acted action closes the sheet like a pick does

    /// The owner quote (S1): "cualquier haccion sobre el menu en el historial
    /// debe hace que se cierre el historial". Acting on a menu item closes
    /// the sheet the way a pick does — the one `onClose` seam the panel's
    /// hiding rests focus from. The model-level tests drive each action
    /// against the model's `perform` (the real route the cell's menu runs);
    /// the panel-level test pins the sheet and its focus hook.
    private final class CloseBox { var count = 0 }

    private func modelWithCloseWitness(entries: Int = 1) -> (model: CaptureHistoryPanelModel, store: CaptureHistoryStore, entryList: [PersistedCaptureEntry], closes: CloseBox) {
        let store = CaptureHistoryStore(directory: makeStoreDirectory())
        var added: [PersistedCaptureEntry] = []
        for index in 0..<entries {
            added.append(store.add(
                makeImage(width: 10 + index),
                date: Date(timeIntervalSince1970: TimeInterval(index + 1))
            ))
        }
        let closes = CloseBox()
        let model = CaptureHistoryPanelModel(
            store: store,
            onPick: { _ in },
            onClose: { closes.count += 1 },
            onEdit: { _ in })
        model.refresh()
        added.reverse() // newest first, the grid's order
        return (model, store, added, closes)
    }

    func testEditClosesTheSheetLikeAPickDoes() throws {
        let (model, _, entries, closes) = modelWithCloseWitness()

        model.perform(.edit, at: 0)

        XCTAssertEqual(closes.count, 1, "the edit closed the sheet like a pick")
        XCTAssertEqual(model.entries.count, entries.count, "an edit never touches the history it acted from")
    }

    func testCopyImageClosesTheSheetLikeAPickDoes() {
        let (model, _, _, closes) = modelWithCloseWitness()
        NSPasteboard.general.clearContents()

        model.perform(.copyImage, at: 0)

        XCTAssertTrue(NSPasteboard.general.types?.contains(.png) ?? false, "the copy really ran before the close")
        XCTAssertEqual(closes.count, 1, "the copy closed the sheet like a pick")
    }

    func testCopyFilePathClosesTheSheetLikeAPickDoes() {
        let (model, store, entries, closes) = modelWithCloseWitness()
        NSPasteboard.general.clearContents()

        model.perform(.copyFilePath, at: 0)

        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string), store.fileURL(for: entries[0])!.path,
            "the copy ran before the close")
        XCTAssertEqual(closes.count, 1, "the path copy closed the sheet like a pick")
    }

    func testRevealInFinderClosesTheSheetLikeAPickDoes() {
        let (model, store, entries, closes) = modelWithCloseWitness()
        var revealed: [URL] = []
        model.onReveal = { revealed.append($0) }

        model.perform(.revealInFinder, at: 0)

        XCTAssertEqual(revealed, [store.fileURL(for: entries[0])!], "the reveal really ran before the close")
        XCTAssertEqual(closes.count, 1, "the reveal closed the sheet like a pick")
    }

    func testSaveACopyClosesTheSheetLikeAPickDoes() throws {
        let (model, _, _, closes) = modelWithCloseWitness()
        let destination = makeStoreDirectory().appendingPathComponent("copy.png")
        model.onSaveCopy = { image in
            try! CaptureFile.data(for: image, format: .png)!.write(to: destination)
        }

        model.perform(.saveCopy, at: 0)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path), "the save really ran before the close")
        XCTAssertEqual(closes.count, 1, "the save closed the sheet like a pick")
    }

    /// Delete's confirmation gesture splits the rule in two: the arming click
    /// closes nothing (the confirm has nowhere to happen otherwise), and the
    /// confirming click removes the entry AND closes the sheet, like every
    /// other acted action.
    func testTheArmingDeleteKeepsTheSheetAndTheConfirmingDeleteClosesItLikeAPickDoes() {
        let (model, store, entries, closes) = modelWithCloseWitness(entries: 2)
        let target = entries[1]

        model.perform(.delete, at: 1) // arm
        XCTAssertEqual(closes.count, 0, "the arming click buttons nothing down: the confirm must happen here")
        XCTAssertTrue(model.isArmedForDelete(target))
        XCTAssertEqual(store.entries.count, 2, "the arm removed nothing")

        model.perform(.delete, at: 1) // confirm
        XCTAssertEqual(closes.count, 1, "the confirming delete closed the sheet like a pick")
        XCTAssertFalse(model.entries.map(\.id).contains(target.id), "the entry left with the close")
    }

    /// One action that refused — the stored file is gone, the reveal has
    /// nothing to reveal — changed nothing, so it closes nothing: the sheet
    /// closes over an ACTED action, not over a click that did nothing.
    func testARefusedActionClosesNothing() {
        let (model, store, entries, closes) = modelWithCloseWitness()
        try! FileManager.default.removeItem(
            at: capturesDirectory(of: store.directory).appendingPathComponent(entries[0].fileName)
        )

        model.perform(.revealInFinder, at: 0)

        XCTAssertEqual(closes.count, 0, "no action, no close")
    }

    func testTheMenusFirstItemRoutesThroughTheEditorHandoffSeam() {
        let (model, _, _) = makeModel(entries: 1)
        var handed: [CGImage] = []
        model.onEdit = { handed.append($0) }

        let item = model.menuItems(for: 0)[0]
        XCTAssertEqual(item.title, "Edit")
        item.perform()

        XCTAssertEqual(handed.count, 1)
        XCTAssertEqual(handed[0].width, 10, "the entry's own image goes to the editor")
        XCTAssertFalse(model.entries.isEmpty, "an Edit never touches the history it was offered from")
    }

    func testEditIsDisabledUntilAnEditorHandoffIsWired() {
        let store = CaptureHistoryStore(directory: makeStoreDirectory())
        _ = store.add(makeImage())
        let model = CaptureHistoryPanelModel(store: store, onPick: { _ in }, onClose: {})
        model.refresh()

        XCTAssertEqual(model.menuItems(for: 0)[0].title, "Edit")
        XCTAssertFalse(
            model.menuItems(for: 0)[0].isEnabled,
            "an Edit without a handoff is disabled, never offered and left silently failing"
        )
    }

    // MARK: Copy Image

    func testCopyImageMenuActionCopiesTheCapturesBytes() {
        let (model, _, _) = makeModel(entries: 1)
        NSPasteboard.general.clearContents()

        model.perform(.copyImage, at: 0)

        XCTAssertTrue(NSPasteboard.general.types?.contains(.png) ?? false)
        let png = try! XCTUnwrap(NSPasteboard.general.data(forType: .png))
        let bitmap = try! XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(bitmap.pixelsWide, 10)
        XCTAssertEqual(bitmap.pixelsHigh, 6)
    }

    // MARK: Copy File Path

    func testCopyFilePathCopiesTheStoresValidatedURL() {
        let (model, store, entries) = makeModel(entries: 1)
        let expected = try! XCTUnwrap(store.fileURL(for: entries[0]))
        NSPasteboard.general.clearContents()

        model.perform(.copyFilePath, at: 0)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), expected.path,
                       "the copied path IS the store's validated URL")
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        XCTAssertEqual(urls.first, expected)
    }

    // MARK: Reveal in Finder

    func testRevealInFinderReachesTheWorkspaceWithTheValidatedURL() {
        let (model, store, entries) = makeModel(entries: 1)
        var revealed: [URL] = []
        model.onReveal = { revealed.append($0) }

        model.perform(.revealInFinder, at: 0)

        XCTAssertEqual(revealed, [store.fileURL(for: entries[0])!],
                       "reveal carries exactly the store's validated URL")
    }

    // MARK: Save a Copy…

    func testSaveACopyLandsWhereTheSeamIsToldAndAddsNothingToTheHistories() throws {
        let (model, store, _) = makeModel(entries: 1)
        let toldWhere = makeStoreDirectory().appendingPathComponent("copy.png")
        // The seam is where the panel hands the bytes; the minimal honest
        // witness writes them where it is told, which is what the shipped
        // save panel does with the chosen URL.
        model.onSaveCopy = { image in
            try! CaptureFile.data(for: image, format: .png)!.write(to: toldWhere)
        }
        let count = store.entries.count

        model.perform(.saveCopy, at: 0)

        let data = try XCTUnwrap(Data(contentsOf: toldWhere))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, 10)
        XCTAssertEqual(bitmap.pixelsHigh, 6)
        XCTAssertEqual(store.entries.count, count, "a copy is a copy: no new capture in the store")
        XCTAssertEqual(model.entries.count, count, "no new capture in the panel either")
    }

    // MARK: Delete — two clicks, then everything follows

    func testDeleteAsksForAConfirmingSecondClickBeforeRemovingAnything() {
        let (model, store, entries) = makeModel(entries: 2)
        let target = entries[1]

        model.perform(.delete, at: 1)

        XCTAssertTrue(model.isArmedForDelete(target), "the first click only arms")
        XCTAssertEqual(model.entries.count, 2, "the arm removes nothing")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: capturesDirectory(of: store.directory).appendingPathComponent(target.fileName).path
        ), "the arm deletes no file")
        XCTAssertTrue(indexIDs(of: store).contains(target.id), "the arm rewrites no index")
        XCTAssertEqual(model.menuItems(for: 1).last?.title, "Confirm Delete",
                       "the armed cell's item says so")
    }

    func testTheConfirmingSecondDeleteRemovesEntryFileIndexAndThePanelsCountFollows() throws {
        let (model, store, entries) = makeModel(entries: 2)
        let target = entries[1]
        model.perform(.delete, at: 1) // arm

        model.perform(.delete, at: 1) // confirm

        XCTAssertFalse(model.entries.map(\.id).contains(target.id), "the entry is gone from the model")
        XCTAssertEqual(model.entries.count, 1, "the panel's count followed")
        XCTAssertEqual(model.selectionPosition, "1 / 1", "the header count follows too")
        let fileURL = store.fileURL(for: target)
        XCTAssertNil(fileURL)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: capturesDirectory(of: store.directory).appendingPathComponent(target.fileName).path
        ), "the file is gone from disk")
        XCTAssertFalse(indexIDs(of: store).contains(target.id), "the index no longer lists it")
        XCTAssertFalse(model.isArmedForDelete(target))
    }

    func testWalkingAwayFromACellDisarmsItsPendingDelete() {
        let (model, _, _) = makeModel(entries: 3)
        model.select(at: 2)

        model.perform(.delete, at: 2) // arm
        XCTAssertTrue(model.isArmedForDelete(model.entries[2]))

        model.moveSelection(1)
        XCTAssertNil(
            model.armedForDelete,
            "walking away disarms: the confirming click has to be an immediate one on the same cell"
        )
        XCTAssertEqual(model.menuItems(for: 2).last?.title, "Delete")
    }

    // MARK: No file, no promised action

    /// The store guards the disk; the menu mirrors it. When the stored file
    /// is gone the two file-carried actions are disabled in one, so a menu
    /// click can never fail after being offered — and Delete still works,
    /// because a broken file is exactly what Delete is for.
    func testWhenTheStoredFileIsGoneTheFileActionsAreDisabledAndDeleteStillWorks() {
        let (model, store, entries) = makeModel(entries: 1)
        let entry = entries[0]
        try! FileManager.default.removeItem(
            at: capturesDirectory(of: store.directory).appendingPathComponent(entry.fileName)
        )
        XCTAssertNil(store.fileURL(for: entry))

        let items = model.menuItems(for: 0)

        XCTAssertTrue(items.first(where: { $0.action == .copyFilePath })!.isEnabled == false)
        XCTAssertTrue(items.first(where: { $0.action == .revealInFinder })!.isEnabled == false)
        // And the guard holds even if something bypasses the menu:
        var revealed: [URL] = []
        model.onReveal = { revealed.append($0) }
        model.perform(.revealInFinder, at: 0)
        XCTAssertTrue(revealed.isEmpty, "no reveal without a validated URL")
        XCTAssertTrue(items.first(where: { $0.action == .delete })!.isEnabled)
        // The image is still cached from before the deletion, so Edit stays
        // enabled — and the cached image is what the editor would open.
        XCTAssertTrue(items.first(where: { $0.action == .edit })!.isEnabled)
        XCTAssertTrue(items.first(where: { $0.action == .copyImage })!.isEnabled)
    }
}
