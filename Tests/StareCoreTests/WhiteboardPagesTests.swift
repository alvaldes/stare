import AppKit
import CoreGraphics
import XCTest

import StareCore

/// The whiteboard page model T6/S3: every page owns its marks, its background
/// colour and its pan offset; going past the last page creates one, going back
/// at the first stays put, and the numbered sequence restarts per page.
final class WhiteboardPagesTests: XCTestCase {
    private func drawnSession(stepCount: Int = 0) -> DrawingSession {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 10, y: 10), tool: .pen, ink: .red)
        session.extend(to: CGPoint(x: 40, y: 40))
        session.commit()
        for _ in 0..<stepCount {
            session.begin(at: CGPoint(x: 5, y: 5), tool: .number, ink: .orange)
            session.commit()
        }
        return session
    }

    /// Page 1 becomes black with one mark, then the board moves to page 2.
    private func goToPage2StartingFromBlack(_ board: WhiteboardPages) {
        board.toggleBackground() // page 1: white -> black
        board.adopt(drawnSession())
        board.selectNext()
        XCTAssertEqual(board.currentPage.background, .black, "a new page inherits the background")
    }

    func testMarkStaysOnItsOwnPage() {
        let board = WhiteboardPages()
        board.adopt(drawnSession())

        board.selectNext()
        XCTAssertEqual(board.count, 2)
        XCTAssertTrue(board.currentPage.session.strokes.isEmpty, "a mark on page 1 must not appear on page 2")

        board.selectPrevious()
        XCTAssertEqual(board.currentPage.session.strokes.count, 1, "marks come back with their page")
    }

    func testGoingPastTheLastPageCreatesOneAndGoingBackAtTheFirstStaysPut() {
        let board = WhiteboardPages()
        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(board.currentIndex, 0)

        // ‹ at page 1 must not create a page behind the user.
        XCTAssertFalse(board.selectPrevious())
        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(board.currentIndex, 0)

        // › past the last page creates exactly one page and moves to it.
        XCTAssertTrue(board.selectNext())
        XCTAssertEqual(board.count, 2)
        XCTAssertEqual(board.currentIndex, 1)

        // › inside the existing range only moves: page 4 of 4 stays 4 of 4, and
        // ‹ must not create pages behind the user.
        XCTAssertTrue(board.selectNext())
        XCTAssertTrue(board.selectNext())
        XCTAssertEqual(board.count, 4)
        XCTAssertEqual(board.currentIndex, 3)
        XCTAssertTrue(board.selectPrevious())
        XCTAssertEqual(board.count, 4, "using ‹ must not create pages")
        XCTAssertEqual(board.currentIndex, 2)
    }

    func testNewPageInheritsTheBackgroundOfThePageYouCameFrom() {
        let board = WhiteboardPages()
        goToPage2StartingFromBlack(board)
        XCTAssertEqual(board.currentPage.background, .black)
    }

    func testBackgroundToggleFlipsOnlyTheCurrentPage() {
        let board = WhiteboardPages()
        goToPage2StartingFromBlack(board)

        // ⌘B on page 2: black flips to white, page 1 stays black.
        board.toggleBackground()
        XCTAssertEqual(board.currentPage.background, .white)
        XCTAssertEqual(board.pages[0].background, .black)
    }

    func testNumberedStepsRestartOnEachPage() {
        let board = WhiteboardPages()
        board.adopt(drawnSession(stepCount: 2))
        XCTAssertEqual(board.currentPage.session.strokes.compactMap(\.stepNumber), [1, 2])

        board.selectNext()
        board.adopt(drawnSession(stepCount: 1))
        XCTAssertEqual(board.currentPage.session.strokes.compactMap(\.stepNumber), [1], "the sequence restarts on a new page")
    }

    func testPanOffsetIsPerPageAndPreservedWhenSwitching() {
        let board = WhiteboardPages()
        board.setOffset(CGSize(width: 60, height: 40))
        board.adopt(drawnSession())
        board.selectNext()

        // Panning page 2 must not touch page 1's offset.
        board.pan(by: CGSize(width: -25, height: 10))
        XCTAssertEqual(board.pages[0].offset, CGSize(width: 60, height: 40))
        XCTAssertEqual(board.currentPage.offset, CGSize(width: -25, height: 10))

        board.selectPrevious()
        XCTAssertEqual(board.currentPage.offset, CGSize(width: 60, height: 40), "each page keeps its own pan offset")
    }

    // T12/S9: deleting the current page drops only that page; the others and
    // their marks stay.
    func testDeleteCurrentPageDropsOnlyThatPageAndKeepsTheRest() {
        let board = WhiteboardPages()
        let page1 = drawnSession()
        board.adopt(page1)
        board.selectNext()
        let page2 = drawnSession()
        board.adopt(page2)

        XCTAssertTrue(board.deleteCurrentPage())
        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(board.currentIndex, 0)
        XCTAssertEqual(board.pages[0].session, page1, "the other page keeps its marks")
        XCTAssertFalse(board.pages[0].session.strokes.isEmpty)
    }

    // T12/S9: deleting the page the view is on hands the next page the slot,
    // and deleting the last page moves the current index back into range.
    func testDeleteCurrentPageKeepsTheIndexInRange() {
        let board = WhiteboardPages()
        let page1 = drawnSession()
        board.adopt(page1)
        board.selectNext()
        let page2 = drawnSession()
        board.adopt(page2)

        // Current is the last page: after the delete the index must land on the
        // new last page, never out of range.
        XCTAssertTrue(board.deleteCurrentPage())
        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(board.currentIndex, 0)
        XCTAssertEqual(board.pages[0].session, page1)

        // Deleting from the middle keeps the following page in the same slot.
        board.selectNext()
        let page2b = drawnSession()
        board.adopt(page2b)
        board.selectNext()
        let page3 = drawnSession()
        board.adopt(page3)
        XCTAssertEqual(board.count, 3)
        XCTAssertEqual(board.currentIndex, 2)
        XCTAssertTrue(board.select(index: 1))
        XCTAssertTrue(board.deleteCurrentPage())
        XCTAssertEqual(board.count, 2)
        XCTAssertEqual(board.currentIndex, 1)
        XCTAssertEqual(board.pages[1].session, page3, "the page after the deleted one takes its slot")
        XCTAssertEqual(board.pages[0].session, page1)
    }

    // T12/S9: the board can never go empty — with one page the delete is
    // refused, and the page keeps everything it had.
    func testDeleteIsRefusedWhenOnlyOnePageRemains() {
        let board = WhiteboardPages()
        let only = drawnSession()
        board.adopt(only)

        XCTAssertFalse(board.deleteCurrentPage())
        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(board.currentIndex, 0)
        XCTAssertEqual(board.pages[0].session, only)
        XCTAssertEqual(board.pages[0].background, .white)
    }

    // T12/S9: moving the current page reorders the array, keeps the same page
    // current, and per-page state (background, offset, marks, identity) moves
    // with it. The pages have distinct backgrounds and offsets so the test can
    // actually tell them apart after the swap.
    func testMoveLeftAndRightFollowTheCurrentPage() {
        let board = WhiteboardPages()
        board.setOffset(CGSize(width: 30, height: 20))
        let page1 = drawnSession()
        board.adopt(page1) // page 1: white, offset (30, 20)

        board.selectNext()
        board.toggleBackground() // page 2: white -> black
        board.setOffset(CGSize(width: 5, height: 5))
        let page2 = drawnSession()
        board.adopt(page2)

        board.selectNext()
        board.toggleBackground() // page 3: black -> white
        board.setOffset(CGSize(width: 70, height: 40))
        let page3 = drawnSession()
        board.adopt(page3)

        // Move page 3 right at the last position: refused, nothing changes.
        XCTAssertFalse(board.moveCurrentPageRight())
        XCTAssertEqual(board.count, 3)
        XCTAssertEqual(board.currentIndex, 2)

        // Move page 3 left: it swaps with page 2 and stays current, carrying
        // its own background, offset and marks.
        XCTAssertTrue(board.moveCurrentPageLeft())
        XCTAssertEqual(board.currentIndex, 1)
        XCTAssertEqual(board.count, 3)
        XCTAssertEqual(board.currentPage.session, page3, "the moved page is still the current one")
        XCTAssertEqual(board.currentPage.background, .white, "the moved page keeps its own background")
        XCTAssertEqual(board.currentPage.offset, CGSize(width: 70, height: 40), "the moved page keeps its own offset")
        XCTAssertEqual(board.pages[0].session, page1)
        XCTAssertEqual(board.pages[0].background, .white)
        XCTAssertEqual(board.pages[0].offset, CGSize(width: 30, height: 20))
        XCTAssertEqual(board.pages[2].session, page2, "the neighbour took the old slot")
        XCTAssertEqual(board.pages[2].background, .black)
        XCTAssertEqual(board.pages[2].offset, CGSize(width: 5, height: 5))

        // Move page 3 (current) left again onto the first position.
        XCTAssertTrue(board.moveCurrentPageLeft())
        XCTAssertEqual(board.currentIndex, 0)
        XCTAssertEqual(board.pages[0].session, page3)
        XCTAssertEqual(board.pages[0].offset, CGSize(width: 70, height: 40), "the offset travels with the page")
        XCTAssertEqual(board.pages[1].session, page1)

        // Move left at the first position: refused.
        XCTAssertFalse(board.moveCurrentPageLeft())
        XCTAssertEqual(board.currentIndex, 0)

        // Move right twice lands page 3 at the end again, marks intact.
        XCTAssertTrue(board.moveCurrentPageRight())
        XCTAssertTrue(board.moveCurrentPageRight())
        XCTAssertEqual(board.currentIndex, 2)
        XCTAssertEqual(board.pages[2].session, page3)
        XCTAssertEqual(board.pages[2].session.strokes.map(\.id), page3.strokes.map(\.id), "mark identity survives the reorder")
    }

    // T12/S9: selecting by index moves the presentation and refuses anything
    // out of range, so `currentIndex` can never leave the array.
    func testSelectIndexMovesAndRefusesOutOfRange() {
        let board = WhiteboardPages()
        board.adopt(drawnSession())
        board.selectNext()
        let page2 = drawnSession()
        board.adopt(page2)
        board.selectNext()
        let page3 = drawnSession()
        board.adopt(page3)

        XCTAssertTrue(board.select(index: 0))
        XCTAssertEqual(board.currentIndex, 0)
        XCTAssertTrue(board.select(index: 2))
        XCTAssertEqual(board.currentPage.session, page3)
        XCTAssertTrue(board.select(index: 1))
        XCTAssertEqual(board.currentIndex, 1)

        XCTAssertFalse(board.select(index: -1))
        XCTAssertFalse(board.select(index: 3))
        XCTAssertEqual(board.currentIndex, 1, "a refused select leaves the board alone")
    }

    func testAdoptReplacesOnlyTheCurrentPageSession() {
        let board = WhiteboardPages()
        board.adopt(drawnSession())
        board.selectNext()

        let replacement = drawnSession()
        board.adopt(replacement)
        XCTAssertEqual(board.pages[0].session.strokes.count, 1, "adopting touches only the current page")
        XCTAssertEqual(board.currentPage.session, replacement)
    }

    // T4/S4: the follow-the-system choice is a value of the page background
    // itself, resolved against the appearance wherever a concrete colour is
    // consumed (paint, capture, ⌘B).
    func testSystemResolvesWhiteInLightAndBlackInDark() {
        XCTAssertEqual(BoardBackground.system.resolved(isDark: false), .white, "light mode shows a white page")
        XCTAssertEqual(BoardBackground.system.resolved(isDark: true), .black, "dark mode shows a black page")
    }

    func testExplicitChoicesIgnoreTheAppearance() {
        XCTAssertEqual(BoardBackground.white.resolved(isDark: true), .white)
        XCTAssertEqual(BoardBackground.black.resolved(isDark: false), .black)
    }

    func testSystemCaptureBaseFollowsTheAppearance() throws {
        let light = try XCTUnwrap(BoardBackground.system.captureBase(width: 8, height: 8, isDark: false))
        let dark = try XCTUnwrap(BoardBackground.system.captureBase(width: 8, height: 8, isDark: true))
        for (image, expectBlack) in [(light, false), (dark, true)] {
            let representation = NSBitmapImageRep(cgImage: image)
            let colour = representation.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            colour?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            XCTAssertEqual(alpha, 1, accuracy: 0.01, "the base must be opaque, never transparent")
            let sum = red + green + blue
            if expectBlack {
                XCTAssertEqual(sum, 0, accuracy: 0.01, "a system page in dark mode captures black")
            } else {
                XCTAssertEqual(sum, 3, accuracy: 0.01, "a system page in light mode captures white")
            }
        }
    }

    func testToggleBackgroundOnSystemPageStartsFromTheVisibleColour() {
        // ⌘B keeps flipping between white and black: a system page resolves
        // against the appearance first, so the flip starts from the colour the
        // user actually sees and lands on the opposite explicit choice.
        let darkBoard = WhiteboardPages(background: .system)
        darkBoard.toggleBackground(isDark: true)
        XCTAssertEqual(darkBoard.currentPage.background, .white, "dark mode shows black, ⌘B flips it to white")

        let lightBoard = WhiteboardPages(background: .system)
        lightBoard.toggleBackground(isDark: false)
        XCTAssertEqual(lightBoard.currentPage.background, .black, "light mode shows white, ⌘B flips it to black")
    }

    func testSystemPageKeepsItsChoiceWhileOthersFlip() {
        // The page keeps its identity: flipping other pages and moving between
        // pages never turns a system page into an explicit colour.
        let board = WhiteboardPages(background: .system)
        board.selectNext()
        board.toggleBackground(isDark: false) // page 2 becomes explicitly black
        XCTAssertEqual(board.currentPage.background, .black)
        board.selectPrevious()
        XCTAssertEqual(board.currentPage.background, .system, "page 1 still follows the system")
        board.toggleBackground(isDark: true) // ⌘B on page 1 makes it explicit
        XCTAssertEqual(board.currentPage.background, .white)
    }

    func testNewPageInheritsTheSystemChoice() {
        let board = WhiteboardPages(background: .system)
        board.selectNext()
        XCTAssertEqual(board.currentPage.background, .system, "a new page inherits the page it came from")
    }

    func testCaptureBaseIsASolidOpaqueImageOfTheBackground() throws {
        let base = try XCTUnwrap(
            BoardBackground.black.captureBase(width: 20, height: 10),
            "a page's capture base must exist at display pixel size"
        )
        XCTAssertEqual(base.width, 20)
        XCTAssertEqual(base.height, 10)
        let representation = NSBitmapImageRep(cgImage: base)
        let colour = representation.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        colour?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(alpha, 1, accuracy: 0.01, "the base must be opaque, never transparent")
        XCTAssertEqual(red + green + blue, 0, accuracy: 0.01, "a black page's base must be black")
    }
}
