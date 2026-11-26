import AppKit
import XCTest

@testable import Stare

/// S1: the card that appears after a capture carries a pin and a close, is
/// smaller than the plate it used to be, keeps floating above everything, and
/// a pinned card holds its spot — a later capture stacks next to the unpinned
/// ones and never moves it. These tests drive the real view and the real
/// controller: the buttons are the ones the user clicks, the dismiss policy is
/// the one the timer reads, and the stacking rule is the one the controller
/// applies.
@MainActor
final class CaptureCardTests: XCTestCase {
    /// The plate the card drew before S1, for a 1512×982 capture: the 260×170
    /// thumbnail cap plus the 8 pt backdrop on each side.
    private let oldPlate = CGSize(width: 276, height: 186)

    private func image(width: Int = 1512, height: Int = 982) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func view(
        onOpen: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) -> CaptureCardView {
        CaptureCardView(image: image(), onOpen: onOpen, onClose: onClose)
    }

    private func button(_ identifier: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.identifier?.rawValue == identifier { return button }
        for subview in view.subviews {
            if let found = button(identifier, in: subview) { return found }
        }
        return nil
    }

    // MARK: - The smaller plate

    func testThePlateIsSmallerThanTheOneItHadAndKeepsTheImageWhole() {
        let size = CaptureCardView.preferredSize(for: image())
        XCTAssertLessThan(size.width, oldPlate.width, "S1: the card must be smaller than the old plate")
        XCTAssertLessThan(size.height, oldPlate.height, "S1: the card must be smaller than the old plate")
        // The thumbnail keeps the capture's aspect: no crop, no letterbox.
        // The action row's strip rides under the picture, so the height the
        // picture fills is the card's minus both plates and the strip (C3/S3).
        let thumbnail = CGSize(
            width: size.width - CaptureCardView.plateInset * 2,
            height: size.height - CaptureCardView.plateInset * 2
                - CaptureCardView.rowStripHeight
        )
        XCTAssertEqual(thumbnail.width / thumbnail.height, 1512.0 / 982.0, accuracy: 0.02)
    }

    // MARK: - The two controls

    func testTheCardCarriesAPinAndACloseTheUserCanClick() {
        var closed = false
        let card = view(onClose: { closed = true })

        let pin = button(CaptureCardView.pinButtonIdentifier, in: card)
        let close = button(CaptureCardView.closeButtonIdentifier, in: card)
        XCTAssertNotNil(pin, "S1: the card must carry a pin")
        XCTAssertNotNil(close, "S1: the card must carry a close")

        close?.performClick(nil)
        XCTAssertTrue(closed, "clicking close dismisses the card")
    }

    func testClickingThePinTogglesThePinnedState() {
        let card = view()
        let pin = button(CaptureCardView.pinButtonIdentifier, in: card)
        XCTAssertEqual(card.isPinned, false)

        pin?.performClick(nil)
        XCTAssertTrue(card.isPinned, "S1: the pin fixes the card in place")
        pin?.performClick(nil)
        XCTAssertFalse(card.isPinned, "the pin can be released again")
    }

    func testAClickOnTheCardItselfStillOpensTheEditor() {
        // The controls sit on the plate; they must not eat the click that
        // opens the editor on the rest of it.
        var opened = false
        let card = view(onOpen: { opened = true })
        card.mouseDown(with: NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 20, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!)
        XCTAssertTrue(opened)
    }

    // MARK: - Dismiss policy

    func testAPinnedCardNeverAutoDismisses() {
        XCTAssertNil(
            CaptureCardView.autoDismissDelay(isPinned: true, isHovered: false, hasBeenHovered: true),
            "S1: a pinned card stays until it is closed"
        )
        XCTAssertNil(
            CaptureCardView.autoDismissDelay(isPinned: false, isHovered: true, hasBeenHovered: false),
            "hovering holds the card open"
        )
        XCTAssertEqual(
            CaptureCardView.autoDismissDelay(isPinned: false, isHovered: false, hasBeenHovered: false),
            CaptureCardView.dismissDelay
        )
        XCTAssertEqual(
            CaptureCardView.autoDismissDelay(isPinned: false, isHovered: false, hasBeenHovered: true),
            CaptureCardView.hoverDismissDelay
        )
    }

    // MARK: - Stacking

    func testTheStackStartsAtTheCornerMarginAndGrowsUpwards() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let card = CGSize(width: 202, height: 135)

