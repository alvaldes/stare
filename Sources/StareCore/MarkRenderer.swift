import CoreGraphics
import Foundation

/// Draws the geometry of marks into any context. Pure rendering, shared by the
/// overlay, the capture compositor and the self test, so all three agree.
public enum MarkRenderer {
    /// Whether a mark is still being dragged or already on the canvas (T8b).
    /// One explicit input the caller passes — the overlay, which is the only
    /// place that knows what is mid-gesture — never a guess from the mark's
    /// shape or point count, and never stored on the mark: committed and
    /// in-progress spotlights carry identical data and differ only in what
    /// they paint while drawn.
    public enum Phase: String, Sendable {
        /// The mark is in hand: the overlay's live drag preview.
        case inProgress
        /// The mark is committed, or composed into a capture.
        case committed
    }

    /// The weight of a filled shape's ink wash (S15): translucent, so the
    /// content underneath stays readable while the shape reads as filled —
    /// the same principle the highlighter draws with.
    private static let shapeFillOpacity: CGFloat = 0.3
    /// The dim weight the spotlight settles at far from the region (S15
    /// slice B): one decision, shared by the overlay preview and the
    /// compositor, so the capture shows exactly what the live layer showed.
    private static let spotlightDimAlpha: CGFloat = 0.55
    /// The spotlight's feather: the distance past the lit boundary at which
    /// the dim reaches its deepest weight, as a fraction of the region's
    /// radii. A constant in the region's own metric, so its real width grows
    /// and shrinks with the region — a large area fades wide and ambient, a
    /// small one stays crisp. Tuned once for the eye; render candidates to
    /// compare by passing `feather:`.
    public static let spotlightFeather: CGFloat = 1.2
    /// Samples of the eased falloff across one feather: the smoothstep curve
    /// `t²(3 − 2t)`, so the ramp starts and ends with zero slope and the
    /// boundary never reads as an edge.
    private static let spotlightEaseSteps: [CGFloat] = [0.25, 0.5, 0.75]

    // MARK: - The redaction patch (S13)

    /// The one place the blur mark's effect is chosen. The overlay's live blur
    /// preview (`OverlayView.drawBlur`) and the capture compositor's
    /// `drawBlur` both crop the same source at the same pixel rect, and both
    /// must answer "blur or pixelate" with the mark's own style — so the
    /// decision lives here, in the file the overlay, the compositor and the
    /// self test already share, and neither path can drift into a second
    /// decision a mark that previews pixelated is saved pixelated (L9).
    ///
    /// `scale` is the effect scale (`BlurEffect.defaultRadius * scale` for the
    /// blur; the pixelate derives its block from the rect itself, so it needs
    /// no scale). The pixelate's grid offsets use the caller's `seed` — the
    /// mark's own, never the public `PixelateEffect.defaultSeed`
    /// (`R1-pixelate-predictable-offsets`).
    public static func redactionPatch(
        _ image: CGImage,
        pixelRect: CGRect,
        style: RedactionStyle,
        seed: UInt64,
        scale: CGFloat
    ) -> CGImage? {
        switch style {
        case .blur:
            return BlurEffect.crop(image, pixelRect: pixelRect, radius: BlurEffect.defaultRadius * scale)
        case .randomizedPixelate:
            return PixelateEffect.crop(image, pixelRect: pixelRect, seed: seed)
        }
    }

