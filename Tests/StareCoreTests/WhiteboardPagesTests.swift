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

    func testAdoptReplacesOnlyTheCurrentPageSession() {
        let board = WhiteboardPages()
        board.adopt(drawnSession())
        board.selectNext()

        let replacement = drawnSession()
        board.adopt(replacement)
        XCTAssertEqual(board.pages[0].session.strokes.count, 1, "adopting touches only the current page")
        XCTAssertEqual(board.currentPage.session, replacement)
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
