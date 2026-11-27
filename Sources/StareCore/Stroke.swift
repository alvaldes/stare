import CoreGraphics
import Foundation

/// The head an arrow mark carries. Pure model: the open head is the shipped
/// barb pair, the filled head inks the triangle the barbs span. The style is
/// a property of the mark (S15), so an arrow keeps the head it was drawn
/// with through undo, redo and the editor.
public enum ArrowHeadStyle: String, CaseIterable, Sendable {
    /// The shipped arrow head: two straight barbs from the tip.
    case open
    /// A solid triangle spanning the two barbs.
    case filled

    /// The next style when the key cycles the choice.
    public var next: ArrowHeadStyle {
        switch self {
        case .open: .filled
        case .filled: .open
        }
    }
}

/// How a blur mark redacts what is under it (S13). The blur audit
/// (odd/tasks/capture-extras.md L4) measured the gaussian blur safe at the
/// shipped parameters, so `.blur` stays the default it always was, and the
/// randomized pixelate is the plain second option beside it: same tool, same
/// geometry, no new mark kind.
public enum RedactionStyle: String, CaseIterable, Sendable, Codable {
    /// The gaussian diffusion the mark always painted; today's behaviour.
    case blur
    /// Pixelation with per-block randomized sampling (`PixelateEffect`), whose
    /// block derives from the mark's rectangle — never a user knob — and whose
    /// grid offsets move per `Stroke.redactionSeed`.
    case randomizedPixelate
}

/// S2/S3 with S4's revision: the shape the spotlight draws. One tool — the
/// shape is a property of the mark itself — the same disposition the fill and
/// the arrow head already have (S15) — so a saved drawing restores the shape
/// it was drawn with, and the armed choice rides `EditorState` the way
/// `arrowHeadStyle` does into every minting site. The control is a context
/// menu on the spotlight's own button offering exactly the two shapes the
/// owner wants (`menuChoices`), never a second tool and never a preference.
/// The plain rectangle is withdrawn from that offer but kept as data: its raw
/// value stays decodable and its silhouette stays renderable, so a mark drawn
/// with it keeps looking like that.
public enum SpotlightShape: String, CaseIterable, Sendable, Codable {
    case rectangle
    case ellipse
    case roundedRectangle

    /// The shipped corner radius of the rounded-rectangle shape, in points —
    /// the shallow dish the third shape reads by (`PathBuilder` clamps it
    /// into the region's half sides so a small region never inverts).
    public static let roundedRectRadius: CGFloat = 16

    /// The shapes the control offers. One, since the owner's call: "puedo
    /// quedarme solo con el rect porque el elipse ya no me gusta". `.ellipse`
    /// and `.rectangle` are deliberately absent — not options any more, but
    /// still `allCases` members every legacy mark may carry, and a control
    /// with a single choice offers no choice, so the button carries no menu.
    public static let menuChoices: [SpotlightShape] = [.roundedRectangle]

    /// The name the spotlight button's help and context menu print for a
    /// shape.
    public var displayName: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .roundedRectangle: "Rounded rectangle"
        }
    }
}