        XCTAssertEqual(
            CaptureCardLayout.nextOrigin(visibleFrame: visible, cardSize: card, stackedHeight: 0),
            CGPoint(x: 1512 - 202 - CaptureCardLayout.margin, y: CaptureCardLayout.margin)
        )
        XCTAssertEqual(
            CaptureCardLayout.nextOrigin(
                visibleFrame: visible,
                cardSize: card,
                stackedHeight: 135 + CaptureCardLayout.gap
            ),
            CGPoint(
                x: 1512 - 202 - CaptureCardLayout.margin,
                y: CaptureCardLayout.margin + 135 + CaptureCardLayout.gap
            ),
            "S1: the second capture stacks above the first"
        )
    }

    /// S1 (owner's second pass): the stack is packed at all times. Pinning the
    /// newest card and letting the older ones go must drop the pinned card into
    /// the free slot at the bottom instead of leaving it hanging where the
    /// stack had grown to, and the next capture must land right above it.
    func testPinningTheNewestCardDropsItIntoTheFreeSlotWhenTheOthersGo() throws {
        try XCTSkipIf(NSScreen.main == nil, "needs a screen to place a card")
        let controller = CaptureCardController()
        let screen = try XCTUnwrap(NSScreen.main)

        for _ in 0..<4 { controller.show(image(), on: screen) }
        let pinned = try XCTUnwrap(controller.cards.last)
        // The slot is computed against the screen the card actually landed on, not
        // `NSScreen.main`: that one follows the key window, so on a desk with more
        // than one display it can answer with a different screen's frame between
        // the placement and this assertion, which read as the card being in the
        // wrong slot when it was not. Containment is asked of the card's centre, so
        // a card sitting on a shared edge still resolves to one screen.
        let centreOfCard = CGPoint(x: pinned.frame.midX, y: pinned.frame.midY)
        let cardScreen = try XCTUnwrap(
            NSScreen.screens.first { $0.visibleFrame.contains(centreOfCard) },
            "the pinned card has to land inside some screen's visible frame"
        )
        let bottomSlot = CaptureCardLayout.nextOrigin(
            visibleFrame: cardScreen.visibleFrame,
            cardSize: pinned.frame.size,
            stackedHeight: 0
        )
        XCTAssertGreaterThan(pinned.frame.origin.y, bottomSlot.y, "the fourth card starts higher up the stack")

        pinned.isPinned = true
        for card in controller.cards where card !== pinned {
            controller.dismiss(card)
        }

        XCTAssertEqual(controller.cards.count, 1)
        XCTAssertEqual(pinned.frame.origin.y, bottomSlot.y, accuracy: 0.5, "S1: the pinned card drops into the free slot")

        controller.show(image(), on: screen)
        let next = try XCTUnwrap(controller.cards.last)
        XCTAssertGreaterThan(next.frame.origin.y, pinned.frame.origin.y, "the next capture stacks right above it")
        XCTAssertEqual(
            next.frame.origin.y,
            bottomSlot.y + pinned.frame.height + CaptureCardLayout.gap,
            accuracy: 0.5,
            "no hole is left between them"
        )
    }

    func testTheControllerNeverEvictsAPinnedCard() throws {
        try XCTSkipIf(NSScreen.main == nil, "needs a screen to place a card")
        let controller = CaptureCardController()
        let screen = try XCTUnwrap(NSScreen.main)

        controller.show(image(), on: screen)
        let pinned = try XCTUnwrap(controller.cards.first)
        pinned.isPinned = true

        for _ in 0..<CaptureCardController.maximumUnpinnedCards {
            controller.show(image(), on: screen)
        }

        XCTAssertEqual(controller.cards.count, CaptureCardController.maximumUnpinnedCards + 1,
                       "S1: the cap counts the unpinned cards only")
        XCTAssertTrue(controller.cards.contains { $0 === pinned }, "S1: a pinned card is never evicted")
        XCTAssertEqual(
            pinned.level.rawValue,
            NSWindow.Level.screenSaver.rawValue + 2,
            "S1: the card stays above the palettes and the overlay"
        )
    }

    // MARK: - Cursor

    /// S1 (owner's second pass): neither the drawing overlay's crosshair nor
    /// the board's crosshair may leak onto a capture card — it is a result you
    /// click, not a canvas.
    func testThePointerOverTheCardIsTheArrowEvenWhileDrawing() {
        let card = view()
        NSCursor.crosshair.set()
        card.cursorUpdate(with: NSEvent())
        XCTAssertEqual(NSCursor.current, NSCursor.arrow, "the card answers with the arrow, not the tool's cursor")
    }
}
