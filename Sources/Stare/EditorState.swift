import Combine
import Foundation
import StareCore

/// Editor state shared by the overlay views and the floating toolbar: the
/// current tool, the current ink and whether the armed frame is drawn.
final class EditorState: ObservableObject {
    private static let frameKey = "showArmedFrame"
    private static let cursorFrameKey = "showCursorFrame"
    private static let laserLifetimeKey = "laserLifetime"

    @Published var tool: Tool = .pen {
        didSet { Diag.log("tool=\(tool.rawValue)") }
    }
    @Published var ink: Ink = .red
    @Published var showArmedFrame: Bool {
        didSet { UserDefaults.standard.set(showArmedFrame, forKey: Self.frameKey) }
    }
    @Published var showCursorFrame: Bool {
        didSet { UserDefaults.standard.set(showCursorFrame, forKey: Self.cursorFrameKey) }
    }
    /// Presentation mode: the layer is visible but passes clicks through, so the
    /// pointer highlight works while the user keeps working in another app.
    @Published var pointerActive: Bool = false
    /// Seconds a laser mark stays on screen before fading out.
    @Published var laserLifetime: TimeInterval {
        didSet { UserDefaults.standard.set(laserLifetime, forKey: Self.laserLifetimeKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.frameKey) == nil {
            defaults.set(true, forKey: Self.frameKey)
        }
        if defaults.object(forKey: Self.cursorFrameKey) == nil {
            defaults.set(true, forKey: Self.cursorFrameKey)
        }
        showArmedFrame = defaults.bool(forKey: Self.frameKey)
        if defaults.object(forKey: Self.laserLifetimeKey) == nil {
            defaults.set(2.5, forKey: Self.laserLifetimeKey)
        }
        showCursorFrame = defaults.bool(forKey: Self.cursorFrameKey)
        laserLifetime = defaults.double(forKey: Self.laserLifetimeKey)
    }
}
