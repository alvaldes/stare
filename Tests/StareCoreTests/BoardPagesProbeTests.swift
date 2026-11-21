import CoreGraphics
import XCTest

import StareCore

/// Independent page-management probes (T12/S9, brought in from the verifier):
/// delete and move keep every other page byte-identical — sessions, undo
/// stacks, backgrounds and offsets — and the board never leaves the index out
/// of range.
final class BoardPagesProbeTests: XCTestCase {
    private func session(_ ink: Ink, _ x: CGFloat) -> DrawingSession {
        var s = DrawingSession()
        s.begin(at: CGPoint(x: x, y: x), tool: .pen, ink: ink)
        s.extend(to: CGPoint(x: x + 20, y: x + 20))
        s.commit()
        return s
    }

    /// Four pages, each with its own background, offset and marks.
    private func fourPages() -> (WhiteboardPages, [DrawingSession]) {
        let board = WhiteboardPages()
        var sessions: [DrawingSession] = []
        for i in 0..<4 {
            if i > 0 { board.selectNext() }
            board.setOffset(CGSize(width: CGFloat(i) * 10, height: CGFloat(i) * 5))
            if i % 2 == 0 { board.toggleBackground() } // pages 1 and 3 black
            let s = session(Ink.allCases[i % Ink.allCases.count], CGFloat(i) * 30)
            board.adopt(s)
            sessions.append(s)
        }
        return (board, sessions)
    }

    func testDeleteMiddlePageKeepsEveryOtherPageAndItsState() {
        let (board, s) = fourPages()
        XCTAssertTrue(board.select(index: 1))
        XCTAssertTrue(board.deleteCurrentPage())
        print("PROBE delete-middle count=\(board.count) current=\(board.currentIndex)")
        XCTAssertEqual(board.count, 3)
        XCTAssertEqual(board.currentIndex, 1)
        // The page that followed the deleted one takes its slot; the rest keep
        // their exact sessions (marks, undo stacks), backgrounds and offsets.
        XCTAssertEqual(board.pages[0].session, s[0])
        XCTAssertEqual(board.pages[1].session, s[2])
        XCTAssertEqual(board.pages[2].session, s[3])
        XCTAssertEqual(board.pages[0].offset, CGSize(width: 0, height: 0))
        XCTAssertEqual(board.pages[1].offset, CGSize(width: 20, height: 10))
        XCTAssertEqual(board.pages[2].offset, CGSize(width: 30, height: 15))
        XCTAssertEqual(board.pages.map(\.background), [.black, .white, .white])
        // No page lost or gained a mark.
        XCTAssertEqual(board.pages.map { $0.session.strokes.count }, [1, 1, 1])
    }

    func testDeleteFirstPagePullsTheBoardBackInRangeAndUndoStaysOnItsPage() {
        let (board, s) = fourPages()
        XCTAssertTrue(board.select(index: 0))
        XCTAssertTrue(board.deleteCurrentPage())
        XCTAssertEqual(board.currentIndex, 0)
        XCTAssertEqual(board.pages[0].session, s[1])
        // Deleting the only remaining mark's page then undoing must not move a
        // mark onto another page: the surviving pages keep byte-identical state.
        let before = board.pages.map(\.session)
        var current = board.currentPage.session
        _ = current.undo()
        board.adopt(current)
        XCTAssertEqual(board.pages[1].session, before[1], "undo on one page never edits another page")
        XCTAssertEqual(board.pages[2].session, before[2])
        XCTAssertEqual(board.pages.map(\.session.strokes.count), [0, 1, 1], "undo only touched the current page")
    }

    func testDeleteRefusedOnLastPageAndAfterwardsSelectStillInRange() {
        let (board, s) = fourPages()
        for _ in 0..<3 {
            XCTAssertTrue(board.deleteCurrentPage(), "the current (last) page can be deleted while pages remain")
            XCTAssertLessThan(board.currentIndex, board.count)
        }
        XCTAssertEqual(board.count, 1)
        XCTAssertFalse(board.deleteCurrentPage(), "the last page is never deleted")
        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(board.currentIndex, 0)
        XCTAssertEqual(board.pages[0].session, s[0])
        XCTAssertFalse(board.select(index: 1))
        XCTAssertTrue(board.select(index: 0))
        // A fresh page after that inherits the background, like ›.
        XCTAssertTrue(board.selectNext())
        XCTAssertEqual(board.count, 2)
    }

    func testMoveKeepsEachPageWholeAcrossTheSwap() {
        let (board, s) = fourPages()
        XCTAssertTrue(board.select(index: 2))
        XCTAssertTrue(board.moveCurrentPageLeft()) // 3rd page to slot 2
        XCTAssertEqual(board.currentIndex, 1)
        XCTAssertEqual(board.pages.map(\.session), [s[0], s[2], s[1], s[3]])
        XCTAssertEqual(board.pages.map(\.offset), [CGSize(width: 0, height: 0), CGSize(width: 20, height: 10),
                                                   CGSize(width: 10, height: 5), CGSize(width: 30, height: 15)])
        XCTAssertEqual(board.pages.map(\.background), [.black, .white, .black, .white])
        XCTAssertTrue(board.moveCurrentPageRight())
        XCTAssertEqual(board.pages.map(\.session), [s[0], s[1], s[2], s[3]])
        XCTAssertEqual(board.currentIndex, 2)
        // Boundaries.
        XCTAssertTrue(board.moveCurrentPageRight())
        XCTAssertEqual(board.currentIndex, 3)
        XCTAssertFalse(board.moveCurrentPageRight())
        XCTAssertEqual(board.currentIndex, 3)
        XCTAssertTrue(board.select(index: 0))
        XCTAssertFalse(board.moveCurrentPageLeft())
        XCTAssertEqual(board.currentIndex, 0)
        XCTAssertEqual(board.count, 4)
        // One page: both moves are refused and nothing changes.
        let single = WhiteboardPages()
        single.adopt(session(.red, 0))
        XCTAssertFalse(single.moveCurrentPageLeft())
        XCTAssertFalse(single.moveCurrentPageRight())
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single.pages[0].session.strokes.count, 1)
        XCTAssertEqual(single.pages[0].session.strokes.first?.points.map(\.x), [0, 20])
    }
}
