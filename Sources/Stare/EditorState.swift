import Combine
import Foundation
import StareCore

/// Editor state shared by the overlay views and the floating toolbar: the
/// current tool, the current ink and whether the armed frame is drawn.
final class EditorState: ObservableObject {
    private static let frameKey = "showArmedFrame"
    private static let laserLifetimeKey = "laserLifetime"
    private static let pointerSizeKey = "pointerSize.v3"
    private static let overlayScopeKey = "overlayScope"
    private static let palettePlacementKey = "palettePlacement"
    private static let pointerShapeKey = "pointerShape"
    private static let pointerGlowKey = "pointerGlow"
    private static let pointerFadeKey = "pointerFadeWhenIdle"
    private static let boardBackgroundKey = "boardPageBackground"
    private static let boardScopeKey = "boardScope"
    private static let boardBorderKey = "boardShowBorder"

    @Published var tool: Tool = .pen {
        didSet { Diag.log("tool=\(tool.rawValue)") }
    }
    @Published var ink: Ink = .red
    @Published var showArmedFrame: Bool {
        didSet { UserDefaults.standard.set(showArmedFrame, forKey: Self.frameKey) }
    }
    /// Presentation mode: the layer is visible but passes clicks through, so the
    /// pointer highlight works while the user keeps working in another app.
    @Published var pointerActive: Bool = false
    /// "all" draws on every display, "active" only on the one under the pointer.
    @Published var overlayScope: String {
        didSet { UserDefaults.standard.set(overlayScope, forKey: Self.overlayScopeKey) }
    }
    /// Where the palette opens: "cursor", "frontWindow" or "fixed".
    @Published var palettePlacement: String {
        didSet { UserDefaults.standard.set(palettePlacement, forKey: Self.palettePlacementKey) }
    }
    /// Diameter of the pointer highlight ring, in points.
    @Published var pointerSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(pointerSize), forKey: Self.pointerSizeKey) }
    }
    /// `circle` or `squircle`, matching the shapes the reference app offers.
    @Published var pointerShape: String {
        didSet { UserDefaults.standard.set(pointerShape, forKey: Self.pointerShapeKey) }
    }
    @Published var pointerGlow: Bool {
        didSet { UserDefaults.standard.set(pointerGlow, forKey: Self.pointerGlowKey) }
    }
    /// Fade the highlight down when the pointer stops moving.
    @Published var pointerFadeWhenIdle: Bool {
        didSet { UserDefaults.standard.set(pointerFadeWhenIdle, forKey: Self.pointerFadeKey) }
    }
    /// Seconds a laser mark stays on screen before fading out.
    @Published var laserLifetime: TimeInterval {
        didSet { UserDefaults.standard.set(laserLifetime, forKey: Self.laserLifetimeKey) }
    }
    /// The default background of a whiteboard page's first page: "system"
    /// follows the appearance (light → white, dark → black), "white" and
    /// "black" fix it. New pages inherit the page they came from; ⌘B still
    /// flips the current page.
    @Published var boardPageBackground: String {
        didSet { UserDefaults.standard.set(boardPageBackground, forKey: Self.boardBackgroundKey) }
    }
    /// Where the whiteboard opens: "all" covers every display, "active" only
    /// the one under the pointer — the same rule the drawing overlay uses.
    @Published var boardScope: String {
        didSet { UserDefaults.standard.set(boardScope, forKey: Self.boardScopeKey) }
    }
    /// Whether the whiteboard draws its border. The board's own preference,
    /// decided independently of the drawing frame (`showArmedFrame`).
    @Published var boardShowBorder: Bool {
        didSet { UserDefaults.standard.set(boardShowBorder, forKey: Self.boardBorderKey) }
    }
    /// Whiteboard pages indicator for the toolbar: nil hides the page controls.
    @Published var whiteboardPage: (current: Int, total: Int)? = nil

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.frameKey) == nil {
            defaults.set(true, forKey: Self.frameKey)
        }
        showArmedFrame = defaults.bool(forKey: Self.frameKey)
        if defaults.object(forKey: Self.laserLifetimeKey) == nil {
            defaults.set(2.5, forKey: Self.laserLifetimeKey)
        }
        if defaults.object(forKey: Self.pointerSizeKey) == nil {
            defaults.set(72.0, forKey: Self.pointerSizeKey)
        }
        for key in [Self.pointerShapeKey, Self.pointerGlowKey, Self.pointerFadeKey] where defaults.object(forKey: key) == nil {
            defaults.set(key == Self.pointerShapeKey ? "squircle" : true, forKey: key)
        }
        if defaults.object(forKey: Self.overlayScopeKey) == nil {
            defaults.set("all", forKey: Self.overlayScopeKey)
        }
        if defaults.object(forKey: Self.palettePlacementKey) == nil {
            defaults.set("cursor", forKey: Self.palettePlacementKey)
        }
        laserLifetime = defaults.double(forKey: Self.laserLifetimeKey)
        pointerSize = CGFloat(defaults.double(forKey: Self.pointerSizeKey))
        pointerShape = defaults.string(forKey: Self.pointerShapeKey) ?? "squircle"
        pointerGlow = defaults.bool(forKey: Self.pointerGlowKey)
        pointerFadeWhenIdle = defaults.bool(forKey: Self.pointerFadeKey)
        overlayScope = defaults.string(forKey: Self.overlayScopeKey) ?? "all"
        palettePlacement = defaults.string(forKey: Self.palettePlacementKey) ?? "cursor"
        if defaults.object(forKey: Self.boardBackgroundKey) == nil {
            defaults.set("system", forKey: Self.boardBackgroundKey)
        }
        if defaults.object(forKey: Self.boardScopeKey) == nil {
            defaults.set("all", forKey: Self.boardScopeKey)
        }
        if defaults.object(forKey: Self.boardBorderKey) == nil {
            defaults.set(true, forKey: Self.boardBorderKey)
        }
        boardPageBackground = defaults.string(forKey: Self.boardBackgroundKey) ?? "system"
        boardScope = defaults.string(forKey: Self.boardScopeKey) ?? "all"
        boardShowBorder = defaults.bool(forKey: Self.boardBorderKey)
    }

    /// The board's page-colour choice, parsed from the stored preference. An
    /// unknown value falls back to following the system, the documented
    /// default.
    var boardBackgroundChoice: BoardBackground {
        BoardBackground(rawValue: boardPageBackground) ?? .system
    }
}
