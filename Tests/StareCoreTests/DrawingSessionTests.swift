import CoreGraphics
import XCTest

import StareCore

final class DrawingSessionTests: XCTestCase {
    private func drawLine(
        in session: inout DrawingSession,
        tool: Tool = .pen,
        points: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]
    ) {
        session.begin(at: points[0], tool: tool, ink: .red)
        for point in points.dropFirst() { session.extend(to: point) }
        session.commit()
    }

    func testStrokeIsVisibleWhileDragging() {
        var session = DrawingSession()
        session.begin(at: .zero, tool: .pen, ink: .red)
        session.extend(to: CGPoint(x: 5, y: 5))

        XCTAssertEqual(session.visibleStrokes.count, 1)
        XCTAssertTrue(session.strokes.isEmpty, "an in-progress mark is not committed yet")
    }

    func testCommitKeepsFreehandSamplesAndShapeEndpoints() {
        var pen = DrawingSession()
        drawLine(in: &pen, tool: .pen, points: [
            CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5), CGPoint(x: 10, y: 10),
        ])
        XCTAssertEqual(pen.strokes.first?.points.count, 3)

        var rectangle = DrawingSession()
        drawLine(in: &rectangle, tool: .rectangle, points: [
            CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5), CGPoint(x: 10, y: 10),
        ])
        XCTAssertEqual(rectangle.strokes.first?.points, [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
    }

    func testClickToolCommitsImmediately() {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 30, y: 30), tool: .number, ink: .green)

        XCTAssertEqual(session.strokes.count, 1)
        XCTAssertNil(session.active)
        XCTAssertEqual(session.strokes.first?.stepNumber, 1)
    }

    // S7: numbered steps count up as the user clicks.
    func testNumberedStepsCountUp() {
        var session = DrawingSession()
        for index in 0..<3 {
            session.begin(at: CGPoint(x: CGFloat(index), y: 0), tool: .number, ink: .green)
        }

        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2, 3])
        XCTAssertEqual(session.nextStepNumber, 4)
        XCTAssertEqual(session.stepCount, 3)
    }

    func testOnePointDragDoesNotLeaveAMark() {
        var session = DrawingSession()
        session.begin(at: .zero, tool: .pen, ink: .red)
        session.commit()

        XCTAssertTrue(session.strokes.isEmpty, "a bare click with a drag tool draws nothing")
    }

    // S8: Command-Z undoes the last mark.
    func testUndoRemovesTheLastCommittedMark() {
        var session = DrawingSession()
        drawLine(in: &session)
        drawLine(in: &session, points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])
        XCTAssertEqual(session.strokes.count, 2)

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes.count, 1)
    }

    func testUndoWhileDraggingDiscardsTheActiveMark() {
        var session = DrawingSession()
        drawLine(in: &session)
        session.begin(at: .zero, tool: .pen, ink: .red)

        XCTAssertTrue(session.undo())
        XCTAssertNil(session.active)
        XCTAssertEqual(session.strokes.count, 1, "the committed mark survives")
    }

    func testUndoOnEmptySessionIsANoOp() {
        var session = DrawingSession()
        XCTAssertFalse(session.undo())
        XCTAssertTrue(session.isEmpty)
    }

    func testUndoGivesTheStepNumberBack() {
        var session = DrawingSession()
        session.begin(at: .zero, tool: .number, ink: .green)
        session.begin(at: CGPoint(x: 10, y: 0), tool: .number, ink: .green)
        XCTAssertEqual(session.nextStepNumber, 3)

        session.undo()
        XCTAssertEqual(session.nextStepNumber, 2, "numbers never leave a gap")

        session.begin(at: CGPoint(x: 20, y: 0), tool: .number, ink: .green)
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2])
    }

    // S8: Escape clears every mark and restarts numbering.
    func testClearRemovesEverythingAndRestartsNumbering() {
        var session = DrawingSession()
        drawLine(in: &session)
        session.begin(at: .zero, tool: .number, ink: .green)

        session.clear()

        XCTAssertTrue(session.isEmpty)
        XCTAssertEqual(session.nextStepNumber, 1)
        XCTAssertTrue(session.visibleStrokes.isEmpty)
    }

    // S17: Shift while drawing with a freehand tool collapses to a straight line.
    func testShiftCollapsesTheMarkToAStraightLine() {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 0, y: 0), tool: .pen, ink: .red)
        session.extend(to: CGPoint(x: 10, y: 40))
        session.extend(to: CGPoint(x: 30, y: 20))
        session.commit()
        XCTAssertEqual(session.strokes.first?.points.count, 3)

        var straight = DrawingSession()
        straight.begin(at: CGPoint(x: 0, y: 0), tool: .pen, ink: .red)
        straight.extend(to: CGPoint(x: 10, y: 40))
        straight.extend(to: CGPoint(x: 30, y: 20), straight: true)
        straight.commit()

        XCTAssertEqual(
            straight.strokes.first?.points,
            [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 20)]
        )
    }

    func testReleasingShiftResumesFreehand() {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 0, y: 0), tool: .pen, ink: .red)
        session.extend(to: CGPoint(x: 10, y: 10), straight: true)
        session.extend(to: CGPoint(x: 20, y: 30))

        XCTAssertEqual(session.active?.points.count, 3)
        XCTAssertEqual(session.active?.points.last, CGPoint(x: 20, y: 30))
    }

    func testRemovingAMarkByIdKeepsTheRest() {
        var session = DrawingSession()
        drawLine(in: &session)
        drawLine(in: &session, points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])
        let firstID = session.strokes[0].id

        XCTAssertTrue(session.remove(id: firstID))
        XCTAssertEqual(session.strokes.count, 1)
        XCTAssertFalse(session.remove(id: firstID), "removing twice reports failure")
    }
}
