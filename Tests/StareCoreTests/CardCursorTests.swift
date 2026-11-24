import CoreGraphics
import XCTest
@testable import StareCore

/// The pointer's arrow over a capture card (B9): one comparison, pinned so the
/// overlay's screen-wide crosshair cannot quietly take the card back.
final class CardCursorTests: XCTestCase {
    private let card = CGRect(x: 100, y: 200, width: 220, height: 150)

    func testThePointerInsideACardKeepsTheArrow() {
        XCTAssertTrue(CardCursor.isOverCard(CGPoint(x: 210, y: 275), cardFrames: [card]))
    }

    func testThePointerOutsideEveryCardLeavesTheDrawingCursor() {
        XCTAssertFalse(CardCursor.isOverCard(CGPoint(x: 99, y: 275), cardFrames: [card]))
        XCTAssertFalse(CardCursor.isOverCard(CGPoint(x: 210, y: 350), cardFrames: [card]))
    }

    func testNoCardsOnScreenMeansNothingToSkip() {
        XCTAssertFalse(CardCursor.isOverCard(CGPoint(x: 210, y: 275), cardFrames: []))
    }

    func testAnyCardCountsNotOnlyTheFirst() {
        let second = CGRect(x: 400, y: 500, width: 120, height: 90)
        XCTAssertTrue(CardCursor.isOverCard(CGPoint(x: 410, y: 510), cardFrames: [card, second]))
    }

    /// CoreGraphics rects are half-open: a card's origin belongs to it and the
    /// opposite edges do not, so the pointer on the far edge is already off.
    func testTheCardEdgesAreHalfOpen() {
        XCTAssertTrue(CardCursor.isOverCard(CGPoint(x: 100, y: 200), cardFrames: [card]))
        XCTAssertTrue(CardCursor.isOverCard(CGPoint(x: 319.5, y: 349.5), cardFrames: [card]))
        XCTAssertFalse(CardCursor.isOverCard(CGPoint(x: 320, y: 200), cardFrames: [card]))
        XCTAssertFalse(CardCursor.isOverCard(CGPoint(x: 210, y: 350), cardFrames: [card]))
    }
}
