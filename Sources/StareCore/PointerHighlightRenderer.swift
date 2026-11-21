import CoreGraphics

/// Draws the pointer highlight (⌥⇧M, `OverlayView.drawCursorFrame`) for any
/// `PointerAppearance`. This is the single production renderer: the overlay
/// and the Settings preview must draw identical pixels because they both call
/// it with the same `PointerAppearance`, so a preview can never drift from the
/// real highlight.
///
/// Everything geometric comes from the appearance (radius, band, edge, glow
/// stops, glow extent) multiplied by `pulseScale`; no shape carries its own
/// internal proportions. Draw order matches today's overlay: soft glow
/// first, then the shape on top.
public enum PointerHighlightRenderer {
    /// Draws the highlight centred on `center` in the context's coordinate
    /// space. The banded geometries are symmetric, so they are
    /// flip-invariant. Callers keep control of global state; the renderer
    /// only sets fill and stroke colours and widths, and the dash parameters
    /// of a dashed outer boundary line within its own state.
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
        // The band is a ratio of the radius, clamped to the shape so it can
        // never turn the hole negative. The paintings below never punch a
        // hole for filled shapes anyway.
        let band = radius * CGFloat(appearance.bandWidth)
        let holeRadius = max(0, radius - band)

        // Glow first, under the shape, exactly as the overlay does today:
        // a radial gradient from the shape's inner boundary out to the glow
        // reach. The spotlight is pure falloff, so its gradient starts at the
        // centre instead; the filled dot carries the glow as a halo starting
        // at its outer boundary.
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
                case .dot: startRadius = radius
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
            // The band is a filled coloured ring between the two boundary
            // lines: fill the outer shape with the band colour, then punch
            // the middle out with `.clear` — even-odd left the interior
            // painted, which read as a dark disc instead of a ring. The fill
            // stays underneath the outer line's dashes, so a dash gap never
            // shows a hole through the highlight.
            let path = shapePath(center: center, radius: radius, appearance: appearance)
            let hole = shapePath(center: center, radius: holeRadius, appearance: appearance)
            context.setFillColor(ink.cgColor(alpha: CGFloat(appearance.bandFillAlpha)))
            context.addPath(path)
            context.fillPath()
            context.saveGState()
            context.setBlendMode(.clear)
            context.addPath(hole)
            context.fillPath()
            context.restoreGState()

            // The band carries a thin bright line on both boundaries. The
            // inner one is always continuous; the outer one is a solid line,
            // or dashes for the dashed style — everything else about the
            // drawing is identical between the two styles.
            if appearance.edgeWidth > 0 {
                context.setStrokeColor(ink.cgColor(alpha: CGFloat(appearance.edgeAlpha)))
                context.setLineWidth(CGFloat(appearance.edgeWidth))
                context.setLineCap(.round)
                context.addPath(hole)
                context.strokePath()
                if appearance.dashed {
                    // Butt caps so each dash reads as a crisp segment of the
                    // thin line instead of a rounded blob; the rhythm is
                    // pinned under `dashPattern(lineWidth:)`.
                    context.setLineCap(.butt)
                    context.setLineDash(
                        phase: 0,
                        lengths: dashPattern(lineWidth: CGFloat(appearance.edgeWidth))
                    )
                }
                context.addPath(path)
                context.strokePath()
            }

        case .dot:
            // A filled disc, translucent so the pointer under it stays visible.
            context.setFillColor(ink.cgColor(alpha: CGFloat(appearance.bandFillAlpha)))
            fillEllipse(in: context, center: center, radius: radius)

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

    /// Dash rhythm of a dashed outer boundary line, derived from the border
    /// line width so the dashes read as segments on that thin line, not dots
    /// or blobs: each dash is three line widths long and each gap two, and
    /// the caller strokes with butt caps so the segments stay crisp at any
    /// line width. With today's 2 pt border line that is exactly a 6 pt dash
    /// and a 4 pt gap. Pinned by the renderer tests.
    public static func dashPattern(lineWidth: CGFloat) -> [CGFloat] {
        [lineWidth * 3, lineWidth * 2]
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
}
