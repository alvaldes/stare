import Combine
import Foundation
import StareCore

/// Editor state shared by the overlay views and the floating toolbar: the
/// current tool, the current ink and whether the armed frame is drawn.
final class EditorState: ObservableObject {
    private static let frameKey = "showArmedFrame"
    private static let laserLifetimeKey = "laserLifetime"
    private static let pointerSizeKey = "pointerSize.v3"
    private static let pointerShapeKey = "pointerShape"
    private static let pointerGlowKey = "pointerGlow"
    private static let pointerFadeKey = "pointerFadeWhenIdle"

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
        laserLifetime = defaults.double(forKey: Self.laserLifetimeKey)
        pointerSize = CGFloat(defaults.double(forKey: Self.pointerSizeKey))
        pointerShape = defaults.string(forKey: Self.pointerShapeKey) ?? "squircle"
        pointerGlow = defaults.bool(forKey: Self.pointerGlowKey)
        pointerFadeWhenIdle = defaults.bool(forKey: Self.pointerFadeKey)
    }
}
