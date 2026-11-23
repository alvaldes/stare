import CoreGraphics
import Foundation

/// Save-time downscaling arithmetic (T7/S14): a Retina capture is twice the
/// pixels a chat wants, so a folder save can opt into shrinking it — to 1×
/// (the logical size) or to a maximum width. The decision is pure and lives
/// here; the encode path (`CaptureFile`) stays thin. Off by default, and
/// never an upscale: a 1× capture asked to become 1× stays as it is, and a
/// max width larger than the image leaves it alone.
public enum CaptureDownscale {

    /// The scaling a saved file may request, straight from the persisted
    /// preference. Raw values are what the versioned preferences blob
    /// persists; an unknown raw value decodes back to `.off`.
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Save exactly as captured — today's behaviour, the default.
        case off
        /// Scale a Retina capture down to its logical size (1×).
        case oneX
        /// Scale wider captures down to a maximum width in pixels.
        case maxWidth

        /// English label shown in Settings.
        public var title: String {
            switch self {
            case .off: "Off"
            case .oneX: "To 1×"
            case .maxWidth: "Max width"
            }
        }
    }

    /// Nothing degrades to nothing: a target width is never below 1 pixel.
    static let minimumTargetWidth = 1

    /// The target pixel width for the request, or nil when the image should
    /// be left alone: scaling off, an image already at or under the target
    /// (never an upscale), or a 1× request with a logical width the caller
    /// cannot vouch for.
    ///
    /// - Parameters:
    ///   - pixelWidth: the capture's width in pixels.
    ///   - logicalWidth: the capture's width in points, when the caller
    ///     knows it; nil when it cannot be vouched for (no 1× scaling then).
    ///   - mode: the persisted downscale switch.
    ///   - maxPixelWidth: the persisted maximum width for `.maxWidth`.
    public static func targetPixelWidth(
        pixelWidth: Int,
        logicalWidth: CGFloat?,
        mode: Mode,
        maxPixelWidth: Int
    ) -> Int? {
        switch mode {
        case .off:
            return nil
        case .maxWidth:
            let limit = max(minimumTargetWidth, maxPixelWidth)
            guard pixelWidth > limit else { return nil }
            return limit
        case .oneX:
            guard let logicalWidth, logicalWidth > 0 else { return nil }
            let target = max(
                minimumTargetWidth,
                Int(logicalWidth.rounded(.toNearestOrAwayFromZero))
            )
            guard target < pixelWidth else { return nil }
            return target
        }
    }

    /// The image scaled down to `targetPixelWidth` with the aspect kept, or
    /// nil when no redraw applies: a target at or above the pixel width (the
    /// identity and the never-upscale rule are one guard) or below the floor
    /// is refused, and the caller writes the original image instead.
    public static func image(_ image: CGImage, targetPixelWidth: Int) -> CGImage? {
        guard targetPixelWidth >= minimumTargetWidth, targetPixelWidth < image.width else { return nil }
        let targetHeight = max(
            minimumTargetWidth,
            Int((CGFloat(targetPixelWidth) / CGFloat(image.width) * CGFloat(image.height))
                .rounded(.toNearestOrAwayFromZero))
        )
        guard let context = CGContext(
            data: nil,
            width: targetPixelWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetPixelWidth, height: targetHeight))
        return context.makeImage()
    }
}
