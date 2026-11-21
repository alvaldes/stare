import Foundation

/// Named shape of the pointer highlight offered by Settings. Raw values are
/// what the versioned preferences blob persists; the legacy per-key
/// `"circle"`/`"squircle"` strings are mapped onto these during migration.
public enum PointerStylePreset: String, Codable, CaseIterable, Sendable {
    /// Hollow ellipse ring — today's "circle".
    case ring
    /// Hollow rounded-square ring.
    case squircle
    /// The squircle's rounded square rotated 45°: banded, with a bright edge,
    /// its rounded vertices pointing past the outer circle along the axes and
    /// its edges touching the circle along the diagonals.
    case rhombus
    /// Filled disc with no band.
    case dot
    /// Soft radial falloff with no hard edge.
    case spotlight

    /// English label shown in Settings.
    public var title: String {
        switch self {
        case .ring: "Ring"
        case .squircle: "Squircle"
        case .rhombus: "Rhombus"
        case .dot: "Dot"
        case .spotlight: "Spotlight"
        }
    }
}

/// How the outer boundary line of a banded shape is drawn. The band itself
/// is always a filled coloured ring carrying a thin line on both of its
/// boundaries; this choice turns only the outer one into dashes. Raw values
/// are what the preferences blob persists; decoding an unknown string falls
/// back to `.solid`.
public enum PointerBorderStyle: String, Codable, CaseIterable, Sendable {
    /// Today's filled band with its bright edges.
    case solid
    /// The outline stroked as dashes instead of a filled band.
    case dashed

    /// English label shown in Settings.
    public var title: String {
        switch self {
        case .solid: "Solid"
        case .dashed: "Dashed"
        }
    }
}

/// What a click does to the highlight. Raw values are what the preferences
/// blob persists; decoding an unknown string falls back to `.scale`.
public enum PointerClickAnimation: String, Codable, CaseIterable, Sendable {
    /// The highlight grows with the click pulse — today's behaviour.
    case scale
    /// The same pulse envelope turns the shape about its centre instead of
    /// growing it.
    case rotate

    /// English label shown in Settings.
    public var title: String {
        switch self {
        case .scale: "Scale"
        case .rotate: "Rotate"
        }
    }
}

/// Where the pointer highlight takes its colour from.
public enum PointerColorSource: Codable, Equatable, Sendable {
    /// Follows the active ink — today's behaviour, and the default.
    case ink
    /// Always uses the carried ink, independent of the active one.
    case fixed(Ink)

    private enum CodingKeys: String, CodingKey {
        case ink, fixed
    }

    /// Encodes as a marker for `.ink` or the carried ink for `.fixed`;
    /// decoding is lenient and falls back to `.ink` on anything malformed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.ink) {
            self = .ink
            return
        }
        if let raw = try? container.decode(String.self, forKey: .fixed),
            let ink = Ink(rawValue: raw) {
            self = .fixed(ink)
            return
        }
        self = .ink
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ink: try container.encode(true, forKey: .ink)
        case .fixed(let ink): try container.encode(ink.rawValue, forKey: .fixed)
        }
    }
}

/// Pure model of the pointer highlight (⌥⇧M): what the user chose, with every
/// numeric invariant already enforced (all values clamped to their valid
/// range, whichever path produced them — init, decoding or mutation). No
/// AppKit, no persistence: rendering consumes `appearance(ink:)` and
/// persistence lives in `AppPreferences`.
public struct PointerStyle: Codable, Equatable, Sendable {
    /// Valid highlight diameter range, in points.
    public static let sizeRange: ClosedRange<Double> = 32...240
    /// Valid band thickness range, as a ratio of the radius.
    public static let bandWidthRange: ClosedRange<Double> = 0.08...0.5
    /// Valid glow strength range; 0 turns the glow off.
    public static let glowRange: ClosedRange<Double> = 0...1
    /// Valid overall opacity range: fully see-through is not a state worth
    /// offering, so the floor sits above it.
    public static let opacityRange: ClosedRange<Double> = 0.25...1

