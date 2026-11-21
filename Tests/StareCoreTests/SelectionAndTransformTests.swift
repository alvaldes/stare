import CoreGraphics
import XCTest

import StareCore

/// T11/S6 slice 1: the selection cursor, stroke rotation metadata, the
/// selection handles and the transform geometry — all pure StareCore.
final class SelectionAndTransformTests: XCTestCase {
    // MARK: - Select tool

    // T11/S6: the cursor edits what was painted; by itself it draws nothing,
    // so a stray click or drag with it must leave no mark and hit nothing.
    func testSelectToolDrawsNothing() {
        let stroke = Stroke(
            tool: .select,
            ink: .red,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 60)]
        )

        XCTAssertTrue(PathBuilder.path(for: stroke).isEmpty, "the select tool has no geometry")
        XCTAssertFalse(stroke.hitTest(CGPoint(x: 20, y: 30), radius: 6), "a select-tool mark is never hit")
    }

    // MARK: - Translate

    // Moving bakes the delta into the points: translation never deforms, so the
    // rotation stays 0 and the size is untouched.
    func testTranslatingBakesTheDeltaIntoThePoints() {
        let rect = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 20, y: 30), CGPoint(x: 120, y: 80)]
        )

        let moved = MarkTransform.translated(rect, by: CGPoint(x: 15, y: -7))

        XCTAssertEqual(moved.points, [CGPoint(x: 35, y: 23), CGPoint(x: 135, y: 73)])
        XCTAssertEqual(PathBuilder.normalizedRect(from: moved.points[0], to: moved.points[1]).size,
                       CGSize(width: 100, height: 50), "the shape keeps its size")
        XCTAssertEqual(moved.rotation, 0)
    }

    // MARK: - Scale

    // The uniform factor is the pure distance ratio: a free drag on one axis
    // still yields one uniform factor.
    func testScaleFactorIsTheDistanceRatioFromTheAnchor() {
        XCTAssertEqual(
            MarkTransform.scaleFactor(
                from: CGPoint(x: 10, y: 10),
                draggedCorner: CGPoint(x: 110, y: 60),
                to: CGPoint(x: 160, y: 60)
            ),
            (2 as CGFloat).squareRoot(),
            accuracy: 0.001,
            "a one-axis drag still yields one uniform factor"
        )
    }

    // T11/S6 defect E: a corner drag resolves through the selection handles —
    // a 2× drag is exactly 2×, the aspect ratio never changes, and the
    // opposite handle stays exactly where it was.
    func testScalingFromACornerKeepsTheOppositeHandleStillAndTheRatioExact() {
        let rect = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 60)]
        )
        let before = MarkSelection(stroke: rect)
        let handles = before.handlePoints(rotationHandleOffset: 20)
        let anchor = handles[.topLeft]!
        let dragged = handles[.bottomRight]!
        let pointer = CGPoint(
            x: anchor.x + 2 * (dragged.x - anchor.x),
            y: anchor.y + 2 * (dragged.y - anchor.y)
        )

        let scaled = MarkTransform.scaled(rect, dragging: .bottomRight, to: pointer)

        let after = MarkSelection(stroke: scaled)
        let kept = after.handlePoints(rotationHandleOffset: 20)[.topLeft]!
        XCTAssertEqual(kept.x, anchor.x, accuracy: 0.5, "the opposite handle stays where it was")
        XCTAssertEqual(kept.y, anchor.y, accuracy: 0.5, "the opposite handle stays where it was")

        let oldBox = PathBuilder.path(for: rect).boundingBoxOfPath
        let newBox = PathBuilder.path(for: scaled).boundingBoxOfPath
        XCTAssertEqual(newBox.width / oldBox.width, 2, accuracy: 0.01, "a 2× drag is exactly 2×")
        XCTAssertEqual(newBox.height / oldBox.height, 2, accuracy: 0.01, "a 2× drag is exactly 2×")
        XCTAssertEqual(
            newBox.width / newBox.height,
            oldBox.width / oldBox.height,
            accuracy: 0.01,
            "the aspect ratio never changes"
        )
    }

    // T11/S6 defect E: the same contract on rotated marks, where the old
    // padded-corner anchor drifted the opposite handle.
    func testScalingARotatedMarkKeepsTheOppositeHandleStill() {
        for angle in [CGFloat.pi / 2, .pi / 4] {
            let rect = Stroke(
                tool: .rectangle,
                ink: .red,
                points: [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 60)]
            )
            let rotated = MarkTransform.rotated(rect, by: angle)
            let before = MarkSelection(stroke: rotated)
            let handles = before.handlePoints(rotationHandleOffset: 20)
            let anchor = handles[.topLeft]!
            let dragged = handles[.bottomRight]!
            let pointer = CGPoint(
                x: anchor.x + 2 * (dragged.x - anchor.x),
                y: anchor.y + 2 * (dragged.y - anchor.y)
            )

            let scaled = MarkTransform.scaled(rotated, dragging: .bottomRight, to: pointer)

            let after = MarkSelection(stroke: scaled)
            let kept = after.handlePoints(rotationHandleOffset: 20)[.topLeft]!
            XCTAssertEqual(kept.x, anchor.x, accuracy: 0.5, "opposite handle must not move at \(angle) rad")
            XCTAssertEqual(kept.y, anchor.y, accuracy: 0.5, "opposite handle must not move at \(angle) rad")

            let oldBox = PathBuilder.path(for: rotated).boundingBoxOfPath
            let newBox = PathBuilder.path(for: scaled).boundingBoxOfPath
            XCTAssertEqual(newBox.width / oldBox.width, 2, accuracy: 0.01, "a 2× drag is exactly 2× at \(angle) rad")
            XCTAssertEqual(newBox.height / oldBox.height, 2, accuracy: 0.01, "a 2× drag is exactly 2× at \(angle) rad")
        }
    }

    // Text scales as a whole: textSize grows with the geometry and the content
    // is never touched.
    func testScalingATextMarkScalesItsSizeAndKeepsItsText() {
        let text = Stroke(
            tool: .text,
            ink: .blue,
            points: [CGPoint(x: 10, y: 10)],
            text: "Hola",
            textSize: CGSize(width: 100, height: 24)
        )

        let scaled = MarkTransform.scaled(text, from: .zero, by: 2)

        XCTAssertEqual(scaled.textSize, CGSize(width: 200, height: 48))
        XCTAssertEqual(scaled.text, "Hola")
        XCTAssertEqual(scaled.points.first, CGPoint(x: 20, y: 20), "the origin scales with the mark")
    }

    // MARK: - Rotate

    // T11/S6: "No debe permitir cambiar de forma" — rotation is metadata, so a
    // rotated rectangle is still a rectangle built from the same two points.
    func testRotatingSetsRotationAndLeavesThePointsUntouched() {
        let rect = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 60)]
        )
        let snapshot = rect.points

        let rotated = MarkTransform.rotated(rect, by: .pi / 4)

        XCTAssertEqual(rotated.rotation, .pi / 4, accuracy: 0.0001)
        XCTAssertEqual(rotated.points, snapshot, "rotation must not be baked into the points")
        XCTAssertEqual(PathBuilder.bounds(for: rotated), PathBuilder.bounds(for: rect),
                       "the mark still renders from the same geometry, so the shape is unchanged")
    }

    // A rotated mark is hit where it looks: the query point is rotated back
    // into the mark's own space before testing.
    func testHitTestFollowsTheRotation() {
        let blur = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 20)]
        )
        let rotated = MarkTransform.rotated(blur, by: .pi / 2)

        // (50, 50) is inside the rotated area but far outside the unrotated box.
        XCTAssertFalse(blur.hitTest(CGPoint(x: 50, y: 50), radius: 1))
        XCTAssertTrue(rotated.hitTest(CGPoint(x: 50, y: 50), radius: 1), "inside the rotated mark")
        // (65, 15) sits inside the unrotated box, but the rotated mark is not there.
        XCTAssertTrue(blur.hitTest(CGPoint(x: 65, y: 15), radius: 1))
        XCTAssertFalse(rotated.hitTest(CGPoint(x: 65, y: 15), radius: 1), "only inside the unrotated box")
    }

    // The rotated bounding box grows to contain the whole rotated mark: this is
    // what culling uses.
    func testDisplayBoundsEnclosesTheRotatedMark() {
        let square = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)]
        )
        let rotated = MarkTransform.rotated(square, by: .pi / 4)

        XCTAssertGreaterThan(rotated.displayBounds.width, square.bounds.width)
        XCTAssertGreaterThan(rotated.displayBounds.height, square.bounds.height)

        let transform = Stroke.rotationTransform(around: square.anchor, by: .pi / 4)
        let corners = [
            square.bounds.origin,
            CGPoint(x: square.bounds.maxX, y: square.bounds.minY),
            CGPoint(x: square.bounds.maxX, y: square.bounds.maxY),
            CGPoint(x: square.bounds.minX, y: square.bounds.maxY),
        ]
        for corner in corners {
            XCTAssertTrue(
                rotated.displayBounds.insetBy(dx: -0.5, dy: -0.5).contains(corner.applying(transform)),
                "displayBounds must contain the rotated corner \(corner)"
            )
        }
    }

    // MARK: - Selection handles

    // The handles sit where the rotated mark shows its corners: the rotation
    // handle floats above the top centre, the body answers inside, and far
    // away nothing is grabbed.
    func testSelectionHandlesAnswerTheGrabbedHandle() {
        let stroke = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)]
        )
        let selection = MarkSelection(stroke: stroke)

        XCTAssertEqual(selection.handle(at: CGPoint(x: 0, y: 0), handleSize: 12, rotationHandleOffset: 20), .topLeft)
        XCTAssertEqual(selection.handle(at: CGPoint(x: 100, y: 50), handleSize: 12, rotationHandleOffset: 20), .bottomRight)
        XCTAssertEqual(selection.handle(at: CGPoint(x: 50, y: -20), handleSize: 12, rotationHandleOffset: 20), .rotation)
        XCTAssertEqual(selection.handle(at: CGPoint(x: 50, y: 25), handleSize: 12, rotationHandleOffset: 20), .body)
        XCTAssertNil(selection.handle(at: CGPoint(x: 300, y: 300), handleSize: 12, rotationHandleOffset: 20))
    }

    // A rotated mark offers its handles where it looks, not where it was drawn.
    func testSelectionHandlesFollowTheRotation() {
        let stroke = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)]
        )
        let rotated = MarkTransform.rotated(stroke, by: .pi / 2)
        let selection = MarkSelection(stroke: rotated)

        // The top-left corner of the mark lands at (75, -25) once rotated a
        // quarter turn about its centre.
        XCTAssertEqual(selection.handle(at: CGPoint(x: 75, y: -25), handleSize: 12, rotationHandleOffset: 20), .topLeft)
        XCTAssertEqual(selection.handle(at: CGPoint(x: 50, y: 25), handleSize: 12, rotationHandleOffset: 20), .body)
    }

    // MARK: - T11/S6 slice 2: what the cursor grabs

    // Closed shapes and area marks are grabbed by their (rotated) box: the
    // interior of a rectangle is editable, not only its outline.
    func testCursorSelectsClosedShapesByTheirBox() {
        let rect = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 60)]
        )

        XCTAssertTrue(rect.isSelectedByCursor(at: CGPoint(x: 60, y: 35), radius: 10), "the interior answers")
        XCTAssertTrue(rect.isSelectedByCursor(at: CGPoint(x: 10, y: 35), radius: 10), "the outline answers")
        XCTAssertFalse(rect.isSelectedByCursor(at: CGPoint(x: 200, y: 200), radius: 10))

        // The box follows the rotation, so a rotated shape is grabbed where it
        // now looks, not where it was drawn. A point near the old left edge is
        // inside the unrotated box but outside the rotated one; the same point
        // carried around the anchor is inside the rotated one.
        let rotated = MarkTransform.rotated(rect, by: .pi / 2)
        let rotation = Stroke.rotationTransform(around: rotated.anchor, by: .pi / 2)
        let probe = CGPoint(x: 15, y: 15)
        XCTAssertTrue(rect.isSelectedByCursor(at: probe, radius: 10), "inside the unrotated box")
        XCTAssertFalse(
            rotated.isSelectedByCursor(at: probe, radius: 10),
            "that spot is empty once rotated"
        )
        XCTAssertTrue(rotated.isSelectedByCursor(at: probe.applying(rotation), radius: 10))
    }

    // Freehand ink stays outline-only: the empty middle of its bounding box
    // must not grab the mark.
    func testCursorSelectsFreehandOnlyOnTheInk() {
        let pen = Stroke(
            tool: .pen,
            ink: .red,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        )

        XCTAssertTrue(pen.isSelectedByCursor(at: CGPoint(x: 50, y: 0), radius: 10))
        XCTAssertFalse(pen.isSelectedByCursor(at: CGPoint(x: 50, y: 30), radius: 10), "inside the box but off the ink")
        XCTAssertFalse(pen.isSelectedByCursor(at: CGPoint(x: 50, y: 60), radius: 10))
    }

    // MARK: - T11/S6 advisory A: a numbered badge scales with its mark

    // The badge diameter is a stored property of the mark, exactly like text
    // stores its box: a numbered mark created through the session carries the
    // size it was drawn at, and scaling it 2× doubles the badge's bounds.
    func testScalingANumberedMarkDoublesItsBounds() {
        var session = DrawingSession()
        session.begin(at: CGPoint(x: 100, y: 100), tool: .number, ink: .red)
        let badge = session.strokes[0]

        XCTAssertEqual(badge.badgeSize, PathBuilder.badgeDiameter,
                       "the mark stores the size it was drawn at")

        let before = badge.bounds
        let scaled = MarkTransform.scaled(badge, from: badge.anchor, by: 2)
        let after = scaled.bounds

        XCTAssertEqual(after.width, before.width * 2, accuracy: 0.01,
                       "scaling 2× doubles the bounds width")
        XCTAssertEqual(after.height, before.height * 2, accuracy: 0.01,
                       "scaling 2× doubles the bounds height")
        XCTAssertEqual(scaled.badgeSize, PathBuilder.badgeDiameter * 2)
        XCTAssertEqual(scaled.badgeScale, 2, accuracy: 0.001, "the digit scales with the badge")
    }

    // The hit test follows the stored size too: a 2× badge answers between the
    // old radius and the scaled one, and misses past the scaled radius.
    func testNumberedHitTestFollowsTheStoredBadgeSize() {
        let badge = Stroke(tool: .number, ink: .red, points: [CGPoint(x: 100, y: 100)],
                           stepNumber: 1, badgeSize: PathBuilder.badgeDiameter * 2)

        let between = CGPoint(x: 100, y: 100 + PathBuilder.badgeDiameter / 2 + 1)
        XCTAssertGreaterThan(100 + PathBuilder.badgeDiameter / 2 + 1, 100 + PathBuilder.badgeDiameter / 2,
                             "past the unscaled radius")
        XCTAssertLessThan(CGFloat(14), badge.badgeDiameter / 2, "but inside the scaled radius")
        XCTAssertTrue(badge.hitTest(between, radius: 0),
                      "between the unscaled and scaled radii: the scaled badge answers")
        XCTAssertFalse(badge.hitTest(CGPoint(x: 100, y: 100 + badge.badgeDiameter / 2 + 1), radius: 0),
                       "just past the scaled radius misses")
    }
}
