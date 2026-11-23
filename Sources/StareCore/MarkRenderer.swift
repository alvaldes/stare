import CoreGraphics
import Foundation

/// Draws the geometry of marks into any context. Pure rendering, shared by the
/// overlay, the capture compositor and the self test, so all three agree.
public enum MarkRenderer {
    /// The weight of a filled shape's ink wash (S15): translucent, so the
    /// content underneath stays readable while the shape reads as filled —
    /// the same principle the highlighter draws with.
    private static let shapeFillOpacity: CGFloat = 0.3
    public static func draw(strokes: [Stroke], in context: CGContext) {
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            draw(stroke: stroke, in: context)
        }
        context.restoreGState()
    }

    public static func draw(stroke: Stroke, in context: CGContext, opacity: CGFloat? = nil) {
        guard stroke.rotation != 0 else {
            drawGeometry(stroke, in: context, opacity: opacity)
            return
        }
        // The mark rotates about its anchor; the geometry itself is untouched,
        // so the shape never changes.
        context.saveGState()
        context.concatenate(
            Stroke.rotationTransform(around: stroke.anchor, by: stroke.rotation)
        )
        drawGeometry(stroke, in: context, opacity: opacity)
        context.restoreGState()
    }

    private static func drawGeometry(_ stroke: Stroke, in context: CGContext, opacity: CGFloat? = nil) {
        let path = PathBuilder.path(for: stroke)

        if stroke.tool == .number {
            context.setFillColor(stroke.ink.cgColor())
            context.addPath(path)
            context.fillPath()

            context.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
            context.setLineWidth(1)
            context.addPath(path)
            context.strokePath()
            return
        }

        // A click with a freehand tool has no direction, so it must show as a
        // dot instead of a zero-length line.
        if stroke.tool == .pen, stroke.points.count == 1, let point = stroke.points.first {
            let radius = stroke.lineWidth / 2
            context.setFillColor(stroke.ink.cgColor(alpha: opacity ?? stroke.opacity))
            context.fillEllipse(
                in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            return
        }

        // S15: a filled shape paints its ink wash first, then the outline on
        // top — the outline's own full-opacity stroke covers the wash's edge.
        if stroke.isFilled, stroke.tool == .rectangle || stroke.tool == .ellipse {
            context.setFillColor(stroke.ink.cgColor(alpha: shapeFillOpacity))
            context.addPath(path)
            context.fillPath()
        }

        context.setStrokeColor(stroke.ink.cgColor(alpha: opacity ?? stroke.opacity))
        context.setLineWidth(stroke.lineWidth)
        context.addPath(path)
        context.strokePath()

        // S15: a filled arrow head inks the triangle the two barbs span,
        // over the stroked shaft and barbs, so the head reads as solid while
        // the shaft keeps its drawn weight. The open head (the default) adds
        // nothing here and renders exactly as it always did.
        if stroke.tool == .arrow, stroke.arrowHead == .filled,
            let start = stroke.startPoint, let end = stroke.endPoint,
            !PathBuilder.arrowHeadBarbs(from: start, to: end).isEmpty
        {
            let head = CGMutablePath()
            head.move(to: end)
            for barb in PathBuilder.arrowHeadBarbs(from: start, to: end) {
                head.addLine(to: barb)
            }
            head.closeSubpath()
            context.setFillColor(stroke.ink.cgColor(alpha: opacity ?? stroke.opacity))
            context.addPath(head)
            context.fillPath()
            return
        }
    }
}
