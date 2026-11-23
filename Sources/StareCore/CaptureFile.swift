import AppKit
import Foundation

/// The folder destination's writer (T11/S6; T7/S14 adds save-time
/// downscaling): the capture goes into the chosen folder, named by
/// `CapturePreference.fileName(at:)` in the chosen format, optionally scaled
/// down first per the persisted preference. Downscaling applies to the file
/// write only — the pasteboard path (`CaptureFile.data` and the caller's own
/// copy) never sees the preference and always carries the full capture.
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
    public static func write(
        _ image: CGImage,
        preference: CapturePreference,
        date: Date,
        calendar: Calendar = .current,
        scale: CGFloat? = nil
    ) -> URL? {
        guard case .folder(let path) = preference.destination,
            preference.destination.isUsablePath
        else { return nil }
        let saved = scaled(image, preference: preference, scale: scale) ?? image
        guard let data = data(for: saved, format: preference.format) else { return nil }
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        let url = folder.appendingPathComponent(preference.fileName(at: date, calendar: calendar))
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
