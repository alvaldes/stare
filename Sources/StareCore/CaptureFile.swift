import AppKit
import Foundation

/// The folder destination's writer (T11/S6; T7/S14 adds save-time
/// downscaling): the capture goes into the chosen folder, named by
/// `CapturePreference.fileName(at:)` in the chosen format, optionally scaled
/// down first per the persisted preference. Downscaling applies to the file
/// write only — the pasteboard path (`CaptureFile.data` and the caller's own
/// copy) never sees the preference and always carries the full capture. The
/// optional save backdrop (T11/S18) is composed onto the image before any
/// downscale, so the padding is never resampled on its own and the capture's
/// corners do not go soft; the clipboard path is unaffected by both.
///
/// `write` encodes the image exactly as before whenever no scaling applies,
/// so a capture saved with the switch off is byte-for-byte identical to
/// today's file.
public enum CaptureFile {
    /// Writes `image` into the preference's folder destination. Returns the
    /// written URL, or nil when the destination is not a usable folder or
    /// the write failed — the caller decides the fallback.
    ///
    /// - Parameter scale: pixels per point of the source canvas, when the
    ///   caller can vouch for it; nil leaves a `.oneX` request unscaled
    ///   (nothing is guessed) while `.maxWidth` still applies.
    /// - Parameter app: the frontmost app's name for the `{app}` name token
    ///   (T10/S17), when the caller knows it; nil leaves the token
    ///   unavailable and the template refused.
    /// - Parameter displayName: the capture's display name for the
    ///   `{display}` name token, with the same nil contract as `app`.
    public static func write(
        _ image: CGImage,
        preference: CapturePreference,
        date: Date,
        calendar: Calendar = .current,
        scale: CGFloat? = nil,
        app: String? = nil,
        displayName: String? = nil
    ) -> URL? {
        guard case .folder(let path) = preference.destination,
            preference.destination.isUsablePath
        else { return nil }
        // Backdrop first, at full resolution: the padding is composed around
        // the capture before anything resamples, so one downscale resamples
        // capture and padding together and the padding never smears on its
        // own. With the backdrop off this composes nothing and `padded` is
        // the original image, so the default save stays byte for byte.
        let padded = CaptureBackdrop.composed(
            image,
            padding: preference.backdropPadding,
            cornerRadius: preference.backdropCornerRadius,
            shadow: preference.backdropShadow
        ) ?? image
        var saved = scaled(padded, preference: preference, scale: scale) ?? padded
        // A composed canvas carries a transparent margin, and a format that
        // cannot carry alpha (JPEG) would encode it as an undefined colour:
        // flatten it onto the backdrop's opaque base before encoding. An
        // uncomposed save keeps today's bytes exactly.
        if preference.format == .jpeg, padded !== image {
            saved = CaptureBackdrop.flattened(saved) ?? saved
        }
        guard let data = data(for: saved, format: preference.format) else { return nil }
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        let name = preference.fileName(at: date, calendar: calendar, app: app, display: displayName)
        let url = folder.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// One representation call, shared by writing and the save panel. Takes
    /// no preference by design: the clipboard path never downscales.
    public static func data(for image: CGImage, format: CaptureFormat) -> Data? {
        let type: NSBitmapImageRep.FileType = format == .png ? .png : .jpeg
        return NSBitmapImageRep(cgImage: image).representation(using: type, properties: [:])
    }

    /// The image rescaled per the preference's downscale settings, or nil
    /// when today's pixels are written as they are.
    private static func scaled(
        _ image: CGImage,
        preference: CapturePreference,
        scale: CGFloat?
    ) -> CGImage? {
        let logicalWidth = scale.flatMap { scale in
            scale > 0 ? CGFloat(image.width) / scale : nil
        }
        let target = CaptureDownscale.targetPixelWidth(
            pixelWidth: image.width,
            logicalWidth: logicalWidth,
            mode: preference.downscaleMode,
            maxPixelWidth: preference.maxSaveWidth
        )
        return target.flatMap { CaptureDownscale.image(image, targetPixelWidth: $0) }
    }
}
