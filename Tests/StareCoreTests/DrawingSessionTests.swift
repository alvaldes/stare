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

    // v0.2: Shift-Command-Z puts back the mark Command-Z removed.
    func testRedoRestoresTheLastUndoneMark() {
        var session = DrawingSession()
        drawLine(in: &session)
        drawLine(in: &session, points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])
        let second = session.strokes[1].id

        session.undo()
        XCTAssertEqual(session.strokes.count, 1)

        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes.count, 2)
        XCTAssertEqual(session.strokes.last?.id, second, "the same mark comes back")
    }

    func testRedoIsLifoAcrossSeveralUndos() {
        var session = DrawingSession()
        for index in 0 ..< 3 {
            drawLine(in: &session, points: [CGPoint(x: CGFloat(index), y: 0), CGPoint(x: CGFloat(index), y: 10)])
        }
        let ids = session.strokes.map(\.id)

        session.undo()
        session.undo()
        XCTAssertEqual(session.strokes.map(\.id), [ids[0]])

        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes.map(\.id), [ids[0], ids[1]])
        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes.map(\.id), ids)
    }

    func testRedoIsEmptyAfterANewMark() {
        var session = DrawingSession()
        drawLine(in: &session)
        session.undo()

        drawLine(in: &session, points: [CGPoint(x: 30, y: 30), CGPoint(x: 60, y: 60)])

        XCTAssertFalse(session.redo(), "a new mark forks the history")
        XCTAssertEqual(session.strokes.count, 1)
    }

    func testRedoIsEmptyAfterAnErase() {
        var session = DrawingSession()
        drawLine(in: &session)
        drawLine(in: &session, points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])
        session.undo()

        session.erase(at: .zero, radius: 1)

        XCTAssertFalse(session.redo(), "erasing is an edit, so the undone mark is gone for good")
    }

    func testUndoWhileDraggingDoesNotFeedRedo() {
        var session = DrawingSession()
        session.begin(at: .zero, tool: .pen, ink: .red)

        XCTAssertTrue(session.undo())
        XCTAssertFalse(session.redo(), "an uncommitted mark was never in the history")
    }

    func testRedoGivesTheStepNumberBackAgain() {
        var session = DrawingSession()
        session.begin(at: .zero, tool: .number, ink: .green)
        session.begin(at: CGPoint(x: 10, y: 0), tool: .number, ink: .green)
        session.undo()
        XCTAssertEqual(session.nextStepNumber, 2)

        XCTAssertTrue(session.redo())

        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2])
        XCTAssertEqual(session.nextStepNumber, 3)
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

    // S21: the eraser removes whole marks it touches.
    func testEraserRemovesTheMarkUnderThePointer() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .line, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])

        XCTAssertTrue(session.erase(at: CGPoint(x: 50, y: 1), radius: 6).isEmpty == false)
        XCTAssertTrue(session.strokes.isEmpty)
    }

    func testEraserIgnoresMarksItDoesNotTouch() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .line, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])

        XCTAssertTrue(session.erase(at: CGPoint(x: 50, y: 80), radius: 6).isEmpty)
        XCTAssertEqual(session.strokes.count, 1)
    }

    func testEraserKeepsNumberingGapless() {
        var session = DrawingSession()
        for index in 0..<3 {
            session.begin(at: CGPoint(x: CGFloat(index) * 60, y: 0), tool: .number, ink: .green)
        }
        let middle = session.strokes[1]
        session.erase(at: middle.points[0], radius: 4)

        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2])
        XCTAssertEqual(session.nextStepNumber, 3)
    }

    // S22: laser marks fade and expire; normal marks do not.
    func testLaserMarksExpireAndOthersDoNot() {
        var session = DrawingSession()
        let birth = Date(timeIntervalSince1970: 1_000)
        session.laserLifetime = 1.2

        session.begin(at: .zero, tool: .laser, ink: .red, now: birth)
        session.extend(to: CGPoint(x: 50, y: 0))
        session.commit()
        session.begin(at: CGPoint(x: 200, y: 0), tool: .pen, ink: .red, now: birth)
        session.extend(to: CGPoint(x: 250, y: 0))
        session.commit()

        XCTAssertFalse(session.pruneTransient(now: birth.addingTimeInterval(0.5)))
        XCTAssertEqual(session.strokes.count, 2)
        XCTAssertTrue(session.pruneTransient(now: birth.addingTimeInterval(2)))
        XCTAssertEqual(session.strokes.count, 1)
        XCTAssertEqual(session.strokes.first?.tool, .pen)
    }

    func testLaserFadesWithAge() {
        let birth = Date(timeIntervalSince1970: 1_000)
        let stroke = Stroke(
            tool: .laser, ink: .red,
            points: [.zero, CGPoint(x: 10, y: 0)],
            createdAt: birth
        )

        XCTAssertEqual(stroke.opacity(at: birth, laserLifetime: 1.2), 1, accuracy: 0.01)
        XCTAssertEqual(stroke.opacity(at: birth.addingTimeInterval(0.6), laserLifetime: 1.2), 0.5, accuracy: 0.01)
        XCTAssertEqual(stroke.opacity(at: birth.addingTimeInterval(2), laserLifetime: 1.2), 0)
    }

    func testExpiredLaserIsNotVisible() {
        var session = DrawingSession()
        let birth = Date(timeIntervalSince1970: 1_000)
        session.laserLifetime = 1.0
        session.begin(at: .zero, tool: .laser, ink: .red, now: birth)
        session.extend(to: CGPoint(x: 30, y: 0))
        session.commit()

        XCTAssertEqual(session.visibleStrokes(at: birth.addingTimeInterval(0.2)).count, 1)
        XCTAssertTrue(session.visibleStrokes(at: birth.addingTimeInterval(1.5)).isEmpty)
    }

    // S23: text is placed with a click and kept until confirmed.
    func testTextMarkIsPlacedButNotCommittedUntilConfirmed() {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 40, y: 60), tool: .text, ink: .blue)

        XCTAssertNotNil(session.active)
        XCTAssertTrue(session.strokes.isEmpty)

        session.setActiveText("Export failed", size: CGSize(width: 120, height: 24))
        session.commit()

        XCTAssertEqual(session.strokes.count, 1)
        XCTAssertEqual(session.strokes.first?.text, "Export failed")
        XCTAssertEqual(session.strokes.first?.textSize, CGSize(width: 120, height: 24))
    }

    func testEmptyTextLeavesNoMark() {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 40, y: 60), tool: .text, ink: .blue)
        session.setActiveText("", size: .zero)
        session.commit()

        XCTAssertTrue(session.strokes.isEmpty, "a stray click must not leave an invisible box")
    }

    /// Regression: the click that opens the editor used to commit the empty text
    /// mark through the drag path, so the text typed afterwards was discarded.
    func testTextMarkSurvivesAMouseUpBeforeTyping() {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 40, y: 60), tool: .text, ink: .blue)

        // What a stray commit would do; the view no longer does this, and even if
        // it did, the mark must not be lost silently.
        session.setActiveText("", size: nil)
        session.commit()
        XCTAssertTrue(session.strokes.isEmpty)

        session.begin(at: CGPoint(x: 40, y: 60), tool: .text, ink: .blue)
        session.setActiveText("abc", size: CGSize(width: 30, height: 24))
        session.commit()
        XCTAssertEqual(session.strokes.first?.text, "abc")
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

    // T11/S6 slice 2: a deleted mark waits for redo exactly like one undo
    // took away, so ⇧⌘Z after ⌫ brings it back on the same display.
    func testRemovedMarkWaitsForRedoLikeAnUndo() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        let id = session.strokes[0].id

        XCTAssertTrue(session.remove(id: id))
        XCTAssertTrue(session.strokes.isEmpty)
        XCTAssertTrue(session.canRedo(markWithID: id))

        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes.map(\.id), [id])
        XCTAssertFalse(session.canRedo(markWithID: id))
    }

    // MARK: - T11/S6 slice 2: the global history routes undo/redo by mark id

    // The controller pops a history entry and must not undo a different op
    // than the one it popped: the query answers for the newest *live* op,
    // whatever kind it is.
    func testCanUndoMarkWithIDSeesDrawsAndTransforms() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 200, y: 0), CGPoint(x: 300, y: 50)])
        let first = session.strokes[0].id
        let second = session.strokes[1].id

        XCTAssertTrue(session.canUndo(markWithID: second))
        XCTAssertFalse(session.canUndo(markWithID: first), "the second draw is newest")

        let moved = MarkTransform.translated(session.strokes[1], by: CGPoint(x: 5, y: 5))
        XCTAssertTrue(session.replace(moved))
        XCTAssertTrue(session.canUndo(markWithID: second), "the transform is now the newest op")
        XCTAssertFalse(session.canUndo(markWithID: first))

        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.canUndo(markWithID: second), "after the transform undo, the draw is newest again")
    }

    // Erasing leaves stale journal entries behind; the query must look through
    // them instead of naming a mark that no longer exists.
    func testCanUndoMarkWithIDSkipsStaleEntries() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 200, y: 0), CGPoint(x: 300, y: 50)])
        let first = session.strokes[0].id
        let second = session.strokes[1].id

        session.erase(at: session.strokes[1].points[0], radius: 1)

        XCTAssertTrue(session.canUndo(markWithID: first))
        XCTAssertFalse(session.canUndo(markWithID: second), "the erased mark's entry is stale")
        XCTAssertFalse(session.canUndo(markWithID: UUID()))
    }

    // The exact contract the verifier found broken: draw A, draw B, move A —
    // ⌘Z restores A's geometry, ⌘Z removes B, ⌘Z removes A, and ⇧⌘Z three
    // times comes back exactly to the original state.
    func testDrawDrawMoveRoundTripsThroughThreeUndosAndThreeRedos() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 200, y: 0), CGPoint(x: 300, y: 50)])
        let a = session.strokes[0]
        let b = session.strokes[1]
        let movedA = MarkTransform.translated(a, by: CGPoint(x: 30, y: 0))
        XCTAssertTrue(session.replace(movedA))
        XCTAssertEqual(session.strokes[0].points, movedA.points)

        // The global history pops in exactly this order, and each entry must
        // be the session's newest live op when it is popped.
        XCTAssertTrue(session.canUndo(markWithID: a.id))
        XCTAssertFalse(session.canUndo(markWithID: b.id))

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes[0].points, a.points, "the first undo restores A's geometry")
        XCTAssertTrue(session.canUndo(markWithID: b.id))
        XCTAssertTrue(session.canRedo(markWithID: a.id))

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes.map(\.id), [a.id], "then B goes away")
        XCTAssertTrue(session.canUndo(markWithID: a.id))
        XCTAssertTrue(session.canRedo(markWithID: b.id))

        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.strokes.isEmpty, "then A goes away")
        XCTAssertTrue(session.canRedo(markWithID: a.id))

        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes.map(\.id), [a.id])
        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes.map(\.id), [a.id, b.id])
        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes[0].id, a.id)
        XCTAssertEqual(session.strokes[0].points, movedA.points, "back to the transformed state exactly")
        XCTAssertFalse(session.canRedo(markWithID: a.id), "nothing left to redo")
        XCTAssertTrue(session.canUndo(markWithID: a.id), "and the round trip can start over")
    }

    // The same mark moved twice: every move is its own undo step, and redo
    // walks the transforms back in the same order they were made.
    func testSameMarkMovedTwiceRoundTripsThroughUndoAndRedo() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        let a = session.strokes[0]
        let moved1 = MarkTransform.translated(a, by: CGPoint(x: 10, y: 0))
        let moved2 = MarkTransform.translated(moved1, by: CGPoint(x: 0, y: 20))

        XCTAssertTrue(session.replace(moved1))
        XCTAssertTrue(session.replace(moved2))
        XCTAssertEqual(session.strokes[0].points, moved2.points)
        XCTAssertTrue(session.canUndo(markWithID: a.id))

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes[0].points, moved1.points, "the second move undoes first")
        XCTAssertTrue(session.canUndo(markWithID: a.id))

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes[0].points, a.points, "then the first move")

        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes[0].points, moved1.points)
        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes[0].points, moved2.points, "redo walks the moves back in order")
    }

    // The redo query sees transform entries, which `undoneStrokes` does not
    // carry — that is what made ⇧⌘Z silently drop transforms before.
    func testCanRedoMarkWithIDSeesTransformEntries() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        let id = session.strokes[0].id
        let moved = MarkTransform.translated(session.strokes[0], by: CGPoint(x: 5, y: 5))

        XCTAssertTrue(session.replace(moved))
        XCTAssertFalse(session.canRedo(markWithID: id), "a fresh transform forks the history")

        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.canRedo(markWithID: id), "the undone transform waits for redo")

        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes[0].points, moved.points)
        XCTAssertFalse(session.canRedo(markWithID: id))
    }

    // MARK: - T11/S6 advisories: deleting numbered marks keeps numbering gapless

    // Advisory D: ⌫ goes through remove(id:), which must leave a gapless
    // sequence exactly like the eraser does — deleting step 2 of [1,2,3] must
    // renumber the third mark to 2 and hand the number 3 to the next mark.
    func testDeletingANumberedMarkRenumbersGapless() {
        var session = DrawingSession()
        for index in 0..<3 {
            session.begin(at: CGPoint(x: CGFloat(index) * 60, y: 0), tool: .number, ink: .green)
        }
        let middle = session.strokes[1].id

        XCTAssertTrue(session.remove(id: middle))
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2], "the third mark takes the freed number")
        XCTAssertEqual(session.nextStepNumber, 3)

        session.begin(at: CGPoint(x: 300, y: 0), tool: .number, ink: .green)
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2, 3], "no duplicate number where the deleted mark was")
    }

    // Advisory D, global path: ⇧⌘Z after ⌫ restores the deleted mark with the
    // sequence still gapless — the stale journalled number must not come back
    // as a duplicate.
    func testRedoAfterDeletingANumberedMarkKeepsTheSequenceGapless() {
        var session = DrawingSession()
        for index in 0..<3 {
            session.begin(at: CGPoint(x: CGFloat(index) * 60, y: 0), tool: .number, ink: .green)
        }
        let middle = session.strokes[1].id

        XCTAssertTrue(session.remove(id: middle))
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2])

        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes.count, 3)
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2, 3], "the restored mark takes the next number, not its stale one")
        XCTAssertEqual(session.nextStepNumber, 4)
    }

    // MARK: - T11/S6: transforms are undoable

    // Undo after a move/scale/rotate restores the previous geometry exactly,
    // and redo re-applies the transform.
    func testTransformUndoRestoresGeometryAndRedoReappliesIt() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        let snapshot = session.strokes[0]

        let moved = MarkTransform.translated(snapshot, by: CGPoint(x: 30, y: 0))
        XCTAssertTrue(session.replace(moved))
        XCTAssertEqual(session.strokes[0].points, moved.points)

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes.count, 1, "undoing a transform keeps the mark")
        XCTAssertEqual(session.strokes[0].points, snapshot.points, "the previous geometry is restored exactly")
        XCTAssertEqual(session.strokes[0].rotation, snapshot.rotation)

        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes[0].points, moved.points, "redo re-applies the transform")
    }

    // A transform sits on top of the draw history: undoing it first must not
    // consume the pending draw undo, and redo walks back in reverse order.
    func testUndoAfterATransformStillCanUndoTheDraw() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])
        let first = session.strokes[0]
        let transformed = MarkTransform.translated(first, by: CGPoint(x: 5, y: 5))

        XCTAssertTrue(session.replace(transformed))

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes[0].points, first.points, "the transform undoes first")
        XCTAssertEqual(session.strokes.count, 2, "the pending draw undo is not consumed")

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes.count, 1, "then the second draw undoes")

        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes.count, 2)

        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes[0].points, transformed.points, "the transform is reapplied last")
    }

    // A no-op replace must not eat an undo step, and an unknown id reports
    // failure without touching the session.
    func testReplaceIgnoresNoOpsAndUnknownIds() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])

        XCTAssertFalse(session.replace(Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 99, y: 0), CGPoint(x: 10, y: 10)]
        )), "no mark has that id")
        XCTAssertEqual(session.strokes.count, 1)

        XCTAssertTrue(session.replace(session.strokes[0]), "same geometry: no journal entry")
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes.count, 0, "the draw undo is still there, not a transform undo")
    }

    // T11/S6 defect A: the cursor must never become a mark — a stray drag
    // with the select tool would leave an invisible mark no eraser can reach.
    func testSelectToolNeverBecomesAMark() {
        var session = DrawingSession()
        session.begin(at: .zero, tool: .select, ink: .red)
        session.extend(to: CGPoint(x: 30, y: 30))
        session.commit()

        XCTAssertTrue(session.strokes.isEmpty, "a drag with the cursor tool leaves no mark")
        XCTAssertNil(session.active)
    }

    // Erase stays an edit that forks the history: undone marks and transforms
    // are gone for good.
    func testEraseStillClearsRedoIncludingTransforms() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        let transformed = MarkTransform.translated(session.strokes[0], by: CGPoint(x: 3, y: 3))
        XCTAssertTrue(session.replace(transformed))
        XCTAssertFalse(session.canRedo, "a fresh transform forks the history")

        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.canRedo, "the undone transform waits for redo")

        session.erase(at: session.strokes[0].points[0], radius: 1)

        XCTAssertFalse(session.canRedo, "erasing is an edit, so the undone work is gone for good")
    }

    // T11/S6 defect D: undo after an erase renumbering must take the number
    // from the live stroke, not the stale journalled snapshot, or the next
    // number leaves a gap where the erased mark used to be.
    func testUndoAfterErasingTheFirstNumberKeepsTheSequenceGapless() {
        var session = DrawingSession()
        for index in 0..<3 {
            session.begin(at: CGPoint(x: CGFloat(index) * 60, y: 0), tool: .number, ink: .green)
        }
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2, 3])

        session.erase(at: session.strokes[0].points[0], radius: 4)
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2])
        XCTAssertEqual(session.nextStepNumber, 3)

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.nextStepNumber, 2, "the live stroke's number, not the stale journalled one")

        session.begin(at: CGPoint(x: 300, y: 0), tool: .number, ink: .green)
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2], "no gap where 2 was lost")
        XCTAssertEqual(session.nextStepNumber, 3)
    }

    func testUndoAfterErasingTheMiddleNumberKeepsTheSequenceGapless() {
        var session = DrawingSession()
        for index in 0..<3 {
            session.begin(at: CGPoint(x: CGFloat(index) * 60, y: 0), tool: .number, ink: .green)
        }

        session.erase(at: session.strokes[1].points[0], radius: 4)
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2])
        XCTAssertEqual(session.nextStepNumber, 3)

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.nextStepNumber, 2, "the live stroke's number, not the stale journalled one")

        session.begin(at: CGPoint(x: 300, y: 0), tool: .number, ink: .green)
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2])
        XCTAssertEqual(session.nextStepNumber, 3)
    }

    // T11/S6 defect F: sessions that differ only in their undo/redo journals
    // behave differently on undo/redo, so they must not compare equal.
    func testSessionsDifferingOnlyInHistoryAreNotEqual() {        var base = DrawingSession()
        drawLine(in: &base, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])

        var transformed = base
        let moved = MarkTransform.translated(transformed.strokes[0], by: CGPoint(x: 5, y: 5))
        XCTAssertTrue(transformed.replace(moved))
        XCTAssertTrue(transformed.undo())

        var plain = base

        XCTAssertEqual(transformed.strokes, plain.strokes, "the visible state is the same…")
        XCTAssertNotEqual(transformed, plain, "…but a different history must not compare equal")
    }

    // MARK: - T4/S5: the Escape clear is one undoable step

    // The owner's report verbatim: "si limpio con esc y despues hago cmd+z
    // se debe restaurar lo que se limpio". The clear journals the whole batch
    // at once, so one ⌘Z restores every mark with its exact ids and geometry.
    func testEscapeClearThenUndoRestoresTheExactSetOfMarks() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .pen, points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])
        drawLine(in: &session, tool: .line, points: [CGPoint(x: 50, y: 50), CGPoint(x: 60, y: 30)])
        let original = session.strokes

        XCTAssertTrue(session.clearForUndo(), "a clear of marks reports a journalled step")
        XCTAssertTrue(session.strokes.isEmpty, "the clear took every mark away")

        XCTAssertTrue(session.undo(), "the clear is one undo step, not one per mark")
        XCTAssertEqual(session.strokes, original, "every mark comes back exactly: ids, geometry, inks")
    }

    // ⇧⌘Z after the ⌘Z restore clears the batch again, and the round trip
    // keeps working one more step.
    func testEscapeClearThenRedoClearsItAgain() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .pen)
        drawLine(in: &session, tool: .pen, points: [CGPoint(x: 30, y: 30), CGPoint(x: 40, y: 40)])
        let original = session.strokes

        XCTAssertTrue(session.clearForUndo())
        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.canRedoClear, "the restored clear waits for redo")

        XCTAssertTrue(session.redo())
        XCTAssertTrue(session.strokes.isEmpty, "⇧⌘Z clears what ⌘Z restored")

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes, original, "the round trip can start over")
    }

    // The clear is one step: the undo after it works mark by mark, exactly
    // like the history before the clear did.
    func testUndoAfterARestoredClearRemovesSingleMarksAgain() {
        var session = DrawingSession()
        drawLine(in: &session)
        drawLine(in: &session, points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])
        let ids = session.strokes.map(\.id)

        XCTAssertTrue(session.clearForUndo())
        XCTAssertTrue(session.undo())

        XCTAssertTrue(session.undo(), "the next undo removes one mark, not both")
        XCTAssertEqual(session.strokes.map(\.id), [ids[0]])
        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.strokes.isEmpty)
    }

    // The exact contract the global history needs: after a clear the newest
    // live op is the clear, so a popped clear entry never undoes a different
    // op than the one it names.
    func testCanUndoClearMatchesTheNewestLiveOp() {
        var session = DrawingSession()
        drawLine(in: &session)
        drawLine(in: &session, points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])

        XCTAssertFalse(session.canUndoClear, "nothing was cleared yet")
        XCTAssertTrue(session.clearForUndo())
        XCTAssertTrue(session.canUndoClear)
        XCTAssertFalse(session.canUndo(markWithID: session.strokes.first?.id ?? UUID()))

        drawLine(in: &session, points: [CGPoint(x: 70, y: 70), CGPoint(x: 80, y: 80)])
        XCTAssertFalse(session.canUndoClear, "a later draw is the newest live op")

        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.canUndoClear, "the clear is newest again once the draw is undone")
    }

    func testCanRedoClearTracksTheRedoJournal() {
        var session = DrawingSession()
        drawLine(in: &session)

        XCTAssertTrue(session.clearForUndo())
        XCTAssertFalse(session.canRedoClear, "a clear is an edit: the redo history forked")

        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.canRedoClear)

        XCTAssertTrue(session.redo())
        XCTAssertFalse(session.canRedoClear)
    }

    // An empty canvas adds no history step, and it must not touch the redo
    // history either: Escape on an empty layer is a no-op.
    func testClearOfAnEmptyCanvasAddsNoHistoryStep() {
        var session = DrawingSession()

        XCTAssertFalse(session.clearForUndo())
        XCTAssertFalse(session.canUndoClear, "no step was journalled")
        XCTAssertFalse(session.undo(), "nothing to undo")

        // The empty case with an undo waiting for redo: Escape (the clear of
        // an empty canvas) must not kill it.
        drawLine(in: &session)
        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.strokes.isEmpty)

        XCTAssertFalse(session.clearForUndo())
        XCTAssertTrue(session.redo(), "the clear of an empty canvas left the redo history alone")
    }

    // An uncommitted mark is discarded by the clear, never journalled: it was
    // never part of the history.
    func testEscapeClearDiscardsTheActiveMarkWithoutJournalling() {
        var session = DrawingSession()
        session.begin(at: .zero, tool: .pen, ink: .red)
        session.extend(to: CGPoint(x: 10, y: 10))

        XCTAssertFalse(session.clearForUndo(), "no committed mark, no history step")
        XCTAssertNil(session.active)
        XCTAssertFalse(session.canUndoClear)
        XCTAssertFalse(session.undo())
    }

    // The numbered-badge rule survives the batch restore: numbers stay
    // gapless, the marks drawn after the clear keep their numbers and no
    // duplicate ever shows up.
    func testEscapeClearUndoKeepsNumberingGapless() {
        var session = DrawingSession()
        for index in 0..<3 {
            session.begin(at: CGPoint(x: CGFloat(index) * 60, y: 0), tool: .number, ink: .green)
        }

        XCTAssertTrue(session.clearForUndo())
        session.begin(at: CGPoint(x: 300, y: 0), tool: .number, ink: .green)
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1], "the new mark takes number 1 again")

        XCTAssertTrue(session.undo(), "the newest change — the draw after the clear — undoes first")
        XCTAssertTrue(session.strokes.isEmpty)

        XCTAssertTrue(session.undo(), "one undo step restores the whole cleared batch")
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2, 3], "gapless, the original numbers")
        XCTAssertEqual(session.nextStepNumber, 4)

        session.begin(at: CGPoint(x: 300, y: 0), tool: .number, ink: .green)
        XCTAssertEqual(session.strokes.compactMap(\.stepNumber), [1, 2, 3, 4], "no duplicate where number 1 was")
    }

    // MARK: - T6b/S8: the group move is one undoable step

    // Dragging a multi-selection moves every selected mark by the same delta:
    // the batch replacement carries one journal op for the whole group, ids
    // and draw order stay put, and a mark outside the selection never moves.
    func testGroupMoveTranslatesEveryMemberByTheSameDelta() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 200, y: 20), CGPoint(x: 260, y: 70)])
        drawLine(in: &session, tool: .pen, points: [CGPoint(x: 500, y: 500), CGPoint(x: 600, y: 540)])
        let first = session.strokes[0]
        let second = session.strokes[1]
        let outsider = session.strokes[2]
        let delta = CGPoint(x: 17, y: -9)
        let moved = [first, second].map { MarkTransform.translated($0, by: delta) }

        XCTAssertTrue(session.replaceBatch(moved), "the group move journals one batch step")
        XCTAssertEqual(session.strokes.map(\.id), [first.id, second.id, outsider.id],
                       "ids and draw order survive the batch"
        )
        XCTAssertEqual(session.strokes[0].points, [CGPoint(x: delta.x, y: delta.y), CGPoint(x: 100 + delta.x, y: 50 + delta.y)])
        XCTAssertEqual(session.strokes[1].points, [CGPoint(x: 200 + delta.x, y: 20 + delta.y), CGPoint(x: 260 + delta.x, y: 70 + delta.y)])
        XCTAssertEqual(session.strokes[2], outsider, "a mark outside the selection never moves")
    }

    // The owner's S8 words: a multi-selection moves together. The batch is
    // journalled once, so one ⌘Z puts every mark back exactly where it was —
    // never one undo step per mark.
    func testTheBatchMoveIsOneUndoStepThatRestoresEveryMark() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 200, y: 20), CGPoint(x: 260, y: 70)])
        let original = session.strokes
        let delta = CGPoint(x: -12, y: 6)
        let moved = Array(session.strokes).map { MarkTransform.translated($0, by: delta) }

        XCTAssertTrue(session.replaceBatch(moved))
        XCTAssertEqual(session.strokes, original.map { MarkTransform.translated($0, by: delta) },
                       "every mark moved by the same delta"
        )

        XCTAssertTrue(session.undo(), "one undo step restores the whole group")
        XCTAssertEqual(session.strokes, original, "every mark is back exactly: ids, geometry, inks")
    }

    // ⇧⌘Z after the ⌘Z apply the whole move again, and the round trip starts
    // over — the journal forks like every edit, so nothing stale follows.
    func testBatchMoveRedoReappliesTheWholeMoveInOneStep() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 200, y: 20), CGPoint(x: 260, y: 70)])
        let original = session.strokes
        let delta = CGPoint(x: 30, y: 30)
        let moved = Array(session.strokes).map { MarkTransform.translated($0, by: delta) }

        XCTAssertTrue(session.replaceBatch(moved))
        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.canRedoBatchMove, "the undone batch waits for redo")

        XCTAssertTrue(session.redo(), "one redo step reapplies the whole move")
        XCTAssertEqual(session.strokes, moved, "every mark is moved again")

        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes, original, "the round trip can start over")
    }

    // A group move with a single selected mark must be today's single-mark
    // move: one transform step, one undo restores it, the second mark untouched.
    func testABatchMoveOfASingleMarkEqualsTodaysSingleMarkMove() {
        var batch = DrawingSession()
        var single = DrawingSession()
        drawLine(in: &batch, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        drawLine(in: &batch, tool: .rectangle, points: [CGPoint(x: 200, y: 20), CGPoint(x: 260, y: 70)])
        drawLine(in: &single, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        drawLine(in: &single, tool: .rectangle, points: [CGPoint(x: 200, y: 20), CGPoint(x: 260, y: 70)])
        let batchOutsider = batch.strokes[1]
        let singleOutsider = single.strokes[1]
        let delta = CGPoint(x: 8, y: 4)
        let batchFirst = MarkTransform.translated(batch.strokes[0], by: delta)
        let singleFirst = MarkTransform.translated(single.strokes[0], by: delta)

        XCTAssertTrue(batch.replaceBatch([batchFirst]))
        XCTAssertTrue(single.replace(singleFirst))
        XCTAssertEqual(batch.strokes.map(\.points), single.strokes.map(\.points), "one moved mark ends exactly where the single route ends")
        XCTAssertEqual(batch.strokes.count, single.strokes.count)

        XCTAssertTrue(batch.undo())
        XCTAssertTrue(single.undo())
        XCTAssertEqual(batch.strokes.map(\.points), single.strokes.map(\.points), "and one undo leaves the same rest state")
        XCTAssertEqual(batch.strokes[1].points, batchOutsider.points, "the mark outside the selection never moved")
        XCTAssertEqual(single.strokes[1], singleOutsider)
    }

    // Unknown ids report failure, all-no-op batches journal nothing and fork
    // no redo history — the same no-step invariants the single replace keeps.
    func testReplaceBatchIgnoresUnknownIdsAndNoOpsWithoutAJournalledStep() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        let snapshot = session

        XCTAssertFalse(session.replaceBatch([Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 99, y: 0), CGPoint(x: 10, y: 10)]
        )]), "no mark has that id")
        XCTAssertEqual(session, snapshot, "an unknown id touched nothing, journals included")

        let noOp = Array(session.strokes)
        XCTAssertFalse(session.replaceBatch(noOp), "nothing changed, so there is no step")
        XCTAssertEqual(session, snapshot, "a no-op batch never touches the journals")
    }

    // A batch member the eraser took away afterwards stays gone: the undo
    // skips the stale member and still restores the live ones.
    func testBatchMoveUndoSkipsAMemberErasedAfterwards() {
        var session = DrawingSession()
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)])
        drawLine(in: &session, tool: .rectangle, points: [CGPoint(x: 200, y: 20), CGPoint(x: 260, y: 70)])
        let original = [session.strokes[1]]
        let delta = CGPoint(x: 10, y: 0)
        let moved = Array(session.strokes).map { MarkTransform.translated($0, by: delta) }

        XCTAssertTrue(session.replaceBatch(moved))
        XCTAssertTrue(!session.erase(at: CGPoint(x: 13, y: 25), radius: 6).isEmpty, "the eraser takes the first mark away")
        XCTAssertEqual(session.strokes.count, 1)

        XCTAssertTrue(session.undo(), "the batch undo still answers")
        XCTAssertEqual(session.strokes, original, "the live member comes back; the erased one stays gone")
    }

    // The contract the global history needs: after a batch move the newest
    // live op is the batch, so a popped batch-move entry can never undo a
    // different change than the one it names — and no single-mark entry is
    // answered first either.
    func testCanUndoBatchMoveMatchesTheNewestLiveOp() {
        var session = DrawingSession()
        drawLine(in: &session)
        drawLine(in: &session, points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)])

        XCTAssertFalse(session.canUndoBatchMove, "no group moved yet")
        session.replaceBatch(Array(session.strokes).map { MarkTransform.translated($0, by: CGPoint(x: 5, y: 5)) })
        XCTAssertTrue(session.canUndoBatchMove)
        for stroke in session.strokes {
            XCTAssertFalse(session.canUndo(markWithID: stroke.id),
                           "a single-mark entry is never answered while the batch is newest live"
            )
        }

        drawLine(in: &session, points: [CGPoint(x: 70, y: 70), CGPoint(x: 80, y: 80)])
        XCTAssertFalse(session.canUndoBatchMove, "a later draw is the newest live op")

        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.canUndoBatchMove, "the batch is newest again once the draw is undone")
        XCTAssertTrue(session.undo())
        XCTAssertFalse(session.canUndoBatchMove, "and once it is undone, nothing batch is live")
    }

    func testCanRedoBatchMoveTracksTheRedoJournal() {
        var session = DrawingSession()
        drawLine(in: &session)

        let moved = [MarkTransform.translated(session.strokes[0], by: CGPoint(x: 5, y: 5))]
        XCTAssertTrue(session.replaceBatch(moved))
        XCTAssertFalse(session.canRedoBatchMove, "a move is an edit: the redo history forked")

        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.canRedoBatchMove)
        XCTAssertFalse(session.canRedo(markWithID: session.strokes.first?.id ?? UUID()),
                       "a batch entry is not a single mark's entry")

        XCTAssertTrue(session.redo())
        XCTAssertFalse(session.canRedoBatchMove)
    }

    // MARK: Session persistence (T10/S11)

    /// Draws one pen line and one numbered badge, then one laser mark on top,
    /// used by the persistence tests below.
    private func mixedSession() -> DrawingSession {
        var session = DrawingSession()
        drawLine(in: &session, points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        session.begin(at: CGPoint(x: 30, y: 30), tool: .number, ink: .green)
        let now = Date()
        session.begin(at: CGPoint(x: 50, y: 50), tool: .laser, ink: .red, now: now)
        session.extend(to: CGPoint(x: 60, y: 60))
        session.commit()
        return session
    }

    func testPersistedStrokesExcludeLaserMarks() {
        let session = mixedSession()

        XCTAssertEqual(session.persistedStrokes, session.strokes.filter { !$0.tool.isTransient })
        XCTAssertEqual(session.persistedStrokes.count, session.strokes.count - 1)
    }

    func testRestoredSessionRebuildsMarkIdentityGeometryInkToolAndNumbering() {
        let session = mixedSession()

        let restored = DrawingSession.restored(strokes: session.strokes)
        XCTAssertEqual(restored.strokes, session.persistedStrokes, "ids, geometry, ink, tool and numbering come back exactly, without the transient mark")
        XCTAssertEqual(restored.nextStepNumber, session.nextStepNumber, "the numbered sequence continues where it left off")
        XCTAssertNil(restored.active, "an in-progress mark is never restored")
    }

    func testRestoredSessionDropsTransientMarksEvenFromAHandBuiltPayload() {
        // A stale or hand-edited payload that still carries a laser mark must
        // not resurrect it: it would have faded anyway.
        let restored = DrawingSession.restored(strokes: mixedSession().strokes)
        XCTAssertFalse(restored.strokes.contains { $0.tool.isTransient })
        XCTAssertEqual(restored.strokes.count, 2)
    }

    func testRestoredSessionOfNothingIsEmpty() {
        let restored = DrawingSession.restored(strokes: [])
        XCTAssertTrue(restored.isEmpty)
        XCTAssertEqual(restored.nextStepNumber, 1)
    }

    /// Pen stroke with every field a mark can carry, encoded once for the
    /// round trips.
    private static func featuredPersistedStroke(
        id: UUID = UUID(),
        tool: Tool,
        stepNumber: Int? = nil,
        text: String? = nil,
        textSize: CGSize? = nil,
        createdAt: Date? = nil,
        badgeSize: CGFloat? = nil,
        rotation: CGFloat = 0
    ) -> PersistedStroke {
        let stroke = Stroke(
            id: id,
            tool: tool,
            ink: .purple,
            points: [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)],
            stepNumber: stepNumber,
            text: text,
            textSize: textSize,
            createdAt: createdAt,
            badgeSize: badgeSize,
            rotation: rotation
        )
        return stroke.persisted
    }

    func testPersistedStrokeEncodesToolAndInkAsRawValuesAndRoundTrips() throws {
        let stroke = Self.featuredPersistedStroke(tool: .number, stepNumber: 1)

        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(PersistedStroke.self, from: data)
        XCTAssertEqual(decoded, stroke)

        let restored = Stroke(persisted: decoded)
        XCTAssertEqual(restored?.id, stroke.id)
        XCTAssertEqual(restored?.tool, Tool.number)
        XCTAssertEqual(restored?.ink, Ink.purple)
        XCTAssertEqual(restored?.points, [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)])
        XCTAssertEqual(restored?.stepNumber, 1)
    }

    func testPersistedStrokeRestoresEveryField() {
        let stamp = Date(timeIntervalSince1970: 100)
        let stroke = Self.featuredPersistedStroke(
            tool: .text,
            text: "hello",
            textSize: CGSize(width: 40, height: 12),
            createdAt: stamp,
            badgeSize: 30,
            rotation: 0.5
        )

        let restored = Stroke(persisted: stroke)
        XCTAssertEqual(restored?.text, "hello")
        XCTAssertEqual(restored?.textSize, CGSize(width: 40, height: 12))
        XCTAssertEqual(restored?.createdAt, stamp)
        XCTAssertEqual(restored?.badgeSize, 30)
        XCTAssertEqual(restored?.rotation, 0.5)
    }

    func testPersistedStrokeWithAnUnknownToolIsDroppedNotMisrendered() throws {
        // A foreign document that names a tool this build does not know: the
        // mark is dropped (it behaves like a fresh launch) instead of a wrong
        // shape appearing on screen.
        var stroke = Self.featuredPersistedStroke(tool: .pen)
        stroke.tool = "galaxy"

        XCTAssertNil(Stroke(persisted: stroke))
    }

    func testPersistedStrokeWithAnUnknownInkFallsBackToTheDefault() throws {
        var stroke = Self.featuredPersistedStroke(tool: .pen)
        stroke.ink = "void"

        XCTAssertEqual(Stroke(persisted: stroke)?.ink, Ink.red, "an unknown ink falls back like the blob's own fields do")
    }

    // MARK: Boot session store (T10/S11)

    /// One pen mark's persisted form, shared by the store tests.
    private static func penPersistedStroke(id: UUID = UUID()) -> PersistedStroke {
        let stroke = Stroke(tool: .pen, ink: .red, points: [CGPoint(x: 2, y: 3), CGPoint(x: 8, y: 9)])
        return Stroke(id: id, tool: stroke.tool, ink: stroke.ink, points: stroke.points).persisted
    }

    private static func archive(boot: Date, strokeID: UUID = UUID()) -> SessionArchive {
        SessionArchive(
            bootTime: boot,
            displays: ["123": [penPersistedStroke()]],
            boards: ["123": PersistedBoard(pages: [], currentIndex: 0)]
        )
    }

    func testSessionArchiveRoundTripsThroughTheStoreWithinTheSameBoot() {
        let store = InMemoryPreferenceStore()
        let bootTime = Date(timeIntervalSince1970: 1000)
        let sessionStore = BootSessionStore(store: store, bootTime: { bootTime })
        let archive = Self.archive(boot: bootTime)

        sessionStore.save(archive)

        let reloaded = BootSessionStore(store: store, bootTime: { bootTime }).load()
        XCTAssertEqual(reloaded, archive, "a session stored this boot is restored this boot")
    }

    func testSessionArchiveFromAnEarlierBootIsDiscarded() {
        let store = InMemoryPreferenceStore()
        let earlierBoot = Date(timeIntervalSince1970: 1000)
        BootSessionStore(store: store, bootTime: { earlierBoot }).save(Self.archive(boot: earlierBoot))

        // The machine restarted: the new boot's instant is a different one.
        let afterRestart = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(BootSessionStore(store: store, bootTime: { afterRestart }).load())
    }

    func testCorruptStoredSessionBehavesLikeAFreshLaunch() {
        let store = InMemoryPreferenceStore()
        let bootTime = Date(timeIntervalSince1970: 1000)
        let sessionStore = BootSessionStore(store: store, bootTime: { bootTime })
        sessionStore.save(Self.archive(boot: bootTime))
        store.set(Data("not json at all".utf8), forKey: SessionArchive.storageKey)

        XCTAssertNil(sessionStore.load(), "a corrupt payload must never fail the launch")
    }

    func testSessionStoreDropsStoredData() {
        let store = InMemoryPreferenceStore()
        let bootTime = Date(timeIntervalSince1970: 1000)
        let sessionStore = BootSessionStore(store: store, bootTime: { bootTime })
        sessionStore.save(Self.archive(boot: bootTime))

        sessionStore.drop()

        XCTAssertNil(BootSessionStore(store: store, bootTime: { bootTime }).load())
    }

    func testSessionStoreSkipsTheWriteWhenTheBootClockIsUnknown() {
        // With no boot instant the store cannot tag the session, so it must
        // not write untagged data a later boot could resurrect.
        let store = InMemoryPreferenceStore()
        let sessionStore = BootSessionStore(store: store, bootTime: { nil })

        sessionStore.save(Self.archive(boot: Date()))

        XCTAssertNil(store.data(forKey: SessionArchive.storageKey))
    }

    func testSessionStoreOfAnEmptyStoreIsFresh() {
        XCTAssertNil(BootSessionStore(store: InMemoryPreferenceStore(), bootTime: { Date() }).load())
    }

    // MARK: - S15 slice A: shape fill, arrow-head styles, remembered text style

    private func decoded(_ data: Data) throws -> Stroke? {
        Stroke(persisted: try JSONDecoder().decode(PersistedStroke.self, from: data))
    }

    /// A document written before fill and arrow heads existed simply carries
    /// no such keys: the restored mark must be outline with the open head,
    /// never a filled shape resurrected by a decode default.
    func testLegacyPersistedStrokeWithoutTheNewFieldsDecodesOutlineAndOpen() throws {
        let json = Data("""
        {"id":"11111111-1111-1111-1111-111111111111","tool":"rectangle","ink":"blue",\
         "points":[[10,20],[30,40]],"stepNumber":null,"text":null,\
         "textSize":null,"createdAt":null,"badgeSize":null,"rotation":0}
        """.utf8)
        let restored = try XCTUnwrap(decoded(json))
        XCTAssertEqual(restored.tool, .rectangle)
        XCTAssertEqual(restored.ink, .blue)
        XCTAssertFalse(restored.isFilled, "a legacy mark must restore as an outline")
        XCTAssertEqual(restored.arrowHead, .open, "a legacy mark must restore the open head")
    }

    /// The plain keys `9` and `0` are free for the new style keys: no tool
    /// letter claims them, no ink digit answers them, and a rebound map entry
    /// keeps winning before any plain-key decision (the view routes the
    /// shortcut map first).
    func testFillAndArrowHeadKeysAreFreeOfCollisions() {
        XCTAssertNil(Tool.allCases.first { $0.shortcut == "9" || $0.shortcut == "0" },
                     "no tool must claim the style keys")
        XCTAssertNil(ToolShortcutMap.standard.tool(for: "9"))
        XCTAssertNil(ToolShortcutMap.standard.tool(for: "0"))

        for digit in 1...8 {
            guard case .ink = ShortcutRouter.resolve(Character("\(digit)")) else {
                return XCTFail("digit \(digit) must select its ink")
            }
        }
        XCTAssertEqual(ShortcutRouter.resolve("9"), .none)
        XCTAssertEqual(ShortcutRouter.resolve("0"), .none, "no ink lives on 0")

        var rebound = ToolShortcutMap.standard
        guard case .success = rebound.assigning("9", to: .pen) else {
            return XCTFail("9 must be assignable to a tool in a custom map")
        }
        XCTAssertEqual(ShortcutRouter(shortcuts: rebound).resolve("9"), .tool(.pen),
                       "a rebound entry must win over the plain style key")
    }

    private func roundTrip(_ stroke: Stroke) throws -> Stroke? {
        try decoded(try JSONEncoder().encode(stroke.persisted))
    }

    /// The fill and the head ride the documented persistence seam, so a
    /// snapshot and the capture history restore the shape the user drew.
    func testPersistedRoundTripCarriesFillAndArrowHead() throws {
        let rectangle = Stroke(tool: .rectangle, ink: .blue, points: [CGPoint(x: 1, y: 2), CGPoint(x: 30, y: 40)], fill: true)
        let arrow = Stroke(tool: .arrow, ink: .red, points: [.zero, CGPoint(x: 10, y: 10)], arrowHead: .filled)
        for stroke in [rectangle, arrow] {
            let restored = try XCTUnwrap(roundTrip(stroke))
            XCTAssertEqual(restored, stroke, "\(stroke.tool.rawValue) must survive the round trip whole")
        }
    }

    /// A raw value this build does not know can only mean the shipped head:
    /// a foreign document must never draw a shape nobody drew.
    func testUnknownArrowHeadRawValueRestoresOpen() throws {
        var stroke = Stroke(tool: .arrow, ink: .red, points: [.zero, CGPoint(x: 10, y: 10)], arrowHead: .filled)
        // Hand-write the document so the raw value is truly foreign.
        let data = try JSONEncoder().encode(stroke.persisted)
        let corrupted = String(data: data, encoding: .utf8)!
            .replacingOccurrences(of: "filled", with: "chevron")
        let restored = try XCTUnwrap(decoded(Data(corrupted.utf8)))
        XCTAssertEqual(restored.arrowHead, .open, "an unknown head must fall back to open")
    }

    /// The remembered text style (S15): the next text mark starts with the
    /// style of the last committed one.
    func testRememberedTextStyleHoldsTheLastCommittedStyle() {
        var session = DrawingSession()
        XCTAssertNil(session.lastTextStyle, "a fresh session starts with no memory")

        session.rememberTextStyle(.init(fontSize: 26, ink: .purple))
        XCTAssertEqual(session.lastTextStyle, .init(fontSize: 26, ink: .purple))

        session.rememberTextStyle(.init(fontSize: 14, ink: .green))
        XCTAssertEqual(session.lastTextStyle, .init(fontSize: 14, ink: .green),
                       "the newest committed text decides")
    }

    func testRememberedTextStyleRefusesAnUnusableSize() {
        var session = DrawingSession()
        session.rememberTextStyle(.init(fontSize: 26, ink: .purple))
        session.rememberTextStyle(.init(fontSize: 0, ink: .green))
        session.rememberTextStyle(.init(fontSize: -3, ink: .green))
        XCTAssertEqual(session.lastTextStyle, .init(fontSize: 26, ink: .purple),
                       "garbage styles never displace a good memory")
    }

    /// The style memory is session-scoped: a cleared session forgets it.
    func testClearingTheSessionForgetsTheRememberedTextStyle() {
        var session = DrawingSession()
        session.rememberTextStyle(.init(fontSize: 26, ink: .purple))
        session.clear()
        XCTAssertNil(session.lastTextStyle, "a cleared session starts text over")
    }

    /// The restore seam rebuilds marks from a snapshot; the style memory
    /// belongs to the live session and restarts with it.
    func testRestoredSessionForgetsTheRememberedTextStyle() {
        var live = DrawingSession()
        live.rememberTextStyle(.init(fontSize: 26, ink: .purple))
        live.begin(at: .zero, tool: .text, ink: .purple)
        live.setActiveText("a", size: nil)
        live.commit()

        let restored = DrawingSession.restored(strokes: live.strokes)
        XCTAssertNil(restored.lastTextStyle, "a restored session has no style memory")
        XCTAssertNotEqual(restored, live, "the memory is part of what makes sessions distinct")
    }

    /// The plain `begin` — what every surface that has not adopted the style
    /// keys calls — keeps today's outline and open head.
    func testBeginDefaultsToOutlineAndOpenHead() {
        for tool in [Tool.pen, .line, .rectangle, .ellipse, .arrow, .text, .number, .blur] {
            var session = DrawingSession()
            session.begin(at: .zero, tool: tool, ink: .red)
            guard let mark = session.active ?? session.strokes.last else {
                return XCTFail("\(tool.rawValue) must lay a mark")
            }
            XCTAssertFalse(mark.isFilled, "\(tool.rawValue) must default to outline")
            XCTAssertEqual(mark.arrowHead, .open, "\(tool.rawValue) must default to the open head")
        }
    }

    /// A style property is stored only on the tool it belongs to: the keys arm
    /// the next *shape*, the next *arrow* — a pen or line never carries them.
    func testBeginStoresTheStyleOnlyOnTheToolItBelongsTo() {
        var session = DrawingSession()
        session.begin(at: .zero, tool: .rectangle, ink: .red, fill: true, arrowHead: .filled)
        let shape = session.active ?? session.strokes.last
        XCTAssertEqual(shape?.isFilled, true)
        XCTAssertEqual(shape?.arrowHead, .open, "an open-by-default head never rides a shape")

        var arrows = DrawingSession()
        arrows.begin(at: .zero, tool: .arrow, ink: .red, fill: true, arrowHead: .filled)
        let arrow = arrows.active ?? arrows.strokes.last
        XCTAssertEqual(arrow?.arrowHead, .filled)
        XCTAssertEqual(arrow?.isFilled, false, "a fill never rides an arrow")

        var others = DrawingSession()
        others.begin(at: .zero, tool: .pen, ink: .red, fill: true, arrowHead: .filled)
        let other = others.active ?? others.strokes.last
        XCTAssertEqual(other?.isFilled, false)
        XCTAssertEqual(other?.arrowHead, .open)
    }

    /// The style is a property of the mark: commit, undo, redo and the editor
    /// transforms all keep whatever the mark was drawn with.
    func testFillAndHeadSurviveCommitUndoRedoAndReplace() {
        var session = DrawingSession()
        session.begin(at: .zero, tool: .rectangle, ink: .red, fill: true)
        session.extend(to: CGPoint(x: 50, y: 40))
        session.commit()
        let drawn = session.strokes.first
        XCTAssertEqual(drawn?.isFilled, true)

        var moved = MarkTransform.translated(session.strokes[0], by: CGPoint(x: 5, y: 5))
        XCTAssertTrue(session.replace(moved))
        XCTAssertTrue(session.strokes.first!.isFilled)
        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.strokes.first!.isFilled, "undo restores the filled mark")
        XCTAssertTrue(session.strokes.first! == drawn!)
        XCTAssertTrue(session.redo())
        XCTAssertTrue(session.strokes.first!.isFilled, "redo reapplies the transform with the style intact")
    }

    func testArrowHeadSurvivesCommitAndUndoRedo() {
        var session = DrawingSession()
        session.begin(at: .zero, tool: .arrow, ink: .red, arrowHead: .filled)
        session.extend(to: CGPoint(x: 50, y: 40))
        session.commit()
        XCTAssertEqual(session.strokes.first?.arrowHead, .filled)

        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes.first?.arrowHead, .filled)
        XCTAssertEqual(session.undoneStrokes, [])
    }

    // MARK: - S15 slice B: the spotlight is a mark like any other

    /// The tool arrives through its persisted raw value, so these tests run
    /// (and fail) before the case exists instead of failing to compile.
    private func spotlightTool() throws -> Tool {
        try XCTUnwrap(Tool(rawValue: "spotlight"), "the spotlight tool must exist")
    }

    /// A spotlight spans the dragged rectangle and nothing else: the commit
    /// collapses it to its endpoints exactly like the blur.
    func testSpotlightCommitsAsAnEndpointsOnlyAreaMark() throws {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 10, y: 10), tool: try spotlightTool(), ink: .black)
        session.extend(to: CGPoint(x: 40, y: 30))
        session.extend(to: CGPoint(x: 80, y: 60))
        session.commit()

        XCTAssertEqual(session.strokes.count, 1)
        XCTAssertEqual(
            session.strokes[0].points,
            [CGPoint(x: 10, y: 10), CGPoint(x: 80, y: 60)],
            "a spotlight keeps only the drag's endpoints"
        )
    }

    /// A mark, not a pointer effect: undo takes it away, redo brings it back,
    /// and the editor's move round trip keeps it whole.
    func testSpotlightSurvivesUndoRedoAndAMove() throws {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 10, y: 10), tool: try spotlightTool(), ink: .black)
        session.extend(to: CGPoint(x: 60, y: 50))
        session.commit()
        let original = session.strokes[0]

        XCTAssertTrue(session.undo())
        XCTAssertTrue(session.strokes.isEmpty)
        XCTAssertTrue(session.redo())
        XCTAssertEqual(session.strokes, [original])

        let moved = MarkTransform.translated(original, by: CGPoint(x: 15, y: 5))
        XCTAssertTrue(session.replace(moved))
        XCTAssertEqual(session.strokes, [moved])
        XCTAssertTrue(session.undo())
        XCTAssertEqual(session.strokes, [original], "undo restores the pre-move geometry")
    }

    /// The eraser reads the spotlight as an area, like the blur: a point
    /// inside the dragged rectangle touches the mark, a point outside does
    /// not.
    func testEraserTakesASpotlightByItsArea() throws {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 10, y: 10), tool: try spotlightTool(), ink: .black)
        session.extend(to: CGPoint(x: 80, y: 60))
        session.commit()
        let id = session.strokes[0].id

        XCTAssertEqual(session.erase(at: CGPoint(x: 45, y: 35)), [id], "the interior erases")

        session.redo()
        XCTAssertTrue(session.erase(at: CGPoint(x: 5, y: 5)).isEmpty, "outside the rect nothing erases")
    }

    /// The mark rides the documented persistence seam whole, so a snapshot
    /// and the capture history restore the region the user framed.
    func testSpotlightRoundTripsThroughThePersistenceSeam() throws {
        let stroke = Stroke(
            tool: try spotlightTool(),
            ink: .black,
            points: [CGPoint(x: 5, y: 6), CGPoint(x: 70, y: 45)]
        )
        let restored = try XCTUnwrap(
            decoded(try JSONEncoder().encode(stroke.persisted))
        )
        XCTAssertEqual(restored, stroke, "the spotlight must survive the round trip whole")
    }

    /// The premise that lets the undo history survive a mode cycle: a restored
    /// session keeps every stroke's id. The controller's entries name marks by
    /// id, and the board and the overlay restore their session on the way in —
    /// if the ids changed, the steps would name marks that no longer exist.
    func testRestoredStrokesKeepTheirIds() {
        let stroke = Stroke(
            tool: .pen,
            ink: .red,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]
        )
        let restored = DrawingSession.restored(strokes: [stroke])
        XCTAssertEqual(restored.strokes.first?.id, stroke.id)
        XCTAssertEqual(restored.strokes.first?.points, stroke.points)
    }

    /// A mode's restore is undoable like a drawing: the journal comes back with
    /// the marks, which is what makes ⌘Z work after a mode cycle instead of
    /// finding an empty journal (the log showed every restored step skipped).
    /// `restored(strokes:)` stays unjournalled on purpose — the capture editor
    /// seeds the marks a capture ARRIVED with, and those are its baseline.
    func testARestoredSessionCanUndoItsOwnMarks() {
        let first = Stroke(tool: .pen, ink: .red, points: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5)])
        let second = Stroke(tool: .pen, ink: .blue, points: [CGPoint(x: 9, y: 9), CGPoint(x: 12, y: 12)])
        var restored = DrawingSession.restoredUndoable(strokes: [first, second])

        XCTAssertTrue(restored.canUndo(markWithID: second.id), "the newest restored mark is undoable")
        XCTAssertTrue(restored.undo())
        XCTAssertEqual(restored.strokes.map(\.id), [first.id], "undo removed the newest restored mark")
        XCTAssertTrue(restored.canUndo(markWithID: first.id))
        XCTAssertTrue(restored.undo())
        XCTAssertTrue(restored.strokes.isEmpty, "and then the one before it")
    }
}
