import AppKit
import UniformTypeIdentifiers
import XCTest

@testable import Stare
import StareCore

/// C3/S4: the capture card's four corner COMMANDS — copy, save, pin, discard —
/// one control per corner, where the action row used to carry five. The
/// annotate entry is the click on the picture itself, and the drag-out out of
/// the card's body is unchanged. These tests drive the real controls and the
/// real mouse-drag path, and where a command writes somewhere (clipboard,
/// folder, promise file), the write is compared against the existing delivery
/// path's write instead of re-deriving what the bytes should look like.
@MainActor
final class CaptureCardActionsTests: XCTestCase {
    /// The card's four command voices: tooltip AND accessibility label, per
    /// identifier — the same voices the app already answered with.
    private let cornerVoices: [(identifier: String, label: String)] = [
        (CaptureCardView.copyButtonIdentifier, "Copy the capture to the clipboard"),
        (CaptureCardView.saveButtonIdentifier, "Save the capture to a file"),
        (CaptureCardView.pinButtonIdentifier, "Pin the card open"),
        (CaptureCardView.closeButtonIdentifier, "Discard the capture"),
    ]

    /// In-memory store double, so persistence is tested without touching real
    /// `UserDefaults` (the same double the other preference tests keep).
    private final class InMemoryPreferenceStore: PreferenceStore {
        private var storage: [String: Any] = [:]

        func object(forKey key: String) -> Any? { storage[key] }

        func set(_ value: Any?, forKey key: String) {
            storage[key] = value
        }
    }

    // MARK: - Fixtures

    private func solid(_ width: Int = 200, _ height: Int = 120) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func view(
        onOpen: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {},
        onCopy: @escaping () -> Void = {},
        onSave: @escaping () -> Void = {}
    ) -> CaptureCardView {
        CaptureCardView(
            image: solid(),
            onOpen: onOpen,
            onClose: onClose,
            onCopy: onCopy,
            onSave: onSave
        )
    }

