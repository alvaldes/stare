import Foundation

/// Where the drawing overlay draws: every display or only the one under the
/// pointer. Raw values are what the versioned preferences blob persists and
/// the strings today's picker has always used; decoding an unknown raw value
/// falls back to the default instead of failing the document.
public enum OverlayScope: String, Codable, CaseIterable, Sendable {
    /// Draw on every display — today's default.
    case all
    /// Draw only on the display the pointer is on when the session starts.
    case active

    /// English label shown in Settings, matching today's picker.
    public var title: String {
        switch self {
        case .all: "Every display"
        case .active: "Only the active display"
        }
    }
}

/// Where the palette opens. Raw values are what the versioned preferences
/// blob persists and the strings today's picker has always used; decoding an
/// unknown raw value falls back to the default instead of failing the
/// document.
public enum PalettePlacement: String, Codable, CaseIterable, Sendable {
    /// Near the pointer — today's default.
    case cursor
    /// On the display of the front window.
    case frontWindow
    /// On the last used display.
    case fixed

    /// English label shown in Settings, matching today's picker.
    public var title: String {
        switch self {
        case .cursor: "Under the pointer"
        case .frontWindow: "On the display of the front window"
        case .fixed: "On the last used display"
        }
    }
}

/// How long a laser mark stays on screen before fading out, in seconds. The
/// raw values are exactly today's picker values; decoding an unknown raw
/// value falls back to the default instead of failing the document.
public enum LaserLifetime: Double, Codable, CaseIterable, Sendable {
    case one = 1
    case two = 2
    case twoPointFive = 2.5
    case three = 3
    case five = 5

    /// English label shown in Settings. Verbatim today's picker strings,
    /// including the "1 seconds" wording, so the copy never changes.
    public var title: String {
        switch self {
        case .one: "1 seconds"
        case .two: "2 seconds"
        case .twoPointFive: "2.5 seconds"
        case .three: "3 seconds"
        case .five: "5 seconds"
        }
    }
}

/// The drawing preferences that are not the pointer style: the armed frame,
/// where the overlay draws, where the palette opens and how long the laser
/// lasts. Everything here used to be a lone UserDefaults key; it now lives in
/// the single versioned `AppPreferences` blob. Decoding is lenient: an
/// unknown raw value falls back to the default of that field and never fails
/// the document.
public struct GeneralPreferences: Codable, Equatable, Sendable {
    /// Whether the armed frame is drawn around displays before the first mark.
    public var showArmedFrame: Bool
    /// Which displays the overlay draws on.
    public var scope: OverlayScope
    /// Where the palette opens.
    public var palettePlacement: PalettePlacement
    /// How long a laser mark stays on screen.
    public var laserLifetime: LaserLifetime

    /// The general preferences a fresh install gets, matching what the app
    /// ships today.
    public static let standard = GeneralPreferences()

    /// Creates the general preferences; each unset parameter takes its
    /// shipped default.
    public init(
        showArmedFrame: Bool = true,
        scope: OverlayScope = .all,
        palettePlacement: PalettePlacement = .cursor,
        laserLifetime: LaserLifetime = .twoPointFive
    ) {
        self.showArmedFrame = showArmedFrame
        self.scope = scope
        self.palettePlacement = palettePlacement
        self.laserLifetime = laserLifetime
    }

    private enum CodingKeys: String, CodingKey {
        case showArmedFrame, scope, palettePlacement, laserLifetime
    }

    /// Lenient decoding: a missing or unknown raw value falls back to the
    /// default of that field instead of failing the whole document.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showArmedFrame = (try? container.decode(Bool.self, forKey: .showArmedFrame)) ?? true
        let rawScope = try? container.decode(String.self, forKey: .scope)
        self.scope = rawScope.flatMap(OverlayScope.init(rawValue:)) ?? .all
        let rawPlacement = try? container.decode(String.self, forKey: .palettePlacement)
        self.palettePlacement = rawPlacement.flatMap(PalettePlacement.init(rawValue:)) ?? .cursor
        let rawLifetime = try? container.decode(Double.self, forKey: .laserLifetime)
        self.laserLifetime = rawLifetime.flatMap(LaserLifetime.init(rawValue:)) ?? .twoPointFive
    }
}
