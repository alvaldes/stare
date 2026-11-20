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

    public static func draw(stroke: Stroke, in context: CGContext) {
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

        context.setStrokeColor(stroke.ink.cgColor(alpha: stroke.opacity))
        context.setLineWidth(stroke.lineWidth)
        context.addPath(path)
        context.strokePath()
    }
}
