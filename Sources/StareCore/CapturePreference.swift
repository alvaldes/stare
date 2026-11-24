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

    /// Save-time downscaling for folder saves (T7/S14): off by default —
    /// today's behaviour, where every capture is saved exactly as captured.
    public var downscaleMode: CaptureDownscale.Mode

    /// The pixel width `.maxWidth` scales wider captures down to; narrower
    /// captures are left alone. Never stored below 1, so nothing degrades to
    /// nothing. The default is comfortably under a Retina display's width.
    public var maxSaveWidth: Int {
        didSet { maxSaveWidth = Self.clampedSaveWidth(maxSaveWidth) }
    }

    /// The maximum width a fresh install gets for `.maxWidth` saves.
    public static let defaultMaxSaveWidth = 1600

    /// The file-name template a fresh install gets: empty, today's behaviour.
    public static let defaultFileNameTemplate = ""

    /// The only words a `{…}` token may carry in a template (T10/S17). Any
    /// other word — or any brace left dangling, empty or nested — makes the
    /// whole template fall back to today's prefix-based name.
    static let templateTokens: Set<String> = ["date", "time", "app", "display"]

    /// Token-driven name template for folder saves (T10/S17), off by default:
    /// an empty template is today's behaviour, byte for byte. Literal text
    /// keeps the same safe character set as the prefix, and every `{date}`,
    /// `{time}`, `{app}` and `{display}` token is substituted; anything a
    /// template cannot honour — an unknown token, malformed braces, an unsafe
    /// literal, or a token whose value is unavailable — degrades to today's
    /// name instead of writing one nobody asked for. The extension is
    /// appended after rendering — never doubled when the rendered name
    /// already ends in it — so the written name carries exactly one
    /// extension.
    public var fileNameTemplate: String {
        didSet { fileNameTemplate = Self.sanitisedTemplate(fileNameTemplate) }
    }

    /// Save backdrop (T11/S18), one field per feature, all optional and
    /// appended at the end of the document after the template — never
    /// inserted, so an older blob decodes with them at their defaults. The
    /// padding is a transparent margin in pixels; the corner radius rounds
    /// the capture; the shadow is a fixed cheap shadow. Zero padding, zero
    /// radius and no shadow together are today's behaviour, byte for byte.
    /// Both sizes clamp so a silly preference can neither blank the capture
    /// nor grow the canvas enormous; the radius is clamped again at compose
    /// time by half of the capture.
    public var backdropPadding: Int {
        didSet { backdropPadding = CaptureBackdrop.clampedPadding(backdropPadding) }
    }

    /// The backdrop's corner radius in pixels, clamped on every path.
    public var backdropCornerRadius: Int {
        didSet { backdropCornerRadius = CaptureBackdrop.clampedCornerRadius(backdropCornerRadius) }
    }

    /// Whether the save carries the fixed shadow behind the capture.
    public var backdropShadow: Bool

    /// The capture preferences a fresh install gets, matching today's
    /// clipboard behaviour.
    public static let standard = CapturePreference()

    /// Creates capture preferences, sanitising the prefix and the template
    /// and degrading an unusable folder destination to the clipboard.
    public init(
        format: CaptureFormat = .png,
        destination: CaptureDestination = .clipboard,
        fileNamePrefix: String = defaultPrefix,
        downscaleMode: CaptureDownscale.Mode = .off,
        maxSaveWidth: Int = defaultMaxSaveWidth,
        fileNameTemplate: String = defaultFileNameTemplate,
        backdropPadding: Int = 0,
        backdropCornerRadius: Int = 0,
        backdropShadow: Bool = false
    ) {
        self.format = format
        self.destination = destination.isUsablePath ? destination : .clipboard
        self.fileNamePrefix = Self.sanitisedPrefix(fileNamePrefix)
        self.downscaleMode = downscaleMode
        self.maxSaveWidth = Self.clampedSaveWidth(maxSaveWidth)
        self.fileNameTemplate = Self.sanitisedTemplate(fileNameTemplate)
        self.backdropPadding = CaptureBackdrop.clampedPadding(backdropPadding)
        self.backdropCornerRadius = CaptureBackdrop.clampedCornerRadius(backdropCornerRadius)
        self.backdropShadow = backdropShadow
    }

    private enum CodingKeys: String, CodingKey {
        case format, destination, fileNamePrefix
        // The downscale settings sit at the end of the document (T7/S14), so
        // an older blob decodes with them at their defaults.
        case downscaleMode, maxSaveWidth
        // The template sits after them (T10/S17) — fields are appended,
        // never inserted, so an older blob decodes with it at its default.
        case fileNameTemplate
        // The backdrop sits after the template (T11/S18), appended all the
        // same.
        case backdropPadding, backdropCornerRadius, backdropShadow
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
        self.downscaleMode =
            (try? container.decode(CaptureDownscale.Mode.self, forKey: .downscaleMode)) ?? .off
        let rawMaxSaveWidth = try? container.decode(Int.self, forKey: .maxSaveWidth)
        self.maxSaveWidth = Self.clampedSaveWidth(rawMaxSaveWidth ?? Self.defaultMaxSaveWidth)
        let rawTemplate = try? container.decode(String.self, forKey: .fileNameTemplate)
        self.fileNameTemplate = Self.sanitisedTemplate(rawTemplate)
        let rawBackdropPadding = try? container.decode(Int.self, forKey: .backdropPadding)
        self.backdropPadding = CaptureBackdrop.clampedPadding(rawBackdropPadding ?? 0)
        let rawBackdropCornerRadius = try? container.decode(Int.self, forKey: .backdropCornerRadius)
        self.backdropCornerRadius = CaptureBackdrop.clampedCornerRadius(rawBackdropCornerRadius ?? 0)
        self.backdropShadow = (try? container.decode(Bool.self, forKey: .backdropShadow)) ?? false
    }

    /// Builds a capture file name: `<prefix>-<YYYY>-<MM>-<DD>-at-<HH>-<MM>-<SS>`
    /// `.<ext>`, for example `Stare-2026-11-21-at-14-05-33.png` — or, when a
    /// template is set (T10/S17), the template with its tokens substituted.
    ///
    /// - Parameters:
    ///   - app: the frontmost app's name when the caller knows it; `nil`
    ///     means unavailable, which refuses `{app}` and produces today's
    ///     name instead of a name with a hole in it.
    ///   - display: the capture's display name when the caller knows it;
    ///     `nil` refuses `{display}` exactly as `app` does.
    ///
    /// Invariant: no character needing escaping can appear, and the name is
    /// always one component of the destination folder. Substitute values keep
    /// only the safe character set (so no path separator survives) and never
    /// begin with a dot (so the name is never Finder-hidden) and the
    /// extension is appended — at most once, never doubled when the rendered
    /// template already ends in it — so the rendered name is never exactly
    /// `.` or `..`. A template can rename the capture inside the folder but
    /// cannot move it out of it or hide it. The same date, app, display,
    /// template and format always produce the same name.
    public func fileName(
        at date: Date,
        calendar: Calendar = .current,
        app: String? = nil,
        display: String? = nil
    ) -> String {
        guard !fileNameTemplate.isEmpty,
            let rendered = Self.renderedTemplate(
                fileNameTemplate, date: date, calendar: calendar, app: app, display: display
            )
        else { return legacyFileName(at: date, calendar: calendar) }
        // The format's own extension is the one thing a template is never
        // doubled by: a literal template may end in ".png" because the dot is
        // a safe literal, and appending again would write "shot.png.png". A
        // rendered name that already ends in the extension is written as it
        // is — exactly one extension, and in another format the literal is
        // just the stem's tail ("shot.png" stays "shot.png.jpg" for JPEG).
        if rendered.lowercased().hasSuffix(".\(format.fileExtension)") { return rendered }
        return "\(rendered).\(format.fileExtension)"
    }

    /// Today's name, unchanged since before templates existed.
    private func legacyFileName(at date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        let year = String(format: "%04d", components.year ?? 0)
        return "\(fileNamePrefix)-\(year)-\(pad(components.month))-\(pad(components.day))"
            + "-at-\(pad(components.hour))-\(pad(components.minute))-\(pad(components.second))"
            + ".\(format.fileExtension)"
    }

    private enum TemplateSegment: Equatable {
        /// A run of safe literal characters.
        case literal(String)
        /// A known `{token}` word from `templateTokens`.
        case token(String)
    }

    /// The template's segments in order — literal runs of safe characters and
    /// known tokens — or nil when the template is unusable: an unknown or
    /// malformed token (dangling braces, empty or nested, never a known
    /// word), or a literal character outside the safe set. One scanner serves
    /// both storage-time sanitisation (`sanitisedTemplate`) and render-time
    /// substitution (`renderedTemplate`), so a template one accepts the other
    /// cannot fail — loosening one means loosening both, never a template
    /// that validates but silently falls back at render time.
    private static func parsedTemplate(_ template: String) -> [TemplateSegment]? {
        var segments: [TemplateSegment] = []
        var literal = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            if character == "{" {
                guard let close = template[index...].firstIndex(of: "}"),
                    close > template.index(after: index),
                    // No nested opening brace inside the token.
                    template[template.index(after: index)..<close].allSatisfy({ $0 != "{" }),
                    templateTokens.contains(String(template[template.index(after: index)..<close]))
                else { return nil }
                if !literal.isEmpty {
                    segments.append(.literal(literal))
                    literal = ""
                }
                segments.append(.token(String(template[template.index(after: index)..<close])))
                index = template.index(after: close)
            } else {
                if !isSafeLiteral(character) { return nil }
                literal.append(character)
                index = template.index(after: index)
            }
        }
        if !literal.isEmpty { segments.append(.literal(literal)) }
        return segments
    }

    /// The template with every `{token}` substituted, or nil when the
    /// template cannot be honoured: an unknown or malformed token, or a token
    /// whose value is missing, refuses the whole template.
    private static func renderedTemplate(
        _ template: String,
        date: Date,
        calendar: Calendar,
        app: String?,
        display: String?
    ) -> String? {
        guard let segments = parsedTemplate(template) else { return nil }
        var rendered = ""
        for segment in segments {
            switch segment {
            case .literal(let text):
                rendered += text
            case .token(let token):
                switch token {
                case "date":
                    let components = calendar.dateComponents([.year, .month, .day], from: date)
                    func pad(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
                    let year = String(format: "%04d", components.year ?? 0)
                    rendered += "\(year)-\(pad(components.month))-\(pad(components.day))"
                case "time":
                    let components = calendar.dateComponents([.hour, .minute, .second], from: date)
                    func pad(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
                    rendered += "\(pad(components.hour))-\(pad(components.minute))-\(pad(components.second))"
                case "app":
                    guard let value = sanitisedTokenValue(app) else { return nil }
                    rendered += value
                case "display":
                    guard let value = sanitisedTokenValue(display) else { return nil }
                    rendered += value
                default:
                    return nil
                }
            }
        }
        return rendered
    }

    /// A template is stored verbatim only when every literal character is in
    /// the safe character set and every brace group is a known token — not
    /// empty, not nested, not dangling; anything else stores as `""`,
    /// today's behaviour.
    private static func sanitisedTemplate(_ template: String?) -> String {
        guard let raw = template else { return "" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, parsedTemplate(trimmed) != nil else { return "" }
        return trimmed
    }

    /// A template's literal character is safe when it is exactly one scalar
    /// from the prefix's safe set — a multi-scalar grapheme is never safe.
    private static func isSafeLiteral(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 && safePrefixCharacters.contains(character.unicodeScalars.first!)
    }

    /// A token's substitute value keeps only the safe character set and must
    /// be non-empty: anything unsafe is dropped character by character, and
    /// an empty result means the value is unavailable, refusing the template.
    /// A value that begins with a dot is unsafe the same way: wherever the
    /// token sits, a dot-leading value at the template's start would render a
    /// dot-prefixed file name, which Finder hides — so an all-dots (or any
    /// dot-leading) value refuses the whole template and falls back to
    /// today's prefix name.
    private static func sanitisedTokenValue(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let safe = String(value.unicodeScalars.filter { safePrefixCharacters.contains($0) })
        guard !safe.isEmpty, !safe.hasPrefix(".") else { return nil }
        return safe
    }

    /// The given prefix when it is entirely safe, otherwise `defaultPrefix`.
    private static func sanitisedPrefix(_ prefix: String?) -> String {
        guard let prefix, !prefix.isEmpty,
            prefix.unicodeScalars.allSatisfy({ safePrefixCharacters.contains($0) })
        else { return defaultPrefix }
        return prefix
    }

    /// A saved width is never allowed to degrade to nothing: below 1 (a
    /// typo, a garbage blob) it floors at 1 pixel. There is no upper bound —
    /// a limit larger than the capture is a no-op by the never-upscale rule.
    private static func clampedSaveWidth(_ width: Int) -> Int {
        max(1, width)
    }
}
