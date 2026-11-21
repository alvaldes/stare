import Foundation

/// Persisted whiteboard defaults (T3/S6): what a fresh whiteboard opens with.
/// `.standard` reproduces today's behaviour exactly — one page on a white
/// background.
///
/// `pagesOnOpen` is clamped to 1...10 on every path (init, assignment and
/// decoding), so a malformed blob or UI value can never yield zero pages or a
/// runaway count. Decoding is lenient: an unknown background falls back to
/// `.white` instead of failing the whole document.
public struct WhiteboardDefaults: Codable, Equatable, Sendable {
    /// Valid range for the number of pages a whiteboard opens with.
    public static let pageRange: ClosedRange<Int> = 1...10

    /// Background the board's first page gets; default `.white`, today's
    /// behaviour.
    public var background: BoardBackground

    /// How many pages a whiteboard opens with, always clamped to `pageRange`.
    public var pagesOnOpen: Int {
        didSet { pagesOnOpen = Self.clamped(pagesOnOpen) }
    }

    /// The whiteboard defaults a fresh install gets, matching today's board.
    public static let standard = WhiteboardDefaults()

    /// Creates defaults, clamping `pagesOnOpen` into `pageRange`.
    public init(background: BoardBackground = .white, pagesOnOpen: Int = 1) {
        self.background = background
        self.pagesOnOpen = Self.clamped(pagesOnOpen)
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

    /// Lenient decoding: a missing or unknown background falls back to
    /// `.white`, and a missing or out-of-range page count takes the default
    /// of 1 or clamps into range.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawBackground = try? container.decode(String.self, forKey: .background)
        self.background = rawBackground.flatMap(BoardBackground.init(rawValue:)) ?? .white
        let decodedCount = (try? container.decodeIfPresent(Int.self, forKey: .pagesOnOpen)) ?? 1
        self.pagesOnOpen = Self.clamped(decodedCount)
    }

    /// Encodes the background as its raw string (the type it reuses from
    /// `WhiteboardPages.swift` is not `Codable` itself).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(background.rawValue, forKey: .background)
        try container.encode(pagesOnOpen, forKey: .pagesOnOpen)
    }

    private static func clamped(_ count: Int) -> Int {
        min(max(count, pageRange.lowerBound), pageRange.upperBound)
    }
}
