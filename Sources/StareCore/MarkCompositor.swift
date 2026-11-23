import CoreGraphics
import CoreText
import Foundation

/// Composes the vector marks over a captured frame. This is what makes a capture
/// look right: the image is the real screen, and the marks are drawn again at
/// pixel resolution, so nothing is resampled and the interface never appears in
/// the shot.
public enum MarkCompositor {
    /// Marks live in overlay space: top-left origin, points. `scale` is image
    /// pixels per point.
    ///
    /// `offset` (T12 fix) is the whiteboard page's pan; `zoom` (T5/S5) is its
    /// zoom. Marks stored in page space are placed where the board's view
    /// shows them — `view = (page − offset) × zoom` through `BoardTransform`,
    /// the same mapping the view draws with — so a panned, zoomed page's
    /// capture is what the board shows. The identity transform leaves the
    /// marks where they were, exactly as the drawing overlay composes them.
    ///
    /// `diffusesContent` (S1) marks the board's capture: its blur marks diff
    /// the board's own content. False leaves the drawing overlay's behaviour
    /// untouched: blur crops the base — the real screen pixels.
    public static func composite(
        marks: [Stroke],
        over base: CGImage,
        scale: CGFloat = 1,
        diffusesContent: Bool = false,
        offset: CGSize = .zero,
        zoom: CGFloat = 1
    ) -> CGImage? {
        let width = base.width
        let height = base.height
        guard width > 0, height > 0 else { return nil }

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))

        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        // Overlay space is top-left origin; the bitmap is bottom-left.
        context.translateBy(x: 0, y: CGFloat(height) / scale)
        context.scaleBy(x: 1, y: -1)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // The whiteboard stores marks in page space; the capture (and the
        // frame a blur mark samples) live in view space, where the board shows
        // them at pagePoint - offset. The mark's identity, ink, text and
        // rotation are kept; only the geometry moves, and the rotation anchor
        // (the centre of the bounds) moves with it consistently.
        let placed: [Stroke]
        let transform = BoardTransform(offset: offset, zoom: zoom)
        if transform == .identity {
            placed = marks
        } else {
            placed = marks.map { mark in
                var shifted = mark
                shifted.points = mark.points.map { transform.point(fromPage: $0) }
                return shifted
            }
        }

        for mark in placed where !mark.tool.isTransient {
            draw(mark, in: context, base: base, scale: scale, diffusesContent: diffusesContent)
        }

        context.restoreGState()
        return context.makeImage()
    }

    private static func draw(
        _ stroke: Stroke,
        in context: CGContext,
        base: CGImage,
        scale: CGFloat,
        diffusesContent: Bool
    ) {
        switch stroke.tool {
        case .text:
            drawWithRotation(stroke, in: context) { context in
                drawText(stroke, in: context)
            }
            return
        case .number:
            MarkRenderer.draw(stroke: stroke, in: context)
            drawWithRotation(stroke, in: context) { context in
                drawStepNumber(stroke, in: context)
            }
            return
        case .blur:
            drawWithRotation(stroke, in: context) { context in
                drawBlur(stroke, in: context, base: base, scale: scale, diffusesContent: diffusesContent)
            }
            return
        case .spotlight:
            // The dim covers the whole capture, in overlay points. The
            // renderer turns the hole with the mark itself; nothing here
            // wraps the call in the rotation transform.
            MarkRenderer.drawSpotlight(
                stroke,
                canvas: CGRect(
                    x: 0,
                    y: 0,
                    width: CGFloat(base.width) / scale,
                    height: CGFloat(base.height) / scale
                ),
                in: context
            )
            return
        default:
            MarkRenderer.draw(stroke: stroke, in: context)
        }
    }

    /// Applies the mark's rotation about its anchor to a branch that draws its
    /// own geometry (text, the step digit, the blur image). `MarkRenderer.draw`
    /// already rotates everything it draws itself.
    private static func drawWithRotation(
        _ stroke: Stroke,
        in context: CGContext,
        _ body: (CGContext) -> Void
    ) {
        guard stroke.rotation != 0 else {
            body(context)
            return
        }
        context.saveGState()
        context.concatenate(
            Stroke.rotationTransform(around: stroke.anchor, by: stroke.rotation)
        )
        body(context)
        context.restoreGState()
    }

    /// S1: a blur mark is the content underneath it, gaussian blurred, instead
    /// of stroking a rectangle. `BlurEffect` works in image pixels, which share
    /// the bitmap context's bottom-left origin; the crop is drawn back at the
    /// mark's rectangle in overlay space, where the context's transform already
    /// does the scaling and the flip.
    ///
    /// The source behind the patch is decided by which surface the mark lives
    /// on. On the drawing overlay (`diffusesContent` false) it is the base —
    /// the real screen pixels, as always. On the board (true) it is what is
    /// already rendered beneath the mark in draw order: the page colour and
    /// the marks painted before it, which is exactly the context's content at
    /// the mark's turn. The snapshot is taken here, mid-composition, so it
    /// holds all of that and none of the marks painted after it — they stay
    /// sharp on top of the patch.
    private static func drawBlur(
        _ stroke: Stroke,
        in context: CGContext,
        base: CGImage,
        scale: CGFloat,
        diffusesContent: Bool
    ) {
        guard let first = stroke.points.first, let last = stroke.points.last else { return }
        let rect = PathBuilder.normalizedRect(from: first, to: last)
        guard rect.width > 0, rect.height > 0 else { return }

        let source: CGImage
        if diffusesContent {
            // Everything rendered so far — base plus earlier marks — is the
            // content the patch diffuses.
            guard let beneath = context.makeImage() else { return }
            source = beneath
        } else {
            source = base
        }
        let sourceScale = scale

        // The patch may reach past the base — a mark drawn across the page's
        // edge covers less of the picture than its own rectangle. The blurred
        // source only exists where the base is, so the patch is clipped to
        // that intersection before it is sampled or drawn: the inside part is
        // blurred at its true position (the live view path draws the crop at
        // the intersection the same way), never stretched across the whole
        // rect. Nothing crashes and nothing lands off the base.
        let baseRect = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(source.width) / sourceScale,
            height: CGFloat(source.height) / sourceScale
        )
        let visible = rect.intersection(baseRect)
        guard !visible.isNull, !visible.isEmpty else { return }

        let pixelRect = CGRect(
            x: visible.minX * sourceScale,
            y: CGFloat(source.height) - visible.maxY * sourceScale,
            width: visible.width * sourceScale,
            height: visible.height * sourceScale
        )
        guard let patch = MarkRenderer.redactionPatch(
            source,
            pixelRect: pixelRect,
            style: stroke.redactionStyle,
            seed: stroke.redactionSeed,
            scale: sourceScale
        ) else { return }

        context.saveGState()
        context.translateBy(x: visible.minX, y: visible.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(patch, in: CGRect(origin: .zero, size: visible.size))
        context.restoreGState()
    }

    private static func drawText(_ stroke: Stroke, in context: CGContext) {
        guard let text = stroke.text, !text.isEmpty, let origin = stroke.points.first else { return }
        let fontSize = textFontSize(for: stroke)
        let line = makeLine(text, font: font(ofSize: fontSize), ink: stroke.ink)

        context.saveGState()
        // The context is flipped for overlay space, so glyphs need unmirroring.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: origin.x, y: origin.y + fontSize)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// The stroke's own `textSize` sets the font size: the app stores the box
    /// the text was measured in, and a scaled mark carries the scaled box, so
    /// the size that renders the text at that box's width scales with it.
    /// Unscaled marks measure back out to `OverlayStyle.textSize`, so their
    /// rendering is unchanged.
    private static func textFontSize(for stroke: Stroke) -> CGFloat {
        let base = OverlayStyle.textSize
        guard let text = stroke.text, !text.isEmpty,
              let size = stroke.textSize, size.width > 0
        else { return base }
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let reference = makeLine(text, font: font(ofSize: base), ink: stroke.ink)
        let width = CGFloat(CTLineGetTypographicBounds(reference, &ascent, &descent, nil))
        guard width > 0.001 else { return base }
        return base * size.width / width
    }

    private static func drawStepNumber(_ stroke: Stroke, in context: CGContext) {
        guard let number = stroke.stepNumber, let centre = stroke.points.first else { return }
        let line = makeLine(
            "\(number)",
            // The digit scales with the badge it sits on (advisory A).
            font: font(ofSize: OverlayStyle.stepNumberSize * stroke.badgeScale),
            ink: digitInk(for: stroke.ink)
        )

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))

        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(
            x: centre.x - width / 2,
            y: centre.y + (ascent - descent) / 2
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func makeLine(_ text: String, font: CTFont, ink: Ink) -> CTLine {
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: ink.cgColor(),
        ]
        let attributed = CFAttributedStringCreate(
            nil,
            text as CFString,
            attributes as CFDictionary
        )
        return CTLineCreateWithAttributedString(attributed!)
    }

    /// System UI font, so a composited capture matches what the overlay painted.
    private static func font(ofSize size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func digitInk(for ink: Ink) -> Ink {
        switch ink {
        case .yellow, .white: .black
        default: .white
        }
    }
}

/// Sizes shared by the overlay and the compositor.
public enum OverlayStyle {
    public static let textSize: CGFloat = 20
    public static let stepNumberSize: CGFloat = 15
}