    public static let defaultSize: Double = 72
    public static let defaultBandWidth: Double = 0.26
    public static let defaultGlowIntensity: Double = 1
    public static let defaultOpacity: Double = 1

    /// Shape preset; decoding an unknown string falls back to `.ring`.
    public var preset: PointerStylePreset

    /// Highlight diameter in points, always clamped to `sizeRange`.
    public var size: Double {
        didSet { size = Self.clamp(size, to: Self.sizeRange) }
    }

    /// Where the colour comes from.
    public var colorSource: PointerColorSource

    /// Band thickness as a ratio of the radius, always clamped to
    /// `bandWidthRange`.
    public var bandWidth: Double {
        didSet { bandWidth = Self.clamp(bandWidth, to: Self.bandWidthRange) }
    }

    /// Glow strength, always clamped to `glowRange`; 0 means the glow is off.
    public var glowIntensity: Double {
        didSet { glowIntensity = Self.clamp(glowIntensity, to: Self.glowRange) }
    }

    /// Fade the highlight down when the pointer stops moving.
    public var fadeWhenIdle: Bool

    /// Solid or dashed outer boundary line of a banded shape; the band is
    /// always filled, so only the outer line changes with this value. The
    /// non-banded shapes (dot, spotlight) ignore it.
    public var borderStyle: PointerBorderStyle

    /// Overall opacity, always clamped to `opacityRange`: multiplies every
    /// alpha the highlight draws, so 1 reproduces today's look exactly.
    public var opacity: Double {
        didSet { opacity = Self.clamp(opacity, to: Self.opacityRange) }
    }

    /// What a click does to the highlight.
    public var clickAnimation: PointerClickAnimation

    /// The style a fresh install gets, matching the look the app ships today.
    public static let standard = PointerStyle(
        preset: .squircle,
        size: defaultSize,
        colorSource: .ink,
        bandWidth: defaultBandWidth,
        glowIntensity: defaultGlowIntensity,
        fadeWhenIdle: true
    )

    /// Creates a style, clamping the numeric values into their ranges.
    public init(
        preset: PointerStylePreset = .squircle,
        size: Double = defaultSize,
        colorSource: PointerColorSource = .ink,
        bandWidth: Double = defaultBandWidth,
        glowIntensity: Double = defaultGlowIntensity,
        fadeWhenIdle: Bool = true,
        borderStyle: PointerBorderStyle = .solid,
        opacity: Double = defaultOpacity,
        clickAnimation: PointerClickAnimation = .scale
    ) {
        self.preset = preset
        self.size = size
        self.colorSource = colorSource
        self.bandWidth = bandWidth
        self.glowIntensity = glowIntensity
        self.fadeWhenIdle = fadeWhenIdle
        self.borderStyle = borderStyle
        self.opacity = opacity
        self.clickAnimation = clickAnimation
        // Property observers do not run during initialisation, so clamp once
        // here for every value produced through this path.
        self.size = Self.clamp(self.size, to: Self.sizeRange)
        self.bandWidth = Self.clamp(self.bandWidth, to: Self.bandWidthRange)
        self.glowIntensity = Self.clamp(self.glowIntensity, to: Self.glowRange)
        self.opacity = Self.clamp(self.opacity, to: Self.opacityRange)
    }

    private enum CodingKeys: String, CodingKey {
        case preset, size, colorSource, bandWidth, glowIntensity, fadeWhenIdle
        case borderStyle, opacity, clickAnimation
    }

