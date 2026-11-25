import AppKit
import XCTest

@testable import Stare
import StareCore

/// B9: the pointer over a capture card is the arrow, on the board too. Three
/// attempts tried to win by DROPPING the canvas's moves, which never held on the
/// board; the card takes the moves now, so the canvas never hears them.
@MainActor
final class CaptureCardCursorTests: XCTestCase {
    private func solid(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    func testTheCardPanelTakesThePointersMoves() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen: a card needs one")
        let cards = CaptureCardController()
        cards.show(solid(40, 20), on: try XCTUnwrap(NSScreen.screens.first))
        let card = try XCTUnwrap(cards.openCards.first)
        defer {
            card.orderOut(nil)
            cards.dismiss(card)
        }
        XCTAssertTrue(
            card.acceptsMouseMovedEvents,
            "a card that does not take mouse-moved events hands them to the canvas underneath, which re-asserts the tool cursor"
        )
    }

    func testACardAnswersAMoveWithTheArrow() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "no screen: a card needs one")
        let cards = CaptureCardController()
        cards.show(solid(40, 20), on: try XCTUnwrap(NSScreen.screens.first))
        let card = try XCTUnwrap(cards.openCards.first)
        defer {
            card.orderOut(nil)
            cards.dismiss(card)
        }
        func findCardView(_ view: NSView) -> CaptureCardView? {
            if let cardView = view as? CaptureCardView { return cardView }
            for child in view.subviews {
                if let found = findCardView(child) { return found }
            }
            return nil
        }
        let view = try XCTUnwrap(card.contentView.flatMap(findCardView))

        // The canvas under the board holds a crosshair: the card has to answer
        // the move with the arrow anyway.
        NSCursor.crosshair.set()
        XCTAssertEqual(NSCursor.current, NSCursor.crosshair)

        view.mouseMoved(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: CGPoint(x: 5, y: 5), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: card.windowNumber,
            context: nil, eventNumber: 1, clickCount: 0, pressure: 0
        )))

        XCTAssertEqual(NSCursor.current, NSCursor.arrow, "a move over the card answers with the arrow")
        NSCursor.arrow.set()
    }
}