    public static func draw(strokes: [Stroke], in context: CGContext, canvas: CGRect? = nil, phase: Phase = .committed) {
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            draw(stroke: stroke, in: context, canvas: canvas, phase: phase)
        }
        context.restoreGState()
    }

    /// `canvas` is the whole surface a spotlight's dim must cover, in the
    /// context's current user space. A spotlight drawn without one reads the
    /// context's own clip bounds — right for a bare bitmap context and for a
    /// caller that already clipped to its canvas, and callers with a real
    /// surface rect (the overlay view, the compositor) pass it explicitly.
    ///
    /// `phase` (T8b) defaults to `.committed`, so every caller that does not
    /// name it — the compositor, the editor, the committed overlay marks —
    /// renders exactly as it always did.
    public static func draw(
        stroke: Stroke,
        in context: CGContext,
        opacity: CGFloat? = nil,
        canvas: CGRect? = nil,
        phase: Phase = .committed
    ) {
        if stroke.tool == .spotlight {
            guard phase == .committed else {
                drawSpotlightPreview(stroke, in: context, opacity: opacity)
                return
            }
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

    /// T8b: while the spotlight's drag is in progress the mark previews
    /// exactly what the ellipse tool draws for the same drag — the same
    /// outline, the same thickness and ink behaviour, and the dim nowhere —
    /// by drawing through the ellipse preview's own path: the shared
    /// geometry renderer, fed an ellipse built from the same drag points.
    /// The finished spotlight look (the dim) belongs to the committed phase
    /// and is drawn by `drawSpotlight`; the compositor, which only ever sees
    /// committed marks, never takes this branch, so a capture always
    /// carries the dim.
    private static func drawSpotlightPreview(_ stroke: Stroke, in context: CGContext, opacity: CGFloat?) {
        // The ellipse keeps today's preview byte for byte: the shared geometry
        // renderer, fed an ellipse built from the same drag points.
        if stroke.spotlightShape == .ellipse {
            let outline = Stroke(
                id: stroke.id,
                tool: .ellipse,
                ink: stroke.ink,
                points: stroke.points,
                rotation: stroke.rotation
            )
            draw(stroke: outline, in: context, opacity: opacity)
            return
        }
        // The flat shapes preview their own silhouette, drawn with the shape
        // outline tools' weight (3 — the rectangle's and ellipse's own), the
        // same ink and the same ink behaviour, and the dim nowhere, exactly as
        // the ellipse preview never dims.
        guard let first = stroke.points.first, let last = stroke.points.last else { return }
        let path = PathBuilder.spotlightPath(stroke.spotlightShape, from: first, to: last)
        context.saveGState()
        if stroke.rotation != 0 {
            context.concatenate(
                Stroke.rotationTransform(around: stroke.anchor, by: stroke.rotation)
            )
        }
        context.setStrokeColor(stroke.ink.cgColor(alpha: opacity ?? stroke.opacity))
        context.setLineWidth(3)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    /// S15 slice B: the persistent spotlight. A dimming light, not a stroke:
    /// one silhouette — the dragged rectangle's inscribed ellipse, the shape
    /// a beam of light makes (S2/S3: the mark's own `spotlightShape` — the
    /// rectangle and the rounded rectangle cut the same dim below, in
    /// `drawFlatSpotlight`) — and the dim falls off from its edge in a
    /// single radial gradient, across the whole canvas at once. There is no
    /// second geometry and no shroud fill: inside the boundary the gradient
    /// paints at alpha zero (the content beneath keeps its exact
    /// brightness), the dim eases out over a feather that is a fraction of
    /// the region's radii — so its width grows with the region — and rests
    /// at the deepest weight beyond. The mark's ink is ignored — a
    /// spotlight has no colour of its own — and the dim always covers the
    /// whole canvas even when the mark itself is rotated: only the lit
    /// window turns with the mark, never the falloff.
    ///
    /// Per frame this is one gradient allocation and one gradient fill over
    /// the canvas — strictly less work than the shroud fill plus gradient it
    /// replaced.
    ///
    /// `feather` overrides `spotlightFeather` for look comparisons; the
    /// overlay and the compositor never pass it, so what they draw agrees.
    public static func drawSpotlight(
        _ stroke: Stroke,
        canvas: CGRect,
        in context: CGContext,
        feather: CGFloat? = nil
    ) {
        guard let first = stroke.points.first, let last = stroke.points.last else { return }
        let rect = PathBuilder.normalizedRect(from: first, to: last)
        guard rect.width > 0, rect.height > 0, canvas.width > 0, canvas.height > 0 else { return }

        if stroke.spotlightShape != .ellipse {
            drawFlatSpotlight(stroke, silhouette: PathBuilder.spotlightPath(
                stroke.spotlightShape, from: first, to: last),
                canvas: canvas, in: context)
            return
        }

        let rotation = stroke.rotation
        let rotate = Stroke.rotationTransform(around: stroke.anchor, by: rotation)

        // One silhouette, drawn as one gradient: pixels at normalized
        // distance ≤ 1 from the centre stay clear, the dim eases to its
        // deepest weight a feather of the radii away, and holds it beyond.
        // The metric is the lit ellipse's own — semi-axes from the dragged
        // rectangle — so each pixel's distance answers in the light's
        // proportions.
        let semiWidth = rect.width / 2
        let semiHeight = rect.height / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)

        // The farthest canvas corner from the lit centre, in the light's
        // metric: it bounds the gradient's radius span, so the stops can be
        // placed in pixel distances without the span stretching past what
        // the surface needs. An unbounded canvas (a caller without its own
        // clip rect) has no finite corner to measure — the gradient then
        // only has to reach past the feather, because beyond its last stop
        // the far field is the deepest dim no matter how far out the clip
        // goes.
        let featherFactor = max(0.001, feather ?? spotlightFeather)
        let inverse = rotate.inverted()
        var reach: CGFloat = 0
        var unbounded = false
        for corner in [
            CGPoint(x: canvas.minX, y: canvas.minY),
            CGPoint(x: canvas.maxX, y: canvas.minY),
            CGPoint(x: canvas.maxX, y: canvas.maxY),
            CGPoint(x: canvas.minX, y: canvas.maxY),
        ] {
            let local = corner.applying(inverse)
            let dx = (local.x - centre.x) / semiWidth
            let dy = (local.y - centre.y) / semiHeight
            guard dx.isFinite, dy.isFinite else {
                unbounded = true
                continue
            }
            reach = max(reach, (dx * dx + dy * dy).squareRoot())
        }
        if unbounded || reach > 1 {
            reach = max(reach, 1 + featherFactor)
        } else {
            return // every corner sits inside the lit window: nothing to dim
        }

        // The feather clamps into the room the canvas leaves past the
        // boundary, so a surface barely larger than the region still gets a
        // complete, eased ramp instead of one cut off by the gradient's end.
        let featherWidth = max(0.001, min(featherFactor, (reach - 1) * 0.98))
        var locations: [CGFloat] = [0, 1 / reach]
        var alphas: [CGFloat] = [0, 0]
        for step in spotlightEaseSteps {
            let eased = step * step * (3 - 2 * step)
            locations.append((1 + step * featherWidth) / reach)
            alphas.append(spotlightDimAlpha * eased)
        }
        locations.append(min(1, (1 + featherWidth) / reach))
        alphas.append(spotlightDimAlpha)
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: alphas.map {
                CGColor(srgbRed: 0, green: 0, blue: 0, alpha: $0)
            } as CFArray,
            locations: locations
        ) else { return }

        // The gradient sits under the mark's own rotation — its rings are
        // elliptical about the centre, so turning the context turns them
        // with the region — and paints the entire clipped canvas: extending
        // past the end radius blankets the far field in the deepest dim, so
        // no second fill ever seams against it.
        context.saveGState()
        if rotation != 0 {
            context.concatenate(rotate)
        }
        context.translateBy(x: centre.x, y: centre.y)
        context.scaleBy(x: semiWidth, y: semiHeight)
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: 0,
            endCenter: .zero,
            endRadius: reach,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    /// S2/S3: the rectangle and the rounded rectangle's own silhouettes. The
    /// dim around them is the shipped weight (`spotlightDimAlpha`) drawn the
    /// source-over way the gradient's far field is; the shape itself cuts
    /// where the light reaches, so the interior clears exactly and the dim
    /// starts at the silhouette — no feather band, which the ellipse's curve
    /// needs because its boundary distance is an arc and the mark has none:
    /// a rectangle names its own boundary exactly. The path turns with the
    /// mark's rotation; the dim stays over the whole canvas.
    private static func drawFlatSpotlight(
        _ stroke: Stroke,
        silhouette lit: CGPath,
        canvas: CGRect,
        in context: CGContext
    ) {
        // Nothing to dim when the lit silhouette covers the canvas (the same
        // early return the gradient takes when every corner sits inside): the
        // silhouettes are convex, so the four corners answer for the whole
        // canvas.
        let rotate = Stroke.rotationTransform(around: stroke.anchor, by: stroke.rotation)
        var transform = rotate
        guard let litPath = lit.copy(using: &transform) else { return }
        let covered = [
            CGPoint(x: canvas.minX, y: canvas.minY),
            CGPoint(x: canvas.maxX, y: canvas.minY),
            CGPoint(x: canvas.maxX, y: canvas.maxY),
            CGPoint(x: canvas.minX, y: canvas.maxY),
        ].allSatisfy { litPath.contains($0) }
        if covered { return }
        let shroud = CGMutablePath()
        shroud.addRect(canvas)
        shroud.addPath(litPath)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: spotlightDimAlpha))
        context.addPath(shroud)
        context.fillPath(using: .evenOdd)
    }
}