/// One mark on the screen. Points live in a top-left-origin, display-local space
/// measured in points, which is what the overlay view and the capture both use.
public struct Stroke: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let tool: Tool
    public let ink: Ink
    public var points: [CGPoint]
    /// 1-based counter for `.number` marks, `nil` for every other tool.
    public var stepNumber: Int?
    /// Typed content of a `.text` mark.
    public var text: String?
    /// Size the text was measured at, so bounds and hit testing agree with what
    /// is on screen without re-measuring on every frame.
    public var textSize: CGSize?
    /// When a transient mark was made, used to fade and prune it.
    public var createdAt: Date?
    /// Diameter a numbered badge is drawn at, in points. Nil means the default
    /// `PathBuilder.badgeDiameter`: the mark stores the size it was created at,
    /// so scaling the mark scales the badge and its digit with it.
    public var badgeSize: CGFloat?
    /// Rotation in radians about the anchor (the centre of the unrotated
    /// bounds). Positive turns clockwise on screen. It is metadata, never baked
    /// into `points`: a rotated rectangle must stay a rectangle.
    public var rotation: CGFloat
    /// S15: whether this mark draws filled instead of outline only. A property
    /// of the mark: a shape keeps whatever it was drawn with through undo,
    /// redo and the editor. Only ever true on `.rectangle` and `.ellipse`.
    public var isFilled: Bool = false
    /// S15: the head this arrow mark draws. A property of the mark like the
    /// fill; only ever set on `.arrow`.
    public var arrowHead: ArrowHeadStyle = .open
    /// How the mark redacts what is under it (S13): the gaussian blur the audit
    /// (odd/tasks/capture-extras.md L4) measured safe, or the randomized
    /// pixelate beside it. A plain defaulted field, exactly the peer's
    /// `isFilled`/`arrowHead` precedent: a document that never named the field
    /// decodes as blur, so every mark drawn before it existed renders byte
    /// -identically to what it always rendered.
    public var redactionStyle: RedactionStyle = .blur
    /// S2/S3: the shape this spotlight mark draws — the dragged rectangle,
    /// its inscribed ellipse (today's look, the default every legacy mark
    /// decodes to) or a rounded rectangle. A property of the mark like the
    /// fill and the head, appended last and persisted by the same lenient
    /// discipline `redactionStyle` keeps. S4 no longer offers the plain
    /// rectangle, but a mark drawn with it before the withdrawal keeps
    /// decoding and rendering as the rectangle it was drawn as.
    public var spotlightShape: SpotlightShape = .roundedRectangle

    public init(
        id: UUID = UUID(),
        tool: Tool,
        ink: Ink,
        points: [CGPoint],
        stepNumber: Int? = nil,
        text: String? = nil,
        textSize: CGSize? = nil,
        createdAt: Date? = nil,
        badgeSize: CGFloat? = nil,
        rotation: CGFloat = 0,
        fill: Bool = false,
        arrowHead: ArrowHeadStyle = .open,
        redactionStyle: RedactionStyle = .blur,
        spotlightShape: SpotlightShape = .ellipse
    ) {
        self.id = id
        self.tool = tool
        self.ink = ink
        self.points = points
        self.stepNumber = stepNumber
        self.text = text
        self.textSize = textSize
        self.createdAt = createdAt
        self.badgeSize = badgeSize
        self.rotation = rotation
        self.isFilled = fill
        self.arrowHead = arrowHead
        self.redactionStyle = redactionStyle
        self.spotlightShape = spotlightShape
    }

    /// The mark's own badge diameter, falling back to the default.
    public var badgeDiameter: CGFloat {
        badgeSize ?? PathBuilder.badgeDiameter
    }

    /// The seed the randomized pixelate draws its per-block sampling offsets
    /// from: mixed from the mark's own identity. The identifier is minted the
    /// moment the mark is created — the honest answer for a redaction
    /// primitive, because the branch review's `R1-pixelate-predictable-offsets`
    /// flagged a public constant seed as the grid definition an attacker reads
    /// out of the shipped source. Deriving from the identifier also keeps the
    /// same mark on the same grid everywhere: the live preview, the saved
    /// capture, the editor's zoom and a restored drawing all name the same
    /// mark id, so all four agree byte for byte, and two marks over the same
    /// content never align.
    public var redactionSeed: UInt64 {
        // 128 identity bytes → one stable word; explicit byte assembly keeps
        // it independent of endianness or tuple memory alignment.
        let identity = Array(withUnsafeBytes(of: id.uuid) { Array($0) })
        func word(_ start: Int) -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<8 {
                value |= UInt64(identity[start + index]) << UInt64(8 * index)
            }
            return value
        }
        var state = word(0) ^ word(8) &* 0x9E37_79B9_7F4A_7C15
        // One SplitMix64 step, so even a low-entropy identity still spreads.
        state = state &+ 0x9E37_79B9_7F4A_7C15
        state = (state ^ state >> 30) &* 0xBF58_476D_1CE4_E5B9
        state = (state ^ state >> 27) &* 0x94D0_49BB_1331_11EB
        return state ^ state >> 31
    }

    /// Ratio of the mark's own badge diameter to the default one, so a resized
    /// badge draws its digit at the matching size.
    public var badgeScale: CGFloat {
        badgeDiameter / PathBuilder.badgeDiameter
    }

    /// Stroke width in points, excluding badges.
    public var lineWidth: CGFloat {
        switch tool {
        case .highlighter: 18
        case .number: 2
        case .text, .select, .eraser, .blur, .spotlight: 0
        case .pen, .arrow, .line, .rectangle, .ellipse, .laser: 3
        }
    }

    /// Highlighter is translucent so text underneath stays readable.
    public var opacity: CGFloat {
        tool == .highlighter ? 0.35 : 1
    }

    public var bounds: CGRect {
        PathBuilder.bounds(for: self)
    }

    /// The pivot for rotation: the centre of the unrotated geometry.
    public var anchor: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// Map that rotates a point about `anchor` by `angle` radians. Shared by
    /// rendering, hit testing and the selection handles so all three agree.
    public static func rotationTransform(around anchor: CGPoint, by angle: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
    }

    /// Axis-aligned bounds of the mark once rotated about its anchor. Larger
    /// than `bounds` whenever the rotation spills over the box, which is what
    /// culling needs.
    public var displayBounds: CGRect {
        guard rotation != 0 else { return bounds }
        let transform = Stroke.rotationTransform(around: anchor, by: rotation)
        let corners = [
            bounds.origin,
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
        ]
        var result = CGRect.null
        for corner in corners {
            result = result.union(CGRect(origin: corner.applying(transform), size: .zero))
        }
        return result
    }

    public var startPoint: CGPoint? { points.first }
    public var endPoint: CGPoint? { points.last }

    /// Opacity at a given moment: laser marks fade out over their lifetime.
    public func opacity(at now: Date, laserLifetime: TimeInterval) -> CGFloat {
        guard tool.isTransient, let createdAt else { return opacity }
        let age = now.timeIntervalSince(createdAt)
        guard age < laserLifetime else { return 0 }
        return max(0, 1 - age / laserLifetime)
    }

    /// Whether a pointer at `point` touches this mark, used by the eraser.
    /// A rotated mark answers in its own space: the query point is rotated back
    /// about the anchor first, so the mark is hit where it looks.
    public func hitTest(_ point: CGPoint, radius: CGFloat) -> Bool {
        let local: CGPoint
        if rotation == 0 {
            local = point
        } else {
            local = point.applying(Stroke.rotationTransform(around: anchor, by: -rotation))
        }
        switch tool {
        case .select:
            return false
        case .number:
            guard let center = points.first else { return false }
            let dx = local.x - center.x
            let dy = local.y - center.y
            // The badge is drawn at the mark's own stored size, so a scaled
            // badge answers at its scaled radius.
            let reach = badgeDiameter / 2 + radius
            return (dx * dx + dy * dy) <= reach * reach
        case .text:
            return bounds.insetBy(dx: -radius, dy: -radius).contains(local)
        case .eraser:
            return false
        case .blur, .spotlight:
            // The blur and the spotlight are areas, not outlines: a point
            // inside the rectangle spanned by their endpoints touches the
            // mark.
            guard let first = points.first, let last = points.last else { return false }
            return PathBuilder.normalizedRect(from: first, to: last).contains(local)
        case .pen, .highlighter, .arrow, .line, .rectangle, .ellipse, .laser:
            let outline = PathBuilder.path(for: self).copy(
                strokingWithWidth: max(lineWidth, 2) + radius * 2,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
            return outline.contains(local, using: .winding)
        }
    }

    /// Whether the edit cursor at `point` grabs this mark. Closed shapes and
    /// area marks answer by their rotated box — the interior of a rectangle is
    /// editable, not only its outline — while freehand ink stays outline-only,
    /// so the empty middle of its bounding box does not grab it.
    public func isSelectedByCursor(at point: CGPoint, radius: CGFloat) -> Bool {
        if hitTest(point, radius: radius) { return true }
        switch tool {
        case .rectangle, .ellipse, .blur, .spotlight, .text, .number:
            return displayBounds.insetBy(dx: -radius, dy: -radius).contains(point)
        case .select, .eraser, .pen, .highlighter, .arrow, .line, .laser:
            return false
        }
    }
}
