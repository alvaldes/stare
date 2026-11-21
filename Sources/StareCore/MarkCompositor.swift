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
    /// `blurBase` (T12/S9) is what blur marks crop from instead of the base —
    /// the board capture passes the live frame there, because a whiteboard's
    /// base is the solid page colour and a blur mark has to show the real
    /// pixels the board's view blurs, not the page colour. It is sampled at
    /// its own scale (a live frame arrives downscaled), and when it is absent
    /// the drawing overlay's behaviour is unchanged: blur crops the base.
    ///
    /// `offset` (T12 fix) is the whiteboard page's pan: marks stored in page
    /// space are placed at `pagePoint - offset`, which is where the board's
    /// view shows them (`viewPoint = pagePoint - offset`), so a panned page's
    /// capture is what the board shows. Zero leaves the marks where they were
    /// drawn, exactly as the drawing overlay composes them.
    public static func composite(
        marks: [Stroke],
        over base: CGImage,
        scale: CGFloat = 1,
        blurBase: CGImage? = nil,
        offset: CGSize = .zero
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
        if offset == .zero {
            placed = marks
        } else {
            placed = marks.map { mark in
                var shifted = mark
                shifted.points = mark.points.map { point in
                    CGPoint(x: point.x - offset.width, y: point.y - offset.height)
                }
                return shifted
            }
        }

        for mark in placed where !mark.tool.isTransient {
            draw(mark, in: context, base: base, scale: scale, blurBase: blurBase)
        }

        context.restoreGState()
        return context.makeImage()
    }

    private static func draw(
        _ stroke: Stroke,
        in context: CGContext,
        base: CGImage,
        scale: CGFloat,
        blurBase: CGImage?
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
                drawBlur(stroke, in: context, base: base, scale: scale, blurBase: blurBase)
            }
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

    /// T5/S3: a blur mark is the captured content underneath, blurred, so it
    /// composites a blurred crop of the base frame instead of stroking a
    /// rectangle. `BlurEffect` works in image pixels, which share the bitmap
    /// context's bottom-left origin; the crop is drawn back at the mark's
    /// rectangle in overlay space, where the context's transform already does
    /// the scaling and the flip.
    private static func drawBlur(
        _ stroke: Stroke,
        in context: CGContext,
        base: CGImage,
        scale: CGFloat,
        blurBase: CGImage? = nil
    ) {
        guard let first = stroke.points.first, let last = stroke.points.last else { return }
        let rect = PathBuilder.normalizedRect(from: first, to: last)
        guard rect.width > 0, rect.height > 0 else { return }

        // With a blur base (the board's live frame), crop from it at its own
        // scale: the frame is what the board's view blurs, and it arrives
        // downscaled relative to the display-sized base.
        let source = blurBase ?? base
        let sourceScale = blurBase != nil
            ? scale * CGFloat(source.width) / CGFloat(base.width)
            : scale
        let pixelRect = CGRect(
            x: rect.minX * sourceScale,
            y: CGFloat(source.height) - rect.maxY * sourceScale,
            width: rect.width * sourceScale,
            height: rect.height * sourceScale
        )
        guard let blurred = BlurEffect.crop(
            source,
            pixelRect: pixelRect,
            radius: BlurEffect.defaultRadius * sourceScale
        ) else { return }

        // The crop rectangle never rotates: the pixels always come from the
        // unrotated area of the base frame. The cropped image itself is what
        // turns about the mark's anchor, so a rotated blur patch still shows
        // the pixels underneath it. The context is flipped for overlay space,
        // so an image drawn plainly would land upside down; unflip it inside
        // the rectangle.
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(blurred, in: CGRect(origin: .zero, size: rect.size))
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
