import CoreGraphics
import Foundation

/// Draws the geometry of marks into any context. Pure rendering, shared by the
/// overlay, the capture compositor and the self test, so all three agree.
public enum MarkRenderer {
    /// The weight of a filled shape's ink wash (S15): translucent, so the
    /// content underneath stays readable while the shape reads as filled —
    /// the same principle the highlighter draws with.
    private static let shapeFillOpacity: CGFloat = 0.3
    /// The dim weight outside a spotlight's region (S15 slice B): one
    /// decision, shared by the overlay preview and the compositor, so the
    /// capture shows exactly what the live layer showed.
    private static let spotlightDimAlpha: CGFloat = 0.55
    /// The soft rim lives just outside the dragged rectangle: the region's
    /// own inscribed ellipse stays fully clear, the dim ramps up from its
    /// edge to this multiple of the region's radii, and stays constant
    /// beyond. The silhouette is the pointer highlight's spotlight idea — a
    /// radial falloff — fitted to the mark's region geometry; the pointer
    /// mode itself is never wired into the mark path.
    private static let spotlightRimFactor: CGFloat = 1.2

    public static func draw(strokes: [Stroke], in context: CGContext, canvas: CGRect? = nil) {
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            draw(stroke: stroke, in: context, canvas: canvas)
        }
        context.restoreGState()
    }

    /// `canvas` is the whole surface a spotlight's dim must cover, in the
    /// context's current user space. A spotlight drawn without one reads the
    /// context's own clip bounds — right for a bare bitmap context and for a
    /// caller that already clipped to its canvas, and callers with a real
    /// surface rect (the overlay view, the compositor) pass it explicitly.
    public static func draw(
        stroke: Stroke,
        in context: CGContext,
        opacity: CGFloat? = nil,
        canvas: CGRect? = nil
    ) {
        if stroke.tool == .spotlight {
            drawSpotlight(
                stroke,
                canvas: canvas ?? context.boundingBoxOfClipPath,
                in: context
            )
            return
        }
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

    /// S15 slice B: the persistent spotlight. A dimming mask, not a stroke:
    /// the dragged rectangle's inscribed ellipse stays fully clear, the dim
    /// ramps up over a soft rim just outside it, and everything beyond the
    /// rim dims at the fixed weight. The mark's ink is ignored — a spotlight
    /// has no colour of its own — and the dim always covers the whole canvas
    /// even when the mark itself is rotated: only the hole turns with the
    /// mark, never the shroud.
    public static func drawSpotlight(
        _ stroke: Stroke,
        canvas: CGRect,
        in context: CGContext
    ) {
        guard let first = stroke.points.first, let last = stroke.points.last else { return }
        let rect = PathBuilder.normalizedRect(from: first, to: last)
        guard rect.width > 0, rect.height > 0, canvas.width > 0, canvas.height > 0 else { return }

        let rotation = stroke.rotation
        let rotate = Stroke.rotationTransform(around: stroke.anchor, by: rotation)

        // The reach ellipse: the region's ellipse grown by the rim. The dim
        // fill covers the whole canvas minus that hole; the canvas rect
        // stays in the context's own space, only the hole follows the mark.
        let reach = rect.insetBy(
            dx: -rect.width * (spotlightRimFactor - 1) / 2,
            dy: -rect.height * (spotlightRimFactor - 1) / 2
        )
        let hole = CGMutablePath()
        hole.addEllipse(in: reach)
        let shroud = CGMutablePath()
        shroud.addRect(canvas)
        if rotation != 0 {
            var transform = rotate
            shroud.addPath(hole.copy(using: &transform) ?? hole)
        } else {
            shroud.addPath(hole)
        }
        context.addPath(shroud)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: spotlightDimAlpha))
        context.fillPath(using: .evenOdd)

        // The soft rim: a radial gradient from fully clear at the region's
        // ellipse to the dim weight at the reach, drawn in a space scaled to
        // the reach so the falloff follows the region's proportions. Past
        // the reach the shroud owns the dim, so the gradient must stop
        // there: extending it would double-paint the far field.
        //
        // The gradient sits under the mark's own rotation — its rings are
        // elliptical about the centre, so turning the context turns them
        // with the region. At the reach it holds exactly the dim weight the
        // shroud paints beyond, so the two can never seam.
        context.saveGState()
        if rotation != 0 {
            context.concatenate(rotate)
        }
        context.translateBy(x: reach.midX, y: reach.midY)
        context.scaleBy(x: reach.width / 2, y: reach.height / 2)
        let colors = [
            CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
            CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
            CGColor(srgbRed: 0, green: 0, blue: 0, alpha: spotlightDimAlpha),
        ] as CFArray
        let locations: [CGFloat] = [0, 1 / spotlightRimFactor, 1]
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: locations
        ) {
            context.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: 1,
                options: []
            )
        }
        context.restoreGState()
    }
}