    /// Lenient decoding: unknown preset strings fall back to `.ring`, unknown
    /// border and click-animation values fall back to `.solid`/`.scale`,
    /// missing keys take the defaults of `standard`, and out-of-range numbers
    /// clamp.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPreset = try? container.decode(String.self, forKey: .preset)
        self.preset = rawPreset.flatMap(PointerStylePreset.init(rawValue:)) ?? .ring
        self.size = Self.clamp(
            (try? container.decodeIfPresent(Double.self, forKey: .size)) ?? Self.defaultSize,
            to: Self.sizeRange
        )
        self.colorSource = (try? container.decode(PointerColorSource.self, forKey: .colorSource)) ?? .ink
        self.bandWidth = Self.clamp(
            (try? container.decodeIfPresent(Double.self, forKey: .bandWidth)) ?? Self.defaultBandWidth,
            to: Self.bandWidthRange
        )
        self.glowIntensity = Self.clamp(
            (try? container.decodeIfPresent(Double.self, forKey: .glowIntensity)) ?? Self.defaultGlowIntensity,
            to: Self.glowRange
        )
        self.fadeWhenIdle = (try? container.decodeIfPresent(Bool.self, forKey: .fadeWhenIdle)) ?? true
        let rawBorder = try? container.decode(String.self, forKey: .borderStyle)
        self.borderStyle = rawBorder.flatMap(PointerBorderStyle.init(rawValue:)) ?? .solid
        self.opacity = Self.clamp(
            (try? container.decodeIfPresent(Double.self, forKey: .opacity)) ?? Self.defaultOpacity,
            to: Self.opacityRange
        )
        let rawClick = try? container.decode(String.self, forKey: .clickAnimation)
        self.clickAnimation = rawClick.flatMap(PointerClickAnimation.init(rawValue:)) ?? .scale
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Projects the style into everything a renderer needs, resolving
    /// `.ink` colour sources to the passed active ink and `.fixed` ones to
    /// their own ink. The overlay and the Settings preview both consume this
    /// projection, so the preview cannot drift from the real highlight.
    public func appearance(ink activeInk: Ink) -> PointerAppearance {
        PointerAppearance(style: self, activeInk: activeInk)
    }
}

/// Everything a renderer needs to draw the pointer highlight, derived from a
/// `PointerStyle` plus the active ink. All of today's drawing constants —
/// band ratio, edge width, glow stops and glow extent — live here, so the
/// invalidation rect can be computed from the appearance instead of constants.
public struct PointerAppearance: Equatable, Sendable {
    /// Preset-specific shape the renderer draws.
    public enum Geometry: Equatable, Sendable {
        /// Hollow ellipse: outer boundary at `radius`, inner hole at
        /// `radius - bandWidth * radius`.
        case ring
        /// Hollow rounded square with corner radius
        /// `cornerRadiusFactor * radius`.
        case squircle
        /// Filled disc of `radius`; no band, no edge.
        case dot
        /// Soft radial falloff outward from `radius`; no hard edge.
        case spotlight
        /// The squircle's rounded square rotated 45°: banded, with a bright
        /// edge, drawn by rotating the shape's own drawing by 45° about the
        /// centre. Its rounded vertices reach ≈1.16 × radius along the
        /// axes — past the outer circle the other presets fill — while its
        /// edges touch the circle along the diagonals.
        case rhombus
    }

    /// Ink the highlight is drawn in.
    public var ink: Ink
    /// Half the chosen diameter, in points.
    public var radius: Double
    /// Band thickness measured inward from the outer boundary, as a ratio of
    /// `radius`: the style's band for ring, squircle and rhombus, and 0 for
    /// the filled dot and the edge-less spotlight.
    public var bandWidth: Double
    /// Width of the bright edge stroked on the boundaries, in points; 0 when
    /// the shape has no hard edge.
    public var edgeWidth: Double
    /// Corner radius as a factor of `radius` for the squircle; nil otherwise.
    public var cornerRadiusFactor: Double?
    /// Radial glow stops as (location, alpha) pairs, location 0 at the band's
    /// inner edge and 1 at the outer glow reach; empty when the glow is off.
    public var glowStops: [(location: Double, alpha: Double)]
    /// Outer reach of the glow as a multiplier of `radius` (today's
    /// `pointerGlowMultiplier`).
    public var glowExtent: Double
    /// Extra points of margin beyond the glow reach, so invalidation rects
    /// derived from the appearance never clip the gradient.
    public var glowMargin: Double
    /// Alpha of the translucent body fill for banded and filled shapes
    /// (today's `0.55 * idleAlpha`).
    public var bandFillAlpha: Double
    /// Alpha of the bright edge stroke (today's `0.95 * idleAlpha`).
    public var edgeAlpha: Double
    /// Whether a banded shape draws its outer boundary line as dashes
    /// instead of a solid line; the renderer picks the rhythm from the edge
    /// width, and the band stays filled underneath either way.
    public var dashed: Bool
    /// Preset-specific geometry.
    public var geometry: Geometry