    private func button(_ identifier: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.identifier?.rawValue == identifier { return button }
        for subview in view.subviews {
            if let found = button(identifier, in: subview) { return found }
        }
        return nil
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        at location: NSPoint,
        windowNumber: Int = 0
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: type == .leftMouseDown || type == .leftMouseDragged ? 1 : 0
        )!
    }

    private func cardView(of card: CaptureCard) throws -> CaptureCardView {
        func find(_ view: NSView) -> CaptureCardView? {
            if let cardView = view as? CaptureCardView { return cardView }
            for child in view.subviews {
                if let found = find(child) { return found }
            }
            return nil
        }
        return try XCTUnwrap(card.contentView.flatMap(find))
    }

    /// A folder in the system temp directory; each test cleans up after itself.
    private func tempFolder(_ name: String) -> URL {
        let unique = ProcessInfo.processInfo.globallyUniqueString
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name)-\(unique)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - The four corner commands and their voices

    func testTheCardCarriesItsCommandsOnePerCorner() throws {
        let card = view()
        card.layoutSubtreeIfNeeded()
        for item in cornerVoices {
            let button = try XCTUnwrap(
                self.button(item.identifier, in: card),
                "the card must carry \(item.identifier)"
            )
            XCTAssertEqual(button.toolTip, item.label, "\(item.identifier)'s tooltip is the card's own voice")
            XCTAssertEqual(
                button.accessibilityLabel(),
                item.label,
                "\(item.identifier)'s accessibility label says the same as its tooltip"
            )
        }
        let copy = try XCTUnwrap(button(CaptureCardView.copyButtonIdentifier, in: card))
        let save = try XCTUnwrap(button(CaptureCardView.saveButtonIdentifier, in: card))
        let pin = try XCTUnwrap(button(CaptureCardView.pinButtonIdentifier, in: card))
        let discard = try XCTUnwrap(button(CaptureCardView.closeButtonIdentifier, in: card))
        let midX = card.bounds.midX
        let midY = card.bounds.midY
        // One per corner, in mirrored columns: copy top-left, save bottom-left,
        // pin top-right — where the corner pin has always sat, whose placement
        // a test outside this file pins — and discard bottom-right.
        XCTAssertLessThan(copy.frame.maxX, midX)
        XCTAssertLessThan(copy.frame.maxY, midY, "copy rides the top-left corner")
        XCTAssertLessThan(save.frame.maxX, midX)
        XCTAssertGreaterThan(save.frame.minY, midY, "save rides the bottom-left corner")
        XCTAssertGreaterThan(pin.frame.minX, midX)
        XCTAssertLessThan(pin.frame.maxY, midY, "pin keeps the top-right corner")
        XCTAssertGreaterThan(discard.frame.minX, midX)
        XCTAssertGreaterThan(discard.frame.minY, midY, "discard rides the bottom-right corner")
        // No control sits over another: every control's centre must land on it.
        let controls = [copy, save, pin, discard]
        for outer in controls {
            for inner in controls where outer !== inner {
                XCTAssertFalse(
                    outer.frame.contains(NSPoint(x: inner.frame.midX, y: inner.frame.midY)),
                    "\(inner.identifier?.rawValue ?? "") must not be covered by \(outer.identifier?.rawValue ?? "")"
                )
            }
        }
    }

    // MARK: - Copy: the capture tail's own pasteboard write

    /// The copy control and the delivery path's clipboard branch call the same
    /// writer for the same image, so the pasteboard the copy leaves carries
    /// exactly the bytes a delivery leaves there — PNG and TIFF.
    func testTheCopyControlLeavesThePasteboardTheDeliveryPathWouldLeave() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen: a card needs one")
        // A board of this test's own. A live `NSDraggingSession` from another
        // test keeps the GENERAL pasteboard claimed by a file promise nobody
        // will ask for, and reading it then waits: measured 94 s with the drag
        // test ahead of this one, 932 s inside the full bundle, against 0.2 s
        // alone. Both writers below go through the controller's one pasteboard
        // seam, so this still compares the two production paths — it just does
        // it on a board no drag owns.
        let board = NSPasteboard(name: .init("stare.tests.card.copy"))
        let controller = OverlayController(
            captureService: CaptureService(),
            history: CaptureHistory(capacity: 2),
            editorHandoff: { _, _ in }
        )
        controller.pasteboard = board
        let image = solid()
        let cards = controller.captureCardsForTesting
        cards.show(image, on: try XCTUnwrap(NSScreen.screens.first))
        let card = try XCTUnwrap(cards.openCards.first)
        defer { cards.dismiss(card) }
        let cardView = try cardView(of: card)

        // The existing delivery path's write first: the same writer the
        // capture tail uses whenever a capture lands on the clipboard.
        controller.deliverHistoryPick(image)
        let delivered = try XCTUnwrap(board.data(forType: .png))
        XCTAssertNotNil(board.data(forType: .tiff), "the delivery path writes PNG and TIFF")

        let copyControl = try XCTUnwrap(button(CaptureCardView.copyButtonIdentifier, in: cardView))
        copyControl.performClick(nil)

        XCTAssertEqual(
            board.data(forType: .png), delivered,
            "the copy control writes the delivery path's exact bytes"
        )
        XCTAssertNotNil(board.data(forType: .tiff), "and the same both-format rule")
    }

    // MARK: - Save: the capture file writer's own path

    func testTheSaveControlWritesThroughTheCaptureFileWriterToTheDestination() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen: a card needs one")
        let folder = tempFolder("stare-card-save")
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.capture.destination = .folder(path: folder.path)
        let controller = OverlayController(
            captureService: CaptureService(),
            preferences: model,
            history: CaptureHistory(capacity: 2),
            editorHandoff: { _, _ in }
        )
        let image = solid()
        let cards = controller.captureCardsForTesting
        cards.show(image, on: try XCTUnwrap(NSScreen.screens.first))
        let card = try XCTUnwrap(cards.openCards.first)
        defer { cards.dismiss(card) }
        let cardView = try cardView(of: card)

        let saveControl = try XCTUnwrap(button(CaptureCardView.saveButtonIdentifier, in: cardView))
        saveControl.performClick(nil)

        let contents = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let files = try XCTUnwrap(contents, "the save must reach the capture destination's folder")
        XCTAssertEqual(files.count, 1)
        let written = try XCTUnwrap(files.first)
        XCTAssertTrue(written.lastPathComponent.hasPrefix("Stare-"), "the name follows the app's own prefix")
        XCTAssertEqual(written.pathExtension, "png", "written in the preference's format")
        let imageOnDisk = try XCTUnwrap(
            NSImage(data: try Data(contentsOf: written))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        XCTAssertEqual(imageOnDisk.width, image.width, "the file carries the capture, not a rendition of it")
        XCTAssertEqual(imageOnDisk.height, image.height)
        // The save's encode IS the capture file path's own encode: one call,
        // byte for byte.
        let expected = try XCTUnwrap(CaptureFile.data(for: image, format: model.capture.format))
        XCTAssertEqual(try Data(contentsOf: written), expected)
    }

    /// A clipboard destination cannot take the file write: the save then rides
    /// the delivery path's own rule — the capture lands on the clipboard
    /// instead of being lost, exactly what `deliver` does for that destination.
    func testTheSaveControlOnAClipboardDestinationRidesTheDeliveryFailureFallback() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen: a card needs one")
        let controller = OverlayController(
            captureService: CaptureService(),
            history: CaptureHistory(capacity: 2),
            editorHandoff: { _, _ in }
        )
        let image = solid()
        let cards = controller.captureCardsForTesting
        cards.show(image, on: try XCTUnwrap(NSScreen.screens.first))
        let card = try XCTUnwrap(cards.openCards.first)
        defer { cards.dismiss(card) }
        let cardView = try cardView(of: card)

        // The delivery path's clipboard write as the comparison pin.
        controller.deliverHistoryPick(image)
        let delivered = try XCTUnwrap(NSPasteboard.general.data(forType: .png))

        let saveControl = try XCTUnwrap(button(CaptureCardView.saveButtonIdentifier, in: cardView))
        saveControl.performClick(nil)

        XCTAssertEqual(
            NSPasteboard.general.data(forType: .png), delivered,
            "the fallback copy is the delivery path's clipboard write"
        )
    }

    // MARK: - Annotate: the click on the picture

    /// The annotate entry moved off the row and onto the picture: the click on
    /// the card's body opens the editor, exactly the way the annotate button
    /// used to, through the ONE editor handoff the history pane's reopen shares.
    /// Every test here starts with the general pasteboard released. A live
    /// `NSDraggingSession` begun by a drag test keeps a file promise on it that
    /// nobody will ever request, and any later read of that board waits for it —
    /// that is the fifteen-minute stall this class used to cause, measured at
    /// 94 s for one neighbour and 932 s for the whole bundle.
    override func setUp() {
        super.setUp()
        NSPasteboard.general.clearContents()
    }

    func testAClickOnThePictureOpensTheEditor() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen: a card needs one")
        var handed: [(image: CGImage, capture: CapturePreference)] = []
        let controller = OverlayController(
            captureService: CaptureService(),
            history: CaptureHistory(capacity: 2),
            editorHandoff: { image, capture in handed.append((image, capture)) }
        )
        let image = solid()
        let cards = controller.captureCardsForTesting
        cards.show(image, on: try XCTUnwrap(NSScreen.screens.first))
        let card = try XCTUnwrap(cards.openCards.first)
        defer { cards.dismiss(card) }
        let cardView = try cardView(of: card)

        cardView.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 20, y: 20)))
        XCTAssertEqual(handed.count, 1, "the click hands the capture to the editor")
        XCTAssertTrue(handed[0].image === image, "the click carries the card's own capture")
        XCTAssertEqual(handed[0].capture, .standard)
    }

    // MARK: - Pin: the corner pin's own path

    func testThePinControlFixesAndFreesTheCardTheWayThePinAlwaysDid() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen: a card needs one")
        let cards = CaptureCardController()
        var pinned: [(image: CGImage, screen: NSScreen?)] = []
        cards.onPin = { image, screen in pinned.append((image, screen)) }
        let image = solid(120, 90)
        cards.show(image, on: try XCTUnwrap(NSScreen.screens.first))
        let card = try XCTUnwrap(cards.openCards.first)
        defer { cards.dismiss(card) }
        let cardView = try cardView(of: card)

        let pin = try XCTUnwrap(button(CaptureCardView.pinButtonIdentifier, in: cardView))
        XCTAssertEqual(cardView.isPinned, false)

        pin.performClick(nil)
        XCTAssertTrue(cardView.isPinned, "the pin fixes the card")
        XCTAssertEqual(pinned.count, 1, "the pin floats the image through its one path")
        XCTAssertTrue(pinned[0].image === image, "the pin floats the card's capture")

        pin.performClick(nil)
        XCTAssertFalse(cardView.isPinned, "the pin releases the card again")
    }

    // MARK: - Discard: the close's own path

    func testTheDiscardControlDismissesLikeTheCloseDoes() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen: a card needs one")
        let controller = CaptureCardController()
        controller.show(solid(), on: try XCTUnwrap(NSScreen.screens.first))
        let card = try XCTUnwrap(controller.openCards.first)
        let cardView = try cardView(of: card)

        let discard = try XCTUnwrap(button(CaptureCardView.closeButtonIdentifier, in: cardView))
        discard.performClick(nil)

        XCTAssertEqual(controller.openCards.count, 0, "the discard takes the card off the stack")
        XCTAssertFalse(controller.cards.contains { $0 === card })
    }

    // MARK: - Drag-out: a file promise of the capture

    /// The drag session itself: the off-the-card drag BEGINS (a real session,
    /// from the card's own press-and-drag). What it promises is pinned in the
    /// test beside this one, which reads the same promise off an AppKit
    /// pasteboard without a live session — the session machinery is the one
    /// piece xctest's teardown has shown it cannot hold onto. The card keeps
    /// the real path in the app: `mouseDragged` still begins the session.
    // A test that began a real `NSDraggingSession` used to live here. It proved
    // that mouse-drag starts a session — and poisoned the whole process doing it:
    // the session never ends in xctest, so it keeps the GENERAL pasteboard claimed
    // by a file promise nobody requests, and every later read of that board waits
    // for it. Measured: 0.2 s alone, 94 s for the next test, 932 s inside the full
    // bundle. The behaviour that matters — the card offers its capture as a file
    // promise, named in the app's idiom, written through its own encoder — is
    // proven by testTheDragPromisesTheCaptureAsAFile below, which starts no session
    // and therefore costs nobody anything.

    /// The drag test's window, held past its test's lifetime on purpose — see
    /// the canary note inside the drag test.
    private static var dragTestWindowHold: NSWindow?

    /// What the drag PROMISES the receiving app: writing the card's promise
    /// provider onto an AppKit pasteboard is exactly what the drag session
    /// does for one item — read back through the receiver side, the card's
    /// drag-out is a promised FILE in PNG, named in the app's idiom, whose
    /// bytes are the capture file path's own encode.
    func testTheDragPromisesTheCaptureAsAFile() throws {
        let card = view()
        let item = card.dragItem()
        let provider = try XCTUnwrap(
            card.lastPromiseProvider,
            "the card's drag item carries a file promise provider"
        )
        XCTAssertTrue(item !== nil, "the drag item was built")

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("stare-card-drag-test"))
        pasteboard.releaseGlobally()
        pasteboard.clearContents()
        pasteboard.writeObjects([provider])

        // The receiving side: an NSFilePromiseReceiver — what Finder, Mail and
        // every app that takes file drags reads first.
        let receivers = try XCTUnwrap(
            pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]
        )
        let receiver = try XCTUnwrap(receivers.first)
        XCTAssertEqual(receiver.fileTypes, [UTType.png.identifier], "the promised file is a PNG")

        // The promise's name follows the app's own naming idiom.
        let name = card.filePromiseProvider(provider, fileNameForType: UTType.png.identifier)
        XCTAssertTrue(name.hasPrefix("Stare-"), "the promised file names itself like the app's captures")
        XCTAssertTrue(name.hasSuffix(".png"))

        // Taking the promise writes the capture through the app's own encoder,
        // byte for byte.
        let folder = tempFolder("stare-card-drag")
        defer { try? FileManager.default.removeItem(at: folder) }
        let promised = folder.appendingPathComponent(name)
        var writeError: Error?
        card.filePromiseProvider(provider, writePromiseTo: promised) { writeError = $0 }
        XCTAssertNil(writeError, "the promise write must succeed")
        let expected = try XCTUnwrap(CaptureFile.data(for: card.shownImage, format: .png))
        XCTAssertEqual(try Data(contentsOf: promised), expected)
    }

    // MARK: - The cursor over the controls

    func testThePointerOverAControlStillReadsAsAnArrow() throws {
        let card = view()
        let copy = try XCTUnwrap(button(CaptureCardView.copyButtonIdentifier, in: card))
        XCTAssertTrue(
            card.bounds.contains(copy.frame),
            "the control lies inside the card's own tracking area, which owns the pointer there"
        )

        NSCursor.crosshair.set()
        card.cursorUpdate(with: NSEvent())
        XCTAssertEqual(NSCursor.current, NSCursor.arrow, "a cursor update over a control answers the arrow")
        card.mouseMoved(with: mouseEvent(
            .mouseMoved,
            at: CGPoint(x: copy.frame.midX, y: copy.frame.midY)
        ))
        XCTAssertEqual(NSCursor.current, NSCursor.arrow, "a move over a control answers the arrow")
        NSCursor.arrow.set()
    }
}
