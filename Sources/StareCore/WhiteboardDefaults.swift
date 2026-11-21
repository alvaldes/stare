import Foundation

/// The background a new whiteboard board starts with (T13/S8): white, black,
/// or System, which resolves from the app's appearance when a board opens —
/// white on light mode, black on dark mode. White and black reproduce today's
/// choices exactly; `BoardBackground` (the per-page colour, flipped with ⌘B)
/// stays white/black only, untouched.
///
/// Persistence note: older blobs stored `"white"|"black"` under the same
/// `background` key, so a previous choice decodes straight into this enum —
/// a stored black board never resets to white.
public enum WhiteboardBackgroundChoice: String, CaseIterable, Equatable, Sendable {
    case white
    case black
    /// Resolves from the app's appearance at board-open time.
    case system

    /// The picker's label.
    public var title: String {
        switch self {
        case .white: "White"
        case .black: "Black"
        case .system: "System"
        }
    }

    /// One line under the picker; the System entry states what it resolves
    /// to, so the choice is not a mystery in either theme.
    public var detail: String {
        switch self {
        case .white: "Every page starts white."
        case .black: "Every page starts black."
        case .system: "White in light mode, black in dark mode \u{2014} set when the board opens."
        }
    }
}

/// Persisted whiteboard defaults (T3/S6, T13/S8): what a fresh whiteboard
/// opens with. `.standard` reproduces today's behaviour exactly — one page on
/// a white background.
///
/// `pagesOnOpen` is clamped to 1...10 on every path (init, assignment and
/// decoding), so a malformed blob or UI value can never yield zero pages or a
/// runaway count. Decoding is lenient: an unknown background falls back to
/// white instead of failing the whole document, and blobs written before the
/// System choice existed decode from the same `background` key unchanged.
public struct WhiteboardDefaults: Codable, Equatable, Sendable {
    /// Valid range for the number of pages a whiteboard opens with.
    public static let pageRange: ClosedRange<Int> = 1...10

    /// Background choice the board's first page gets; white and black are
    /// today's behaviour, `system` resolves from the app's appearance when a
    /// board opens.
    public var background: WhiteboardBackgroundChoice

    /// How many pages a whiteboard opens with, always clamped to `pageRange`.
    public var pagesOnOpen: Int {
        didSet { pagesOnOpen = Self.clamped(pagesOnOpen) }
    }

    /// The whiteboard defaults a fresh install gets, matching today's board.
    public static let standard = WhiteboardDefaults()

    /// Creates defaults, clamping `pagesOnOpen` into `pageRange`.
    public init(background: WhiteboardBackgroundChoice = .white, pagesOnOpen: Int = 1) {
        self.background = background
        self.pagesOnOpen = Self.clamped(pagesOnOpen)
    }

    /// Resolves the stored choice into a board page colour: `system` becomes
    /// black when the app is in dark appearance and white otherwise, while
    /// white and black resolve to themselves. The call site reads the
    /// appearance at board-open time, so a theme change later never repaints
    /// an already open board.
    public func resolvedBackground(isDarkAppearance: Bool) -> BoardBackground {
        switch background {
        case .system: isDarkAppearance ? .black : .white
        case .white: .white
        case .black: .black
        }
    }

    /// Returns a copy with the given page count, clamped into `pageRange`,
    /// leaving the receiver untouched.
    public func assigning(pagesOnOpen newCount: Int) -> WhiteboardDefaults {
        var copy = self
        copy.pagesOnOpen = newCount
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case background, pagesOnOpen
    }

    /// Lenient decoding: a missing or unknown background falls back to white,
    /// and a missing or out-of-range page count takes the default of 1 or
    /// clamps into range. The same raw string also carries the pre-System
    /// shapes (`"white"`, `"black"`), so old blobs migrate without a reset.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawBackground = try? container.decode(String.self, forKey: .background)
        self.background = rawBackground.flatMap(WhiteboardBackgroundChoice.init(rawValue:)) ?? .white
        let decodedCount = (try? container.decodeIfPresent(Int.self, forKey: .pagesOnOpen)) ?? 1
        self.pagesOnOpen = Self.clamped(decodedCount)
    }

    /// Encodes the background as its raw string (`"white"`, `"black"` or
    /// `"system"` — the same key and shape older writers used, so the
    /// document stays understandable to future readers).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(background.rawValue, forKey: .background)
        try container.encode(pagesOnOpen, forKey: .pagesOnOpen)
    }

    private static func clamped(_ count: Int) -> Int {
        min(max(count, pageRange.lowerBound), pageRange.upperBound)
    }
}
