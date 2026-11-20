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
    public static func composite(
        marks: [Stroke],
        over base: CGImage,
        scale: CGFloat = 1
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

        for mark in marks where !mark.tool.isTransient {
            draw(mark, in: context)
        }

        context.restoreGState()
        return context.makeImage()
    }

    private static func draw(_ stroke: Stroke, in context: CGContext) {
        switch stroke.tool {
        case .text:
            drawText(stroke, in: context)
            return
        case .number:
            MarkRenderer.draw(stroke: stroke, in: context)
            drawStepNumber(stroke, in: context)
            return
        default:
            MarkRenderer.draw(stroke: stroke, in: context)
        }
    }

    private static func drawText(_ stroke: Stroke, in context: CGContext) {
        guard let text = stroke.text, !text.isEmpty, let origin = stroke.points.first else { return }
        let line = makeLine(text, font: font(ofSize: OverlayStyle.textSize), ink: stroke.ink)

        context.saveGState()
        // The context is flipped for overlay space, so glyphs need unmirroring.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: origin.x, y: origin.y + OverlayStyle.textSize)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawStepNumber(_ stroke: Stroke, in context: CGContext) {
        guard let number = stroke.stepNumber, let centre = stroke.points.first else { return }
        let line = makeLine(
            "\(number)",
            font: font(ofSize: OverlayStyle.stepNumberSize),
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
