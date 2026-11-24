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
        let thumbnail = CGSize(
            width: size.width - CaptureCardView.plateInset * 2,
            height: size.height - CaptureCardView.plateInset * 2
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
            CaptureCardLayout.nextOrigin(visibleFrame: visible, cardSize: card, stackedSizes: []),
            CGPoint(x: 1512 - 202 - CaptureCardLayout.margin, y: CaptureCardLayout.margin)
        )
        XCTAssertEqual(
            CaptureCardLayout.nextOrigin(
                visibleFrame: visible,
                cardSize: card,
                stackedSizes: [CGSize(width: 202, height: 135)]
            ),
            CGPoint(
                x: 1512 - 202 - CaptureCardLayout.margin,
                y: CaptureCardLayout.margin + 135 + CaptureCardLayout.gap
            ),
            "S1: the second capture stacks above the first"
        )
    }

    func testTheControllerNeverEvictsAPinnedCardAndAPinnedCardDoesNotPushNewOnes() throws {
        try XCTSkipIf(NSScreen.main == nil, "needs a screen to place a card")
        let controller = CaptureCardController()
        let screen = try XCTUnwrap(NSScreen.main)

        controller.show(image(), on: screen)
        controller.show(image(), on: screen)
        let pinned = try XCTUnwrap(controller.cards.first)
        pinned.isPinned = true
        let pinnedFrame = pinned.frame

        for _ in 0..<CaptureCardController.maximumUnpinnedCards {
            controller.show(image(), on: screen)
        }

        XCTAssertEqual(controller.cards.count, CaptureCardController.maximumUnpinnedCards + 1,
                       "S1: the cap counts the unpinned cards only")
        XCTAssertTrue(controller.cards.contains { $0 === pinned }, "S1: a pinned card is never evicted")
        XCTAssertEqual(pinned.frame, pinnedFrame, "S1: a pinned card keeps the spot it was left in")
        XCTAssertEqual(
            pinned.level.rawValue,
            NSWindow.Level.screenSaver.rawValue + 2,
            "S1: the card stays above the palettes and the overlay"
        )
    }
}