    /// Today's reach of the radial glow, as a multiplier of the radius.
    static let glowExtentMultiplier: Double = 1.9
    /// Today's safety margin added to the glow reach for invalidation.
    static let glowMarginPoints: Double = 12
    /// Today's bright edge width, in points.
    static let edgeWidthPoints: Double = 2
    /// Today's squircle corner radius, as a factor of the radius.
    static let squircleCornerFactor: Double = 0.62

    init(style: PointerStyle, activeInk: Ink) {
        switch style.colorSource {
        case .ink: self.ink = activeInk
        case .fixed(let ink): self.ink = ink
        }
        self.radius = style.size / 2
        self.glowExtent = Self.glowExtentMultiplier
        self.glowMargin = Self.glowMarginPoints
        // The style's opacity multiplies every alpha the highlight draws —
        // band, edge, dashes and glow alike — so an opacity of 1 reproduces
        // today's alphas exactly.
        self.bandFillAlpha = 0.55 * style.opacity
        self.edgeAlpha = 0.95 * style.opacity
        self.dashed = style.borderStyle == .dashed
        switch style.preset {
        case .ring:
            self.bandWidth = style.bandWidth
            self.geometry = .ring
        case .squircle, .rhombus:
            self.bandWidth = style.bandWidth
            self.geometry = style.preset == .squircle ? .squircle : .rhombus
        case .dot:
            self.bandWidth = 0
            self.geometry = .dot
        case .spotlight:
            self.bandWidth = 0
            self.geometry = .spotlight
        }
        self.cornerRadiusFactor = geometry == .squircle || geometry == .rhombus
            ? Self.squircleCornerFactor : nil
        self.edgeWidth = geometry == .ring || geometry == .squircle || geometry == .rhombus
            ? Self.edgeWidthPoints : 0
        if style.glowIntensity > 0 {
            let intensity = style.glowIntensity * style.opacity
            self.glowStops = [
                (location: 0, alpha: 0.26 * intensity),
                (location: 0.55, alpha: 0.10 * intensity),
                (location: 1, alpha: 0),
            ]
        } else {
            self.glowStops = []
        }
    }

    /// Tuples do not conform to `Equatable`, so equality is written by hand
    /// instead of relying on memberwise synthesis.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ink == rhs.ink
            && lhs.radius == rhs.radius
            && lhs.bandWidth == rhs.bandWidth
            && lhs.edgeWidth == rhs.edgeWidth
            && lhs.bandFillAlpha == rhs.bandFillAlpha
            && lhs.edgeAlpha == rhs.edgeAlpha
            && lhs.dashed == rhs.dashed
            && lhs.cornerRadiusFactor == rhs.cornerRadiusFactor
            && lhs.glowExtent == rhs.glowExtent
            && lhs.glowMargin == rhs.glowMargin
            && lhs.geometry == rhs.geometry
            && lhs.glowStops.count == rhs.glowStops.count
            && zip(lhs.glowStops, rhs.glowStops).allSatisfy {
                $0.location == $1.location && $0.alpha == $1.alpha
            }
    }
}
