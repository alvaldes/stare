import CoreGraphics
import XCTest

import StareCore

final class PathBuilderTests: XCTestCase {
    private let tolerance: CGFloat = 0.001

    private func elementKinds(_ path: CGPath) -> [CGPathElementType] {
        var kinds: [CGPathElementType] = []
        path.applyWithBlock { element in
            kinds.append(element.pointee.type)
        }
        return kinds
    }

    // S6: the pen leaves a mark where the user dragged.
    func testFreehandCurvePassesThroughEverySample() {
        let samples = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 40, y: 60),
            CGPoint(x: 90, y: 30),
            CGPoint(x: 140, y: 90),
        ]
        let path = PathBuilder.freehandPath(points: samples)

        // One line segment per gap between kept samples.
        XCTAssertEqual(elementKinds(path).filter { $0 == .addCurveToPoint }.count, samples.count - 1)
        XCTAssertEqual(path.currentPoint.x, samples.last!.x, accuracy: tolerance)
        XCTAssertEqual(path.currentPoint.y, samples.last!.y, accuracy: tolerance)

        let box = path.boundingBoxOfPath
        for sample in samples {
            XCTAssertTrue(
                box.insetBy(dx: -0.5, dy: -0.5).contains(sample),
                "sample \(sample) must lie on the drawn curve"
            )
        }
    }

    func testTwoSamplesProduceOneStraightSegment() {
        let path = PathBuilder.freehandPath(points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50)])
        XCTAssertEqual(elementKinds(path), [.moveToPoint, .addLineToPoint])
    }

    func testFreehandCollapsesNearDuplicateSamples() {
        let samples = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 10.1, y: 10.1),
            CGPoint(x: 10.2, y: 10.2),
            CGPoint(x: 60, y: 60),
        ]
        XCTAssertEqual(PathBuilder.simplified(samples).count, 2)
    }

    func testSingleSampleStillProducesADot() {
        let path = PathBuilder.freehandPath(points: [CGPoint(x: 5, y: 5)])
        XCTAssertFalse(path.isEmpty)
        XCTAssertFalse(path.boundingBoxOfPath.isNull)
    }

    // S6: the arrow points at what the user aimed at.
    func testArrowBarbsSitBehindTheTip() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 100, y: 0)
        let barbs = PathBuilder.arrowHeadBarbs(from: start, to: end)

        XCTAssertEqual(barbs.count, 2)
        for barb in barbs {
            XCTAssertLessThan(barb.x, end.x, "barbs trail the tip")
            let distance = ((barb.x - end.x) * (barb.x - end.x) + (barb.y - end.y) * (barb.y - end.y))
                .squareRoot()
            XCTAssertEqual(distance, PathBuilder.arrowHeadLength, accuracy: tolerance)
        }
        XCTAssertEqual(barbs[0].y, -barbs[1].y, accuracy: tolerance, "barbs are symmetric")
    }

    func testShortArrowShrinksItsHead() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 10, y: 0)
        let barbs = PathBuilder.arrowHeadBarbs(from: start, to: end)

        for barb in barbs {
            let distance = ((barb.x - end.x) * (barb.x - end.x) + (barb.y - end.y) * (barb.y - end.y))
                .squareRoot()
            XCTAssertLessThanOrEqual(distance, 6 + tolerance, "a 10pt arrow cannot carry a 16pt head")
        }
    }

    func testZeroLengthArrowHasNoBarbs() {
        let point = CGPoint(x: 20, y: 20)
        XCTAssertTrue(PathBuilder.arrowHeadBarbs(from: point, to: point).isEmpty)
    }

    // S6: shapes follow the drag direction.
    func testShapesNormalizeWhenDraggedUpAndLeft() {
        let fromOrigin = PathBuilder.normalizedRect(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 200, y: 220)
        )
        let fromOppositeCorner = PathBuilder.normalizedRect(
            from: CGPoint(x: 200, y: 220),
            to: CGPoint(x: 100, y: 100)
        )

        XCTAssertEqual(fromOrigin, fromOppositeCorner)
        XCTAssertEqual(fromOrigin.origin, CGPoint(x: 100, y: 100))
        XCTAssertEqual(fromOrigin.size, CGSize(width: 100, height: 120))
    }

    // S20: Shift on rectangle and ellipse draws a square and a circle.
    func testSquareConstraintKeepsTheDragDirection() {
        let start = CGPoint(x: 100, y: 100)

        let downRight = PathBuilder.squareConstraint(from: start, to: CGPoint(x: 150, y: 130))
        XCTAssertEqual(downRight, CGPoint(x: 150, y: 150))

        let upLeft = PathBuilder.squareConstraint(from: start, to: CGPoint(x: 40, y: 60))
        XCTAssertEqual(upLeft, CGPoint(x: 40, y: 40))

        let mixed = PathBuilder.squareConstraint(from: start, to: CGPoint(x: 30, y: 180))
        XCTAssertEqual(mixed, CGPoint(x: 20, y: 180))
    }

    func testSquareConstraintProducesASquareRect() {
        let start = CGPoint(x: 20, y: 40)
        let corner = PathBuilder.squareConstraint(from: start, to: CGPoint(x: 90, y: 55))
        let rect = PathBuilder.normalizedRect(from: start, to: corner)

        XCTAssertEqual(rect.width, rect.height, accuracy: 0.001)
        XCTAssertEqual(rect.width, 70, accuracy: 0.001)
    }

    // T5/S3: blur spans the dragged rectangle, like the other area tools.
    func testBlurPathSpansTheDraggedRectangle() {
        let stroke = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 15, y: 25), CGPoint(x: 95, y: 75)]
        )
        let box = PathBuilder.path(for: stroke).boundingBoxOfPath

        XCTAssertEqual(box, CGRect(x: 15, y: 25, width: 80, height: 50))
    }

    // T5/S3: the eraser removes a blur by touching its rectangle.
    func testBlurHitTestCoversTheRectangleInterior() {
        let stroke = Stroke(
            tool: .blur,
            ink: .red,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 60)]
        )

        XCTAssertTrue(stroke.hitTest(CGPoint(x: 50, y: 40), radius: 2), "inside the blurred rectangle")
        XCTAssertTrue(stroke.hitTest(CGPoint(x: 20, y: 20), radius: 2), "on the rectangle corner")
        XCTAssertFalse(stroke.hitTest(CGPoint(x: 10, y: 10), radius: 2), "outside the rectangle")
        XCTAssertFalse(stroke.hitTest(CGPoint(x: 90, y: 40), radius: 2), "beyond the right edge")
    }

    func testBadgeIsCenteredOnTheClick() {
        let click = CGPoint(x: 50, y: 50)
        let box = PathBuilder.badgePath(centeredAt: click).boundingBoxOfPath

        XCTAssertEqual(box.midX, click.x, accuracy: tolerance)
        XCTAssertEqual(box.midY, click.y, accuracy: tolerance)
        XCTAssertEqual(box.width, PathBuilder.badgeDiameter, accuracy: tolerance)
    }

    // S7: the highlighter marks text without hiding it.
    func testHighlighterIsWiderAndTranslucent() {
        let highlighter = Stroke(tool: .highlighter, ink: .yellow, points: [.zero, CGPoint(x: 10, y: 10)])
        let pen = Stroke(tool: .pen, ink: .yellow, points: [.zero, CGPoint(x: 10, y: 10)])

        XCTAssertGreaterThan(highlighter.lineWidth, pen.lineWidth)
        XCTAssertLessThan(highlighter.opacity, 1)
        XCTAssertEqual(pen.opacity, 1)
    }

    func testBoundsCoverTheWholeMark() {
        let stroke = Stroke(
            tool: .rectangle,
            ink: .red,
            points: [CGPoint(x: 10, y: 20), CGPoint(x: 110, y: 120)]
        )
        let bounds = stroke.bounds

        XCTAssertTrue(bounds.contains(CGPoint(x: 10, y: 20)))
        XCTAssertTrue(bounds.contains(CGPoint(x: 110, y: 120)))
        XCTAssertGreaterThan(bounds.width, 100, "bounds include the stroke width")
    }
}
