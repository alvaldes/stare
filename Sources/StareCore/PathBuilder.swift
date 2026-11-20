import CoreGraphics
import Foundation

/// Builds the vector geometry of a mark. Pure geometry: no windows, no colours,
/// no rendering, so every rule here is unit-testable.
public enum PathBuilder {
    /// Diameter of a numbered-step badge, in points.
    public static let badgeDiameter: CGFloat = 26
    /// Length of each arrow head barb, in points.
    public static let arrowHeadLength: CGFloat = 16
    /// Half-angle between the shaft and each barb.
    public static let arrowHeadHalfAngle: CGFloat = .pi / 8
    /// Consecutive drag samples closer than this are collapsed.
    public static let minimumSampleDistance: CGFloat = 0.75

    public static func path(for stroke: Stroke) -> CGPath {
        let points = stroke.points
        guard let first = points.first else { return CGMutablePath() }

        switch stroke.tool {
        case .text:
            // Text is drawn by the platform layer; the model keeps its box.
            return CGMutablePath()
        case .eraser:
            return CGMutablePath()
        case .number:
            return badgePath(centeredAt: first)
        case .line:
            return linePath(from: first, to: points.last ?? first)
        case .arrow:
            return arrowPath(from: first, to: points.last ?? first)
        case .rectangle:
            return rectanglePath(from: first, to: points.last ?? first)
        case .ellipse:
            return ellipsePath(from: first, to: points.last ?? first)
        case .pen, .highlighter, .laser:
            return freehandPath(points: points)
        }
    }

    public static func bounds(for stroke: Stroke) -> CGRect {
        if stroke.tool == .text, let origin = stroke.points.first {
            let size = stroke.textSize ?? CGSize(width: 0, height: 0)
            return CGRect(origin: origin, size: size).insetBy(dx: -2, dy: -2)
        }
        let geometry = path(for: stroke)
        var box = geometry.boundingBoxOfPath
        if box.isNull || box.isEmpty { box = .zero }
        let padding = stroke.lineWidth / 2 + 1
        return box.insetBy(dx: -padding, dy: -padding)
    }

    // MARK: - Primitives

    public static func linePath(from start: CGPoint, to end: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }

    public static func arrowPath(from start: CGPoint, to end: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)

        let barbs = arrowHeadBarbs(from: start, to: end)
        for barb in barbs {
            path.move(to: end)
            path.addLine(to: barb)
        }
        return path
    }

    /// The two barbs of the arrow head, ordered left then right of the shaft.
    public static func arrowHeadBarbs(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.001 else { return [] }

        let shaft = atan2(dy, dx)
        // A short stroke must not grow barbs longer than itself.
        let barbLength = min(arrowHeadLength, length * 0.6)

        return [arrowHeadHalfAngle, -arrowHeadHalfAngle].map { offset in
            let angle = shaft + offset
            return CGPoint(
                x: end.x - cos(angle) * barbLength,
                y: end.y - sin(angle) * barbLength
            )
        }
    }

    public static func rectanglePath(from first: CGPoint, to second: CGPoint) -> CGPath {
        let rect = normalizedRect(from: first, to: second)
        let path = CGMutablePath()
        path.addRect(rect)
        return path
    }

    public static func ellipsePath(from first: CGPoint, to second: CGPoint) -> CGPath {
        let rect = normalizedRect(from: first, to: second)
        let path = CGMutablePath()
        path.addEllipse(in: rect)
        return path
    }

    public static func badgePath(centeredAt center: CGPoint) -> CGPath {
        let radius = badgeDiameter / 2
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: badgeDiameter,
            height: badgeDiameter
        )
        let path = CGMutablePath()
        path.addEllipse(in: rect)
        return path
    }

    /// Endpoint that turns a rectangle or ellipse into a square or circle while
    /// Shift is held, keeping the drag direction.
    public static func squareConstraint(from start: CGPoint, to point: CGPoint) -> CGPoint {
        let dx = point.x - start.x
        let dy = point.y - start.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(
            x: start.x + (dx < 0 ? -side : side),
            y: start.y + (dy < 0 ? -side : side)
        )
    }

    public static func normalizedRect(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }

    // MARK: - Freehand

    /// Smooths drag samples into a curve. The curve passes through every kept
    /// point, so the mark never drifts away from what the user drew.
    public static func freehandPath(points rawPoints: [CGPoint]) -> CGPath {
        let points = simplified(rawPoints)
        let path = CGMutablePath()

        guard let first = points.first else { return path }
        guard points.count > 1 else {
            // A click with a freehand tool still leaves a dot.
            path.move(to: first)
            path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y))
            return path
        }

        path.move(to: first)
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }

    /// Drops samples that are too close together, which would make the spline
    /// control points degenerate.
    public static func simplified(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if let last = result.last {
                let dx = point.x - last.x
                let dy = point.y - last.y
                if (dx * dx + dy * dy).squareRoot() < minimumSampleDistance {
                    continue
                }
            }
            result.append(point)
        }
        if result.isEmpty, let first = points.first { result = [first] }
        return result
    }
}
