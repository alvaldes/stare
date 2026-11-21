import CoreGraphics
import Foundation

/// Draws the geometry of marks into any context. Pure rendering, shared by the
/// overlay, the capture compositor and the self test, so all three agree.
public enum MarkRenderer {
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

        context.setStrokeColor(stroke.ink.cgColor(alpha: opacity ?? stroke.opacity))
        context.setLineWidth(stroke.lineWidth)
        context.addPath(path)
        context.strokePath()
    }
}
