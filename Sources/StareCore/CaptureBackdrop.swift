import CoreGraphics
import Foundation

/// The save-time backdrop (T11/S18): optional padding, rounded corners and a
/// shadow around a capture, composed purely out of CGImage in and CGImage out
/// — no window, no screen, no presets, no ratios, no imported backgrounds.
/// Every parameter is optional and off by default; with all of them off the
/// composition is nothing at all and the capture is written exactly as today.
///
/// The composition never draws over the capture: the image is blitted 1:1 at
/// an offset into a larger canvas, so the pixels inside the padded region are
/// the original ones, unresampled — the downscale (`CaptureDownscale`) is the
/// only thing that may resample, and it runs after this composes.
public enum CaptureBackdrop {

    /// The largest padding a preference may ask for, in pixels. Beyond this
    /// the canvas grows enormous for no look anyone chose deliberately.
    public static let maxPadding = 128

    /// The largest corner radius a preference may store, in pixels. At
    /// compose time it is clamped again by half of the capture — a radius
    /// over that would invert the rounded rectangle and blank the image.
    public static let maxCornerRadius = 64

    /// The fixed canvas margin reserved to the shadow when it is on. The
    /// shadow has no dial of its own: it is cheap and looks one way.
    static let shadowCanvasMargin = 16

    /// The base the backdrop paints behind the image: the shadow's fill
    /// shape colour, and the background the composition flattens a canvas
    /// onto when the written format cannot carry alpha. One colour, defined
    /// here, so both uses stay the same.
    static let baseColour = CGColor(gray: 0, alpha: 1)

    /// The fixed shadow style: a 12-point blur with a slight downward offset
    /// at 40% black. Constants, not preferences — S18 asks for a backdrop,
    /// not a shadow editor.
    static let shadowBlur: CGFloat = 12
    static let shadowOffset = CGSize(width: 0, height: -6)
    static let shadowAlpha: CGFloat = 0.4

    /// The stored padding clamped into `0...maxPadding` — below zero
    /// degrades to off rather than to a negative (impossible) margin, and a
    /// giant value degrades to the maximum instead of an enormous canvas.
    public static func clampedPadding(_ padding: Int) -> Int {
        max(0, min(maxPadding, padding))
    }

    /// The stored corner radius clamped into `0...maxCornerRadius`, with the
    /// same degrade-don't-break rule as the padding.
    public static func clampedCornerRadius(_ radius: Int) -> Int {
        max(0, min(maxCornerRadius, radius))
    }

    /// The image flattened onto an opaque background, at its own size and
    /// colour space: a transparent margin encodes an undefined colour in a
    /// format that cannot carry alpha (JPEG), so the flatten paints the same
    /// opaque base the compose paints behind the image and draws the image
    /// over it 1:1 — no resampling. An image with nothing to flatten is
    /// returned unchanged.
    public static func flattened(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(baseColour)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// The capture composed into its backdrop, or nil when every parameter is
    /// off (no redraw applies — the caller writes the original image).
    ///
    /// The canvas is the capture plus the padding, plus a fixed margin on
    /// every side when the shadow is on so the shadow never clips. The image
    /// itself is drawn at an integer offset without scaling and clipped to a
    /// rounded rectangle when a radius is set; the padding area stays
    /// transparent, because an imported background is exactly what S18 rules
    /// out.
    public static func composed(
        _ image: CGImage,
        padding: Int,
        cornerRadius: Int,
        shadow: Bool
    ) -> CGImage? {
        let pad = clampedPadding(padding)
        let radius = clampedCornerRadius(cornerRadius)
        guard pad > 0 || radius > 0 || shadow else { return nil }
        let margin = shadow ? shadowCanvasMargin : 0
        let width = image.width + 2 * pad + 2 * margin
        let height = image.height + 2 * pad + 2 * margin
        guard width > 0, height > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: pad + margin, y: pad + margin, width: image.width, height: image.height)
        // Half of the capture is the largest honest radius: beyond it the
        // rounded rectangle inverts and the image would blank.
        let honestRadius = CGFloat(max(0, min(radius, image.width / 2, image.height / 2)))
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: honestRadius,
            cornerHeight: honestRadius,
            transform: nil
        )
        if shadow {
            // The shadow comes from one opaque fill behind the image: with
            // the shadow set, the fill paints the shape plus its soft halo.
            // The capture is drawn over it afterwards, so the fill itself
            // never shows through an opaque capture.
            context.saveGState()
            context.setShadow(
                offset: shadowOffset,
                blur: shadowBlur,
                color: CGColor(red: 0, green: 0, blue: 0, alpha: shadowAlpha)
            )
            context.addPath(path)
            context.setFillColor(baseColour)
            context.fillPath()
            context.restoreGState()
        }
        context.addPath(path)
        context.clip()
        // A 1:1 blit at an integer offset: no interpolation, no resampling —
        // the original pixels ride inside the padded region unchanged.
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
