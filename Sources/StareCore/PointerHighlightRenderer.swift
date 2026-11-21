import CoreGraphics

/// Draws the pointer highlight (⌥⇧M, `OverlayView.drawCursorFrame`) for any
/// `PointerAppearance`. This is the single production renderer: the overlay
/// and the Settings preview must draw identical pixels because they both call
/// it with the same `PointerAppearance`, so a preview can never drift from the
/// real highlight.
///
/// Everything geometric comes from the appearance (radius, band, edge, glow
/// stops, glow extent) multiplied by `pulseScale`; the only proportions added
/// locally belong to the marker tip's own anatomy and are documented under
/// `markerTipPath`. Draw order matches today's overlay: soft glow first, then
/// the shape on top.
public enum PointerHighlightRenderer {
    /// Draws the highlight centred on `center` in the context's coordinate
    /// space. For the marker tip, the nib points toward `center.y - radius`
    /// (the top of the coordinate space); the other geometries are symmetric,
    /// so they are flip-invariant. Callers keep control of global state; the
    /// renderer only sets fill and stroke colours and widths, and the dash
    /// parameters of a dashed border within its own state.
    ///
    /// `rotation` turns the whole shape about `center` (radians, positive
    /// counter-clockwise in this coordinate space) — the click animation's
    /// rotate mode. The glow stays unrotated: it is radially symmetric, so
    /// rotating it would draw identical pixels. Rotation never changes
    /// `extent`: it moves the shape inside the same reach.
    public static func draw(
        in context: CGContext,
        center: CGPoint,
        appearance: PointerAppearance,
        pulseScale: CGFloat,
        rotation: CGFloat = 0
    ) {
        let radius = CGFloat(appearance.radius) * pulseScale
        guard radius > 0 else { return }
        let ink = appearance.ink
        // The band is a ratio of the radius, clamped to the shape so a full
        // width band (the marker tip's 2) can never turn the hole negative.
        // The paintings below never punch a hole for filled shapes anyway.
        let band = radius * CGFloat(appearance.bandWidth)
        let holeRadius = max(0, radius - band)

        // Glow first, under the shape, exactly as the overlay does today:
        // a radial gradient from the shape's inner boundary out to the glow
        // reach. The spotlight is pure falloff, so its gradient starts at the
        // centre instead; the filled dot and the marker tip carry the glow as
        // a halo starting at their outer boundary.
        if !appearance.glowStops.isEmpty {
            let colors = appearance.glowStops.map { ink.cgColor(alpha: CGFloat($0.alpha)) } as CFArray
            let locations = appearance.glowStops.map { CGFloat($0.location) }
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) {
                let startRadius: CGFloat
                switch appearance.geometry {
                case .spotlight: startRadius = 0
                case .dot, .markerTip: startRadius = radius
                case .ring, .squircle, .rhombus: startRadius = radius - min(band, radius)
                }
                context.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: startRadius,
                    endCenter: center,
                    endRadius: radius * CGFloat(appearance.glowExtent),
                    options: []
                )
            }
        }

        // The shape turns about the centre: 45° extra for the rhombus, whose
        // paths are the squircle's rounded square, plus the click rotation.
        // The glow above stays put (it is radially symmetric) and the extent
        // stays honest: the rhombus' corner reach (≈1.16 × radius) is well
        // inside the glow reach, and rotating about the centre cannot move
        // any painted pixel farther from it than the shape's own maximum
        // reach.
        let shapeRotation: CGFloat
        switch appearance.geometry {
        case .rhombus: shapeRotation = .pi / 4 + rotation
        default: shapeRotation = rotation
        }
        context.saveGState()
        if shapeRotation != 0 {
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: shapeRotation)
            context.translateBy(x: -center.x, y: -center.y)
        }
        defer { context.restoreGState() }

        switch appearance.geometry {
        case .ring, .squircle, .rhombus:
            if appearance.dashed {
                // Dashed border: the band stops being a filled annulus and
                // becomes a stroke on the outline offset inward half a band,
                // so the silhouette — the radial range the solid one fills —
                // is unchanged and only the rhythm changes. The dash pattern
                // is derived from the band width, so it scales with the
                // highlight and its pulse.
                let outline = shapePath(
                    center: center,
                    radius: radius - band / 2,
                    appearance: appearance
                )
                context.setStrokeColor(ink.cgColor(alpha: CGFloat(appearance.bandFillAlpha)))
                context.setLineWidth(band)
                context.setLineCap(.round)
                context.setLineDash(phase: 0, lengths: dashPattern(band: band))
                context.addPath(outline)
                context.strokePath()
                return
            }
            // Ring by construction, same as today's overlay: fill the outer
            // shape with the band colour, then punch the middle out with
            // `.clear` — even-odd left the interior painted, which read as a
            // dark disc instead of a ring.
            let path = shapePath(center: center, radius: radius, appearance: appearance)
            let hole = shapePath(center: center, radius: holeRadius, appearance: appearance)
            context.saveGState()
            context.setFillColor(ink.cgColor(alpha: CGFloat(appearance.bandFillAlpha)))
            context.addPath(path)
            context.fillPath()
            context.setBlendMode(.clear)
            context.addPath(hole)
            context.fillPath()
            context.restoreGState()

            // Bright edges stroked on both boundaries.
            if appearance.edgeWidth > 0 {
                context.setStrokeColor(ink.cgColor(alpha: CGFloat(appearance.edgeAlpha)))
                context.setLineWidth(CGFloat(appearance.edgeWidth))
                context.addPath(path)
                context.strokePath()
                context.addPath(hole)
                context.strokePath()
            }

        case .dot:
            // A filled disc, translucent so the pointer under it stays visible.
            context.setFillColor(ink.cgColor(alpha: CGFloat(appearance.bandFillAlpha)))
            fillEllipse(in: context, center: center, radius: radius)

        case .markerTip:
            context.setFillColor(ink.cgColor(alpha: CGFloat(appearance.bandFillAlpha)))
            context.addPath(markerTipPath(center: center, radius: radius))
            context.fillPath()

        case .spotlight:
            // The gradient drawn above is the whole shape: soft radial
            // falloff from the appearance's stops with no additional edge.
            break
        }
    }

    /// Bounding rect the drawing can touch, relative to the centre: the glow
    /// reach plus the appearance's margin — today exactly
    /// `OverlayView.pointerRect`'s `radius = size / 2 * scale * 1.9 + 12`.
    /// The overlay derives its invalidation rect from this instead of
    /// constants, so the rect always covers what the renderer paints. The
    /// rhombus and the click rotation stay inside it without inflating it:
    /// the rhombus' corner reach (≈1.16 × radius) sits well inside the glow
    /// reach (1.9 × radius), and rotating about the centre never moves a
    /// painted pixel farther out than the shape's own maximum reach, so the
    /// rect needs no extra margin for either.
    public static func extent(for appearance: PointerAppearance, pulseScale: CGFloat) -> CGRect {
        let reach = CGFloat(appearance.radius) * pulseScale * CGFloat(appearance.glowExtent)
            + CGFloat(appearance.glowMargin)
        return CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)
    }

    /// Dash rhythm of a dashed border, derived from the band width: rounded
    /// dashes twice as long as their gaps and set two band lengths apart, so
    /// the rhythm scales with the highlight's size and pulse. Pinned by the
    /// renderer tests.
    public static func dashPattern(band: CGFloat) -> [CGFloat] {
        [band * 2, band * 2]
    }

    /// Outer boundary of the banded shapes: an ellipse for `.ring`, a rounded
    /// rectangle whose corner radius is `cornerRadiusFactor * radius` for
    /// `.squircle`, and the same rounded square for `.rhombus` — the 45° turn
    /// is applied by the drawing context, not stored in the path, so the
    /// rhombus and the squircle share one path builder. Unknown geometries
    /// degrade to the plain ellipse.
    private static func shapePath(
        center: CGPoint,
        radius: CGFloat,
        appearance: PointerAppearance
    ) -> CGPath {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        guard radius > 0 else {
            let path = CGMutablePath()
            path.addEllipse(in: rect)
            return path
        }
        guard appearance.geometry == .squircle || appearance.geometry == .rhombus,
            let cornerFactor = appearance.cornerRadiusFactor else {
            let path = CGMutablePath()
            path.addEllipse(in: rect)
            return path
        }
        let corner = radius * CGFloat(cornerFactor)
        return CGPath(
            roundedRect: rect,
            cornerWidth: corner,
            cornerHeight: corner,
            transform: nil
        )
    }

    private static func fillEllipse(in context: CGContext, center: CGPoint, radius: CGFloat) {
        context.fillEllipse(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
    }

    /// Anatomy of the chisel nib, expressed as proportions of `radius` (the
    /// only internal proportions a shape needs, documented here):
    ///
    /// - Body: a rounded rectangle spanning the bottom 70% of the shape,
    ///   half-width 0.7 `radius`, corner radius 0.25 `radius`. The 0.7 keeps
    ///   the widest part visibly narrower than the bounding diameter.
    /// - Tip: a tapered quad from the body's top edge down to a flat chisel
    ///   edge of half-width 0.09 `radius` sitting exactly on the shape's
    ///   top boundary, symmetric about the vertical axis.
    ///
    /// The whole tip stays inside the shape's bounding square, so `extent`
    /// over-covers it the same way it over-covers the stroked edges.
    private static func markerTipPath(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let halfBodyWidth = 0.7 * radius
        let bodyTop = radius * -0.4
        let body = CGRect(
            x: center.x - halfBodyWidth,
            y: center.y + bodyTop,
            width: halfBodyWidth * 2,
            height: radius - bodyTop
        )
        path.addPath(
            CGPath(
                roundedRect: body,
                cornerWidth: 0.25 * radius,
                cornerHeight: 0.25 * radius,
                transform: nil
            )
        )
        // Tapered quad: wide at the body's top edge, narrow at the chisel edge
        // on the top boundary. Filled in the same path as the body so the
        // overlap does not double-composite.
        path.move(to: CGPoint(x: center.x - halfBodyWidth, y: center.y + bodyTop))
        path.addLine(to: CGPoint(x: center.x - 0.09 * radius, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + 0.09 * radius, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + halfBodyWidth, y: center.y + bodyTop))
        path.closeSubpath()
        return path
    }
}
