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

    // MARK: - T5/S5: the page ↔ view mapping

    /// The mapping lives in one place in StareCore (`BoardTransform`):
    /// `view = (page − offset) × zoom`, so `page = view / zoom + offset`. Zoom 1
    /// must reduce to the old translation-only rule the panned pages kept.
    func testPageAndViewPointsRoundTripAtSeveralZoomsAndOffsets() {
        let pagePoints = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 37.5, y: 41.25),
            CGPoint(x: -80, y: 200),
            CGPoint(x: 1_000.5, y: -250),
        ]
        let transforms = [
            BoardTransform.identity,
            BoardTransform(offset: CGSize(width: 100, height: 60), zoom: 1),
            BoardTransform(offset: .zero, zoom: 2),
            BoardTransform(offset: CGSize(width: 125, height: -30), zoom: 0.25),
            BoardTransform(offset: CGSize(width: -1, height: 17.5), zoom: 8),
        ]
        for transform in transforms {
            for page in pagePoints {
                let back = transform.point(toPage: transform.point(fromPage: page))
                XCTAssertEqual(back.x, page.x, accuracy: 1e-9, "x round trip at zoom \(transform.zoom)")
                XCTAssertEqual(back.y, page.y, accuracy: 1e-9, "y round trip at zoom \(transform.zoom)")
            }
            let pageRect = CGRect(x: 10, y: 20, width: 300, height: 150)
            let backRect = transform.rect(toPage: transform.rect(fromPage: pageRect))
            XCTAssertEqual(backRect, pageRect, "rect round trip at zoom \(transform.zoom)")
        }
        // Zoom 1 is exactly the old rule: page = view + offset.
        let translationOnly = BoardTransform(offset: CGSize(width: 40, height: 25), zoom: 1)
        XCTAssertEqual(
            translationOnly.point(toPage: CGPoint(x: 100, y: 200)),
            CGPoint(x: 140, y: 225),
            "zoom 1 must keep the panned page's stored-point rule"
        )
    }

    /// The anchoring rule: zooming keeps the page point under the view anchor
    /// exactly where it was, so drawing follows the pointer no matter what the
    /// zoom does.
    func testZoomingAnchoredAtAViewPointKeepsItsPagePointPut() {
        let anchors = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 200, y: 150),
            CGPoint(x: 513.5, y: 287.25),
        ]
        let zooms: [CGFloat] = [1, 2, 0.25]
        let targets: [CGFloat] = [2, 0.25, 8, 1.25]
        for zoom in zooms {
            let before = BoardTransform(offset: CGSize(width: 60, height: -12), zoom: zoom)
            for anchor in anchors {
                let pageUnderAnchor = before.point(toPage: anchor)
                for target in targets {
                    let after = before.zoomed(to: target, anchoredAt: anchor)
                    let kept = after.point(toPage: anchor)
                    XCTAssertEqual(
                        kept.x, pageUnderAnchor.x, accuracy: 1e-9,
                        "the page point under the anchor moved zooming \(zoom)→\(target) at \(anchor)"
                    )
                    XCTAssertEqual(
                        kept.y, pageUnderAnchor.y, accuracy: 1e-9,
                        "the page point under the anchor moved zooming \(zoom)→\(target) at \(anchor)"
                    )
                }
            }
        }
    }

    /// Zoom never boxes you in a corner of the range, and a target outside the
    /// range lands on its boundary without moving the content (the anchor
    /// invariant still holds — a clamped zoom keeps its own page point).
    func testZoomClampsToTheStatedRange() {
        let start = BoardTransform.identity
        let tooFar = start.zoomed(to: 99, anchoredAt: CGPoint(x: 100, y: 100))
        XCTAssertEqual(tooFar.zoom, BoardTransform.maxZoom, "the zoom range top")
        let tooLittle = start.zoomed(to: 0.01, anchoredAt: CGPoint(x: 100, y: 100))
        XCTAssertEqual(tooLittle.zoom, BoardTransform.minZoom, "the zoom range bottom")
        XCTAssertEqual(tooFar.point(toPage: CGPoint(x: 100, y: 100)).x, 100, "a clamped zoom still anchors")
        // Pushing past an already-clamped end is a no-op: nothing moves.
        let again = tooFar.zoomed(to: 99, anchoredAt: CGPoint(x: 100, y: 100))
        XCTAssertEqual(again, tooFar)
        XCTAssertEqual(start.zoomed(to: 1, anchoredAt: CGPoint(x: 300, y: 200)), start, "zoom 1→1 changes nothing")
    }

    /// Zoom is a per-page value exactly like the pan offset: switching pages
    /// never carries one page's view into another, and moving a page keeps it.
    func testZoomIsPerPageLikeThePanOffset() {
        let board = WhiteboardPages()
        XCTAssertTrue(board.zoom(to: 2, anchoredAt: CGPoint(x: 300, y: 200)))
        XCTAssertEqual(board.currentPage.zoom, 2)
        board.selectNext()
        XCTAssertEqual(board.currentPage.zoom, 1, "a new page starts at zoom 1")
        board.pan(by: CGSize(width: 20, height: 0))
        XCTAssertTrue(board.zoom(to: 0.5, anchoredAt: .zero))
        XCTAssertEqual(board.currentPage.zoom, 0.5)
        XCTAssertEqual(
            board.currentPage.offset, CGSize(width: 20, height: 0),
            "anchored at the view origin the offset never moves: the page point under it stays"
        )
        board.selectPrevious()
        XCTAssertEqual(board.currentPage.zoom, 2, "each page keeps its own zoom")
        XCTAssertEqual(board.currentPage.offset, CGSize(width: 150, height: 100), "the anchor's own pan stays")
        board.moveCurrentPageRight()
        XCTAssertEqual(board.currentPage.zoom, 2, "the zoom travels with the page")
    }

    /// ⌘0 puts pan and zoom back together: offset zero and zoom 1, nothing else
    /// touched (marks and background survive untouched).
    func testResetViewRestoresPanAndZoomTogether() {
        let sessionBefore = drawnSession()
        let board = WhiteboardPages(background: .black)
        board.adopt(sessionBefore)
        board.pan(by: CGSize(width: 80, height: 50))
        board.zoom(to: 3, anchoredAt: CGPoint(x: 10, y: 10))

        board.resetView()
        XCTAssertEqual(board.currentPage.offset, .zero)
        XCTAssertEqual(board.currentPage.zoom, 1)
        XCTAssertEqual(board.currentPage.session, sessionBefore, "the marks never move")
        XCTAssertEqual(board.currentPage.background, .black, "the background never changes")
    }

    // MARK: - S1: ⌘ + scroll zoom

    /// One wheel notch's worth of delta zooms in one direction and out the
    /// other, continuously scaled between the keyboard steps.
    func testCommandScrollZoomsInForPositiveDeltaAndOutForNegative() {
        let anchor = CGPoint(x: 300, y: 200)
        let up = BoardTransform.identity.zoomed(forScrollDelta: 10, isZooming: true, anchoredAt: anchor)
        let down = BoardTransform.identity.zoomed(forScrollDelta: -10, isZooming: true, anchoredAt: anchor)
        XCTAssertGreaterThan(up.zoom, 1, "scrolling up (⌘ held) zooms in")
        XCTAssertLessThan(down.zoom, 1, "scrolling down (⌘ held) zooms out")
        // The rule is continuous in the delta: a bigger scroll zooms further.
        let further = BoardTransform.identity.zoomed(forScrollDelta: 30, isZooming: true, anchoredAt: anchor)
        XCTAssertGreaterThan(further.zoom, up.zoom, "a bigger delta zooms further")
        // A zero delta changes nothing.
        XCTAssertEqual(
            BoardTransform.identity.zoomed(forScrollDelta: 0, isZooming: true, anchoredAt: anchor),
            BoardTransform.identity,
            "a zero delta must not zoom"
        )
    }

    /// The scroll zoom is anchored like every other zoom: the page point under
    /// the view anchor never moves.
    func testCommandScrollAnchorsTheViewPointLikeEveryOtherZoom() {
        let anchors = [CGPoint(x: 0, y: 0), CGPoint(x: 640, y: 420), CGPoint(x: 123.5, y: 87.25)]
        let deltas: [CGFloat] = [10, -10, 3.5, -1.25]
        for anchor in anchors {
            let before = BoardTransform(offset: CGSize(width: 55, height: -20), zoom: 1.5)
            let pageUnderAnchor = before.point(toPage: anchor)
            for delta in deltas {
                let after = before.zoomed(forScrollDelta: delta, isZooming: true, anchoredAt: anchor)
                let kept = after.point(toPage: anchor)
                XCTAssertEqual(
                    kept.x, pageUnderAnchor.x, accuracy: 1e-9,
                    "the page point under the anchor moved scrolling \(delta) at \(anchor)"
                )
                XCTAssertEqual(
                    kept.y, pageUnderAnchor.y, accuracy: 1e-9,
                    "the page point under the anchor moved scrolling \(delta) at \(anchor)"
                )
            }
        }
    }

    /// A huge scroll lands on the range boundary and pushing past an already
    /// clamped end is a no-op, exactly like the keyboard steps.
    func testCommandScrollClampsIntoTheZoomRange() {
        let anchor = CGPoint(x: 400, y: 300)
        let wayIn = BoardTransform.identity.zoomed(forScrollDelta: 500, isZooming: true, anchoredAt: anchor)
        XCTAssertEqual(wayIn.zoom, BoardTransform.maxZoom, "a huge scroll clamps at the range top")
        let wayOut = BoardTransform.identity.zoomed(forScrollDelta: -500, isZooming: true, anchoredAt: anchor)
        XCTAssertEqual(wayOut.zoom, BoardTransform.minZoom, "a huge scroll clamps at the range bottom")
        XCTAssertEqual(
            wayIn.zoomed(forScrollDelta: 500, isZooming: true, anchoredAt: anchor), wayIn,
            "scrolling past an already clamped end changes nothing"
        )
        XCTAssertEqual(wayOut.point(toPage: anchor).x, 400, "a clamped scroll still anchors")
    }

    /// Without ⌘ the scroll never touches the zoom: the transform is returned
    /// exactly as it was.
    func testPlainScrollNeverChangesTheZoom() {
        let transform = BoardTransform(offset: CGSize(width: 42, height: -7), zoom: 2.5)
        for delta: CGFloat in [10, -10, 0.5] {
            XCTAssertEqual(
                transform.zoomed(forScrollDelta: delta, isZooming: false, anchoredAt: CGPoint(x: 100, y: 100)),
                transform,
                "plain scroll (no ⌘) must not change the zoom (delta \(delta))"
            )
        }
    }

    // MARK: - v0.5/S2: the ⌘ + scroll gesture state machine

    /// A delta against the locked direction inside one gesture is finger
    /// jitter, not a decision: it must not zoom in the opposite direction.
    /// The lock latches on the gesture's first nonzero delta and holds until
    /// the gesture ends, so the zoom stays monotonic while the fingers move.
    func testGestureRejectsADeltaAgainstTheLockedDirection() {
        var gesture = ScrollZoom.Gesture()
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: 4)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: 4)),
            "the gesture's first nonzero delta zooms through the one shared factor"
        )
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: -0.5)),
            .noZoom,
            "a small delta reversing the locked direction must not zoom out"
        )
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: -4, phase: .changed)),
            .noZoom,
            "a full reversing delta still waits for enough opposite evidence"
        )
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: 1.5)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: 1.5)),
            "consistent deltas keep zooming in the locked direction"
        )
    }

    /// Momentum events travel behind the fingers' `.ended` phase: they belong
    /// to no live gesture, so they must neither zoom nor disturb the lock —
    /// a two-finger flick must not overshoot the zoom the user asked for.
    func testMomentumNeverZoomsAndNeverDisturbsTheLock() {
        var gesture = ScrollZoom.Gesture()
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: 4)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: 4))
        )
        for momentum in [ScrollZoom.MomentumPhase.begin, .continued, .end] {
            XCTAssertEqual(
                gesture.decide(for: ScrollZoom.Event(deltaY: 300, momentumPhase: momentum)),
                .noZoom,
                "momentum phase \(momentum) must not move the zoom"
            )
        }
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: 2)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: 2)),
            "the gesture event after the momentum burst keeps its lock and zooms in"
        )
    }

    /// The direction is the one the board already had: a positive
    /// `scrollingDeltaY` zooms in, whatever the natural-scrolling preference.
    /// Normalising across the preference would have agreed between devices at
    /// the cost of flipping the zoom for whoever is on the default setting, so
    /// it is deliberately not done (v0.5/S2).
    func testPositiveDeltaZoomsInAsTheBoardAlwaysDid() {
        var gesture = ScrollZoom.Gesture()
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: 12, phase: .began)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: 12))
        )
        XCTAssertGreaterThan(ScrollZoom.zoomFactor(forScrollDelta: 12), 1)

        var other = ScrollZoom.Gesture()
        XCTAssertEqual(
            other.decide(for: ScrollZoom.Event(deltaY: -12, phase: .began)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: -12))
        )
        XCTAssertLessThan(ScrollZoom.zoomFactor(forScrollDelta: -12), 1)
    }

    /// `.ended` (and `.cancelled`) close the gesture: the lock releases, so
    /// the next gesture is free to zoom the other way.
    func testEndingTheGestureReleasesTheLockSoTheNextMayZoomOut() {
        var gesture = ScrollZoom.Gesture()
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: 4, phase: .began)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: 4))
        )
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: 3, phase: .changed)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: 3))
        )
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: 0, phase: .ended)),
            .noZoom,
            "the closing event itself zooms nothing"
        )
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: -4, phase: .began)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: -4)),
            "after the gesture ended a new one may zoom the other way"
        )
    }

    /// Opposite deltas that keep coming are not jitter but the user changing
    /// direction: once they outweigh the jitter threshold the gesture
    /// continues zooming in the new direction instead of staying locked.
    func testADeliberateReversalContinuesTheGestureInTheNewDirection() {
        var gesture = ScrollZoom.Gesture()
        XCTAssertEqual(gesture.decide(for: ScrollZoom.Event(deltaY: 4)), .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: 4)))
        // Two −3 deltas (< the 8-point threshold) stay rejected jitter...
        XCTAssertEqual(gesture.decide(for: ScrollZoom.Event(deltaY: -3)), .noZoom)
        XCTAssertEqual(gesture.decide(for: ScrollZoom.Event(deltaY: -3)), .noZoom)
        // ...the third crosses the threshold: the gesture re-locks out and
        // that event's own delta zooms.
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: -3)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: -3))
        )
        XCTAssertEqual(
            gesture.decide(for: ScrollZoom.Event(deltaY: -3)),
            .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: -3)),
            "the gesture now zooms out monotonically"
        )
    }

    /// `ScrollZoom.zoomFactor` answers 1 for a zero or non-finite delta in the
    /// gesture too: the decision is a hold, and no zoom state moves.
    func testAZeroDeltaHoldsInsteadOfZooming() {
        var gesture = ScrollZoom.Gesture()
        XCTAssertEqual(gesture.decide(for: ScrollZoom.Event(deltaY: 4, phase: .began)), .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: 4)))
        XCTAssertEqual(gesture.decide(for: ScrollZoom.Event(deltaY: 0)), .noZoom)
        XCTAssertEqual(gesture.decide(for: ScrollZoom.Event(deltaY: .infinity)), .noZoom)
        XCTAssertEqual(gesture.decide(for: ScrollZoom.Event(deltaY: .nan)), .noZoom)
    }

    // MARK: - T6/S6: the dot grid

    /// At very low zoom a fixed spacing turns into mush, so the spacing only
    /// ever subdivides by powers of two: the on-screen pitch never falls below
    /// the readable minimum at any zoom level.
    func testDotGridSpacingStaysReadableByPowersOfTwo() {
        let base = DotGrid.spacing
        for zoom in [CGFloat(0.25), 0.3, 0.45, 0.5, 1, 2, 3.5, 8] {
            let spacing = DotGrid.pageSpacing(atZoom: zoom)
            XCTAssertGreaterThanOrEqual(
                spacing * zoom, DotGrid.minimumScreenSpacing,
                "the on-screen pitch must stay readable at zoom \(zoom)"
            )
            let power = spacing / base
            // Halving while still readable must not be possible: the rule
            // stops at the first readable power of two.
            var reduced = power
            while reduced >= 2, reduced / 2 * zoom >= DotGrid.minimumScreenSpacing {
                reduced /= 2
            }
            XCTAssertEqual(reduced, power, "the spacing is the first readable power of two at zoom \(zoom)")
        }
        XCTAssertEqual(DotGrid.pageSpacing(atZoom: 1), base, "zoom 1 shows the base pitch")
        XCTAssertEqual(DotGrid.pageSpacing(atZoom: 0.25), base * 2, "zoom 0.25 coarsens one step")
    }

    /// Dots sit on the pitch, anchored at the page origin, and cover the rect.
    func testDotGridDotsLieOnThePitchInsideTheRect() {
        let rect = CGRect(x: 20, y: 8, width: 104, height: 60)
        let dots = DotGrid.dots(in: rect, spacing: 24)
        XCTAssertFalse(dots.isEmpty)
        for dot in dots {
            XCTAssertEqual(dot.x.truncatingRemainder(dividingBy: 24), 0, accuracy: 1e-9, "dots sit on the pitch")
            XCTAssertEqual(dot.y.truncatingRemainder(dividingBy: 24), 0, accuracy: 1e-9, "dots sit on the pitch")
            XCTAssertTrue(rect.contains(dot), "dots stay in the rect: \(dot)")
        }
        // Rows and columns actually fill the rect: the pitch points nearest
        // each corner are all present.
        let points = Set(dots)
        for corner in [
            CGPoint(x: 24, y: 24), CGPoint(x: 120, y: 24), CGPoint(x: 24, y: 48), CGPoint(x: 120, y: 48),
        ] {
            XCTAssertTrue(points.contains(corner), "the grid covers \(corner)")
        }
        // An empty rect has no dots, and a degenerate spacing never loops.
        XCTAssertTrue(DotGrid.dots(in: .zero, spacing: 24).isEmpty)
        XCTAssertTrue(DotGrid.dots(in: CGRect(x: 0, y: 0, width: 100, height: 100), spacing: 0).isEmpty)
    }

    // MARK: Session persistence (T10/S11)

    /// Builds a two-page board: page 1 black with a pen mark and a numbered
    /// badge, panned and zoomed; page 2 inheriting the background with its
    /// own mark; presenting page 2.
    private func populatedBoard() -> WhiteboardPages {
        let board = WhiteboardPages()
        board.toggleBackground() // page 1: white → black
        board.adopt(drawnSession(stepCount: 1))
        board.setOffset(CGSize(width: 12, height: 34))
        _ = board.zoom(to: 2, anchoredAt: .zero)
        board.selectNext() // page 2 inherits the background
        board.adopt(drawnSession())
        board.pan(by: CGSize(width: 5, height: 6))
        return board
    }

    func testPersistedBoardRoundTripPreservesEveryPageWhoMarksBackgroundPanZoomAndTheCurrentPage() {
        let board = populatedBoard()

        let restored = WhiteboardPages(restoring: board.persistedBoard(), fallbackBackground: .white)
        XCTAssertEqual(restored.count, board.count)
        XCTAssertEqual(restored.currentIndex, board.currentIndex, "the presented page comes back presented")
        for (restoredPage, storedPage) in zip(restored.pages, board.pages) {
            XCTAssertEqual(restoredPage.session.strokes, storedPage.session.strokes, "ids, geometry, ink, tool and numbering come back exactly")
            XCTAssertEqual(restoredPage.session.nextStepNumber, storedPage.session.nextStepNumber)
            XCTAssertEqual(restoredPage.background, storedPage.background)
            XCTAssertEqual(restoredPage.offset, storedPage.offset, "the page's pan comes back")
            XCTAssertEqual(restoredPage.zoom, storedPage.zoom, "the page's zoom comes back")
        }
    }

    func testPersistedBoardExcludesTransientMarksFromEveryPage() {
        var laserPage = DrawingSession()
        laserPage.begin(at: CGPoint(x: 8, y: 8), tool: .laser, ink: .red, now: Date())
        laserPage.commit()
        let board = WhiteboardPages()
        board.adopt(drawnSession())
        board.selectNext()
        board.adopt(laserPage)

        let persisted = board.persistedBoard()
        XCTAssertTrue(persisted.pages[0].strokes.contains { $0.tool == "pen" })
        XCTAssertTrue(persisted.pages[1].strokes.isEmpty, "a laser mark would have faded anyway; it is never stored")
    }

    func testRestoredBoardFallsBackToAFreshPageWhenNothingWasStored() {
        let restored = WhiteboardPages(
            restoring: PersistedBoard(pages: [], currentIndex: 0),
            fallbackBackground: .black
        )
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.currentIndex, 0)
        XCTAssertEqual(restored.currentPage.background, .black)
        XCTAssertTrue(restored.currentPage.session.isEmpty)
    }

    func testRestoredBoardClampsAnOutOfRangeCurrentPage() {
        // A partial or foreign document naming a page the board does not
        // have: the board presents its first page instead of failing.
        let page = PersistedBoardPage(strokes: [], background: .white, offset: .zero, zoom: 1)
        let restored = WhiteboardPages(
            restoring: PersistedBoard(pages: [page], currentIndex: 9),
            fallbackBackground: .white
        )
        XCTAssertEqual(restored.currentIndex, 0)
        XCTAssertEqual(restored.count, 1)
    }

    func testPersistedBoardPageEncodesItsBackgroundAsItsRawValue() throws {
        let stroke = Stroke(tool: .pen, ink: .red, points: [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)])
        let page = PersistedBoardPage(
            strokes: [stroke.persisted],
            background: .black,
            offset: CGSize(width: 3, height: 4),
            zoom: 1.5
        )

        let data = try JSONEncoder().encode(page)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"background\":\"black\""), "the raw value is what the blob keeps: \(json)")
        let decoded = try JSONDecoder().decode(PersistedBoardPage.self, from: data)
        XCTAssertEqual(decoded, page)
    }

    // MARK: - T2b/S2: the page image layer

    private func solidImage(_ width: Int, _ height: Int, _ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// One image per page: a paste sets it, a second paste replaces it, and
    /// every page keeps its own — coming back to a page finds its layer again.
    func testPasteReplacesThePagesImageAndEveryPageKeepsItsOwn() {
        let board = WhiteboardPages()
        let first = solidImage(100, 80, 1, 0, 0)
        let layer1 = board.paste(first, inView: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertNotNil(layer1)
        XCTAssertEqual(board.currentPage.image, layer1)

        let second = solidImage(100, 80, 0, 1, 0)
        let layer2 = board.paste(second, inView: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertNotEqual(layer2?.id, layer1?.id, "the replacement is a new layer, not a mutation of the old one")
        XCTAssertEqual(board.currentPage.image, layer2, "a new paste replaces the page's image")

        board.selectNext()
        XCTAssertNil(board.currentPage.image, "the layer is per page: a new one starts without it")
        let layer3 = board.paste(second, inView: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertNotNil(layer3)
        board.selectPrevious()
        XCTAssertEqual(board.currentPage.image, layer2, "coming back to a page must not lose its layer")
        board.selectNext()
        XCTAssertEqual(board.currentPage.image, layer3)
    }

    func testTheImageLayerTravelsWithItsPageThroughReorderAndDelete() {
        let board = WhiteboardPages()
        let layer1 = board.paste(solidImage(100, 80, 1, 0, 0), inView: CGRect(x: 0, y: 0, width: 800, height: 600))
        board.selectNext()
        let layer2 = board.paste(solidImage(100, 80, 0, 1, 0), inView: CGRect(x: 0, y: 0, width: 800, height: 600))

        board.selectPrevious()
        XCTAssertTrue(board.moveCurrentPageRight(), "page 1 swaps with page 2")
        XCTAssertEqual(board.currentIndex, 1)
        XCTAssertEqual(board.currentPage.image, layer1, "the layer travels with its page")
        XCTAssertEqual(board.pages[0].image, layer2)

        XCTAssertTrue(board.deleteCurrentPage())
        XCTAssertEqual(board.pages[0].image, layer2, "deleting a page leaves the other pages' layers alone")
    }

    func testMovePageImageClampsIntoTheVisibleRect() {
        let board = WhiteboardPages()
        let visible = CGRect(x: 0, y: 0, width: 800, height: 600)
        _ = board.paste(solidImage(100, 80, 1, 0, 0), inView: visible)

        // Dragging far past the right edge keeps a grabbable strip in reach.
        XCTAssertTrue(board.movePageImage(by: CGSize(width: 500, height: 0), clampedTo: visible))
        let rect = board.currentPage.image!.rect
        XCTAssertEqual(rect.minX, visible.maxX - CanvasComposition.minimumGrabSide, accuracy: 0.01)
        XCTAssertEqual(rect.minY, 260, accuracy: 0.01, "the other axis is untouched")
        XCTAssertEqual(rect.width, 100, accuracy: 0.01, "a move never resizes")
    }

    func testPlacePageImageClampsTheResizeIntoTheVisibleRect() {
        let board = WhiteboardPages()
        let visible = CGRect(x: 0, y: 0, width: 800, height: 600)
        _ = board.paste(solidImage(100, 80, 1, 0, 0), inView: visible)

        // A corner drag that would put the layer off the page lands it
        // clamped back inside.
        XCTAssertTrue(board.placePageImage(at: CGRect(x: 900, y: 0, width: 100, height: 80), clampedTo: visible))
        XCTAssertEqual(board.currentPage.image!.rect, CanvasComposition.clampedPlacement(
            CGRect(x: 900, y: 0, width: 100, height: 80), in: visible
        ))
        XCTAssertEqual(board.currentPage.image!.rect.minX, visible.maxX - CanvasComposition.minimumGrabSide, accuracy: 0.01)
    }

    func testMoveAndPlaceAndRemoveRefuseWhenThePageHasNoImage() {
        let board = WhiteboardPages()
        let visible = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertFalse(board.movePageImage(by: CGSize(width: 10, height: 10), clampedTo: visible))
        XCTAssertFalse(board.placePageImage(at: CGRect(x: 0, y: 0, width: 10, height: 10), clampedTo: visible))
        XCTAssertFalse(board.removePageImage())

        _ = board.paste(solidImage(10, 10, 1, 0, 0), inView: visible)
        XCTAssertTrue(board.removePageImage())
        XCTAssertNil(board.currentPage.image)
        XCTAssertFalse(board.removePageImage(), "a second ⌫ has nothing left to remove")
    }

    /// Rule 6: the image layer lives as long as the session, like the pages —
    /// it is never written to the boot archive.
    func testPersistedBoardExcludesTheImageLayer() {
        let board = WhiteboardPages()
        board.adopt(drawnSession())
        board.pan(by: CGSize(width: 12, height: 34))
        _ = board.paste(solidImage(100, 80, 1, 0, 0), inView: CGRect(x: 0, y: 0, width: 800, height: 600))

        let restored = WhiteboardPages(restoring: board.persistedBoard(), fallbackBackground: .white)
        XCTAssertEqual(restored.pages.count, board.count, "the pages come back as always")
        XCTAssertEqual(restored.currentPage.offset, board.currentPage.offset, "the pan comes back as always")
        XCTAssertFalse(restored.currentPage.session.isEmpty, "the marks come back as always")
        for page in restored.pages {
            XCTAssertNil(page.image, "the image layer is a session value: the archive never stores it")
        }
    }
}
