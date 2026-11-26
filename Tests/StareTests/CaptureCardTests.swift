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

    /// A solid flat capture in the given colour, for the border renders whose
    /// pixels are sampled.
    private func flat(_ fill: CGColor) -> CGImage {
        let context = CGContext(
            data: nil, width: 200, height: 120, bitsPerComponent: 8,
            bytesPerRow: 200 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(fill)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
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
        // C3/S4: the card IS the picture — the dark plate (the black border)
        // and the action row's strip are gone — so the card's own size holds
        // the capture's aspect: no crop, no letterbox, no stretch.
        let aspect = size.width / size.height
        XCTAssertEqual(aspect, 1512.0 / 982.0, accuracy: 0.02)
    }

    // MARK: - The borders (C3/S4)

    /// The capture colour the border renders sample against: light, so the
    /// old dark plate and the old near-opaque blue border both stand out of it.
    private static let borderFixture = CGColor(srgbRed: 0.9, green: 0.85, blue: 0.8, alpha: 1)

    /// Renders the card's own `draw` into an offscreen bitmap so the border
    /// tests measure pixels, not constants. The card's own painting is
    /// symmetric about its horizontal centre, so both horizontal edges are
    /// sampled and the bitmap's row order cannot matter.
    private func renderedPixels(of card: CaptureCardView) throws -> NSBitmapImageRep {
        let scale: CGFloat = 4
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(card.bounds.width * scale),
                pixelsHigh: Int(card.bounds.height * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: NSColorSpaceName.deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        rep.size = card.bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        card.draw(card.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// The pixel `depth` points inside from one horizontal edge, mid-width.
    private func pixel(
        _ rep: NSBitmapImageRep,
        depth: CGFloat,
        fromTop: Bool
    ) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let scale = CGFloat(rep.pixelsWide) / rep.size.width
        let offset = Int((depth * scale).rounded())
        let x = rep.pixelsWide / 2
        let y = fromTop ? offset : rep.pixelsHigh - 1 - offset
        let color = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        return (color.redComponent, color.greenComponent, color.blueComponent)
    }

    private func distance(
        _ a: (r: CGFloat, g: CGFloat, b: CGFloat),
        _ b: (CGFloat, CGFloat, CGFloat)
    ) -> CGFloat {
        let dr = (a.r - b.0) * (a.r - b.0)
        let dg = (a.g - b.1) * (a.g - b.1)
        let db = (a.b - b.2) * (a.b - b.2)
        return (dr + dg + db).squareRoot()
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

    // MARK: - The cursor

    /// S1 (owner's second pass): neither the drawing overlay's crosshair nor
    /// the board's crosshair may leak onto a capture card — it is a result you
    /// click, not a canvas.
    func testThePointerOverTheCardIsTheArrowEvenWhileDrawing() {
        let card = view()
        NSCursor.crosshair.set()
        card.cursorUpdate(with: NSEvent())
        XCTAssertEqual(NSCursor.current, NSCursor.arrow, "the card answers with the arrow, not the tool's cursor")
    }

    // MARK: - The borders (C3/S4)

    /// The black border the card used to wear goes, and the picture runs to
    /// the card's edge. Where the border lived: `CaptureCardView.draw(_:)` —
    /// the old card painted `CGColor(gray: 0.08, alpha: 0.92)` over the plate
    /// inset by 1 pt, behind a thumbnail inset 6 pt more, and THAT dark
    /// backdrop read as the card's black border. Measured, not assumed.
    func testTheCardsBorderIsGoneAndThePictureRunsToTheEdge() throws {
        let card = CaptureCardView(image: flat(Self.borderFixture), onOpen: {}, onClose: {})
        let rep = try renderedPixels(of: card)
        let expected: (CGFloat, CGFloat, CGFloat) = (0.9, 0.85, 0.8)
        // Right at the edge the old card showed either the dark plate or the
        // 1 pt rim where it started; depth 0.5, 2 and 5 pt all sat inside the
        // dark backdrop (and the picture stopped 6 pt short). Now every one of
        // them is the capture's own colour, from both edges.
        for depth in [CGFloat(0.5), 2, 5] {
            for fromTop in [true, false] {
                let sampled = try pixel(rep, depth: depth, fromTop: fromTop)
                XCTAssertLessThan(
                    distance(sampled, expected), 0.05,
                    "at \(depth) pt from the \(fromTop ? "top" : "bottom") edge the picture is the capture, not a border"
                )
            }
        }
        // And nowhere does the old plate's dark colour survive.
        let deepSample = try pixel(rep, depth: 3, fromTop: false)
        XCTAssertGreaterThan(
            distance(deepSample, (0.08, 0.08, 0.08)), 0.25,
            "no dark plate is drawn anywhere near the edges"
        )
    }

    /// A pinned card's border becomes subtle. Where it lived and what it is:
    /// `CaptureCardView.draw(_:)` again — the old pin stroke was 2 pt wide at
    /// alpha 0.95 in `CGColor(red: 0.36, green: 0.66, blue: 1, ...)`. The new
    /// line is 1 pt, and its weight shows at a much lower alpha: measured by
    /// sampling the pinned card's own pixels, so the constants cannot drift
    /// away from the render.
    func testThePinnedBorderIsTheSubtlerOne() throws {
        let card = CaptureCardView(image: flat(Self.borderFixture), onOpen: {}, onClose: {})
        card.isPinned = true
        let rep = try renderedPixels(of: card)
        let fixture: (CGFloat, CGFloat, CGFloat) = (0.9, 0.85, 0.8)
        // Subtlety, at the edge: still a border — the fixture does not show
        // through untouched — but the capture's red shows through far more
        // than the old 0.95 weight allowed (its blend read red 0.386; a 0.45
        // weight reads 0.657 against this fixture).
        for fromTop in [true, false] {
            let rim = try pixel(rep, depth: 0.5, fromTop: fromTop)
            XCTAssertGreaterThan(
                rim.r, 0.5,
                "the border's weight must let the capture show through; the old 0.95 blend reads 0.386 at this depth"
            )
            XCTAssertGreaterThan(
                distance(rim, fixture), 0.1,
                "and the border is still there: the rim is not the bare capture either"
            )
            // Only 1 pt in, the border has ended: the new weight is 1 pt where
            // the old was 2 pt, which painted this depth a solid blue.
            let deeper = try pixel(rep, depth: 1.5, fromTop: fromTop)
            XCTAssertLessThan(
                distance(deeper, fixture), 0.05,
                "the border is 1 pt: at 1.5 pt the capture is unbordered"
            )
        }
    }
}
