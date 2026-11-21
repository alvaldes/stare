import Foundation

/// Image format a capture is written in. Raw values are what the versioned
/// preferences blob persists; an unknown raw value decodes back to `.png`.
public enum CaptureFormat: String, Codable, CaseIterable, Sendable {
    /// Lossless PNG — today's format, and the default.
    case png
    /// Smaller JPEG for photographic captures.
    case jpeg

    /// English label shown in Settings.
    public var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }

    /// Extension appended to capture file names; `.jpeg` uses the common
    /// three-letter `"jpg"`.
    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }
}

/// Where a capture goes. `.clipboard` reproduces today's behaviour (both
/// `CaptureEditor` and the overlay write PNG/TIFF onto the pasteboard) and is
/// the default; `.folder` writes the capture as a file into an absolute or
/// home-anchored directory instead.
public enum CaptureDestination: Codable, Equatable, Sendable {
    /// Copy the capture to the pasteboard — today's behaviour.
    case clipboard
    /// Write the capture into this directory.
    case folder(path: String)

    private enum CodingKeys: String, CodingKey {
        case clipboard, folder
    }

    /// True when the path can name a capture directory: non-empty and rooted
    /// at an absolute path or the home shortcut. A relative path would
    /// silently move with the process's working directory, so it is unusable.
    public var isUsablePath: Bool {
        switch self {
        case .clipboard:
            return true
        case .folder(let path):
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && (trimmed.hasPrefix("/") || trimmed.hasPrefix("~"))
        }
    }

    /// Lenient decoding: an unusable folder path falls back to `.clipboard`
    /// instead of failing the whole document.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.clipboard) {
            self = .clipboard
            return
        }
        if let path = try? container.decode(String.self, forKey: .folder),
            CaptureDestination.folder(path: path).isUsablePath {
            self = .folder(path: path)
            return
        }
        self = .clipboard
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .clipboard: try container.encode(true, forKey: .clipboard)
        case .folder(let path): try container.encode(path, forKey: .folder)
        }
    }
}

/// Persisted capture settings (T3/S6): format, destination and the prefix of
/// generated capture file names. Today's capture is a PNG to the clipboard
/// named "Stare.png", which `.standard` reproduces exactly.
///
/// Every value is guarded on every path (init, assignment and decoding): the
/// file name prefix keeps only characters that need no escaping, so a capture
/// file name can never need quoting, and an unusable destination degrades to
/// `.clipboard` rather than storing a path that cannot be written.
public struct CapturePreference: Codable, Equatable, Sendable {
    /// Prefix used when the whole given one is unusable (empty, or carrying a
    /// character outside the safe set).
    public static let defaultPrefix = "Stare"

    /// The only characters a file name prefix may carry: ASCII letters,
    /// digits, hyphen, underscore and dot. Anything else — spaces, path
    /// separators, shell metacharacters, non-ASCII — makes the whole prefix
    /// fall back to `"Stare"`, so no character needing quoting or escaping
    /// can ever reach the filesystem.
    static let safePrefixCharacters: CharacterSet = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."
    )

    /// Image format the capture is written in; default `.png`.
    public var format: CaptureFormat

    /// Where the capture goes; default `.clipboard`, today's behaviour.
    public var destination: CaptureDestination

    /// First part of generated capture file names, always from the safe
    /// character set; default `"Stare"`.
    public var fileNamePrefix: String {
        didSet { fileNamePrefix = Self.sanitisedPrefix(fileNamePrefix) }
    }

    /// The capture preferences a fresh install gets, matching today's
    /// clipboard behaviour.
    public static let standard = CapturePreference()

    /// Creates capture preferences, sanitising the prefix and degrading an
    /// unusable folder destination to the clipboard.
    public init(format: CaptureFormat = .png, destination: CaptureDestination = .clipboard, fileNamePrefix: String = defaultPrefix) {
        self.format = format
        self.destination = destination.isUsablePath ? destination : .clipboard
        self.fileNamePrefix = Self.sanitisedPrefix(fileNamePrefix)
    }

    private enum CodingKeys: String, CodingKey {
        case format, destination, fileNamePrefix
    }

    /// Lenient decoding: an unknown format falls back to `.png`, an unusable
    /// destination to `.clipboard`, and an empty or unsafe prefix to
    /// `"Stare"` — every other field of the document still decodes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawFormat = try? container.decode(String.self, forKey: .format)
        self.format = rawFormat.flatMap(CaptureFormat.init(rawValue:)) ?? .png
        self.destination = (try? container.decode(CaptureDestination.self, forKey: .destination)) ?? .clipboard
        let rawPrefix = try? container.decode(String.self, forKey: .fileNamePrefix)
        self.fileNamePrefix = Self.sanitisedPrefix(rawPrefix)
    }

    /// Builds a capture file name: `<prefix>-<YYYY>-<MM>-<DD>-at-<HH>-<MM>-<SS>
    /// .<ext>`, for example `Stare-2026-11-21-at-14-05-33.png`.
    ///
    /// Invariant: no character needing escaping can appear. The prefix is
    /// sanitised to the safe character set, the date components are digits
    /// and hyphens, and the extension is alphabetic — so the name is stable,
    /// filesystem-safe, and second resolution plus the date make collisions
    /// within one capture workflow practically impossible.
    public func fileName(at date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        let year = String(format: "%04d", components.year ?? 0)
        return "\(fileNamePrefix)-\(year)-\(pad(components.month))-\(pad(components.day))"
            + "-at-\(pad(components.hour))-\(pad(components.minute))-\(pad(components.second))"
            + ".\(format.fileExtension)"
    }

    /// The given prefix when it is entirely safe, otherwise `defaultPrefix`.
    private static func sanitisedPrefix(_ prefix: String?) -> String {
        guard let prefix, !prefix.isEmpty,
            prefix.unicodeScalars.allSatisfy({ safePrefixCharacters.contains($0) })
        else { return defaultPrefix }
        return prefix
    }
}
