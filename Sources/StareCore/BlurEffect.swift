import CoreGraphics
import CoreImage
import Foundation

/// The single place that actually blurs pixels. The capture compositor and the
/// overlay both need the same effect, so it lives here as a pure function over
/// images: no windows, no marks, no state.
public enum BlurEffect {
    /// Default blur radius for a blurred mark, in points. The overlay and the
    /// compositor multiply it by their scale to get a pixel radius.
    public static let defaultRadius: CGFloat = 15

    /// Creating a `CIContext` is expensive, so all blurs share one.
    private static let sharedContext = CIContext()

    /// Gaussian blur of `pixelRect` inside `image`, returned as an image of that
    /// same size, oriented like `image`, ready to be drawn where the rect maps
    /// in view space.
    ///
    /// `pixelRect` is in `image` pixels with a bottom-left origin, the space
    /// shared by bitmap `CGContext`s and `CIImage`. The blur samples
    /// edge-extended content (`clampedToExtent`), so the crop's borders are not
    /// darkened or washed out by the filter. When the rect reaches past the
    /// image, the returned image covers the intersection; callers must draw it
    /// at that intersection. Returns nil when the rect is empty or completely
    /// outside the image instead of crashing: the callers have to fall back.
    public static func crop(_ image: CGImage, pixelRect: CGRect, radius: CGFloat) -> CGImage? {
        let fullRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = pixelRect.intersection(fullRect)
        guard !rect.isNull, !rect.isEmpty, rect.width >= 1, rect.height >= 1 else { return nil }

        // Extend the edges before blurring so the filter never samples beyond
        // the picture and darkens the crop borders.
        let input = CIImage(cgImage: image).clampedToExtent()
        let filter = CIFilter(
            name: "CIGaussianBlur",
            parameters: [
                kCIInputImageKey: input,
                kCIInputRadiusKey: radius,
            ]
        )
        guard let output = filter?.outputImage else { return nil }

        return sharedContext.createCGImage(output.cropped(to: rect), from: rect)
    }
}
