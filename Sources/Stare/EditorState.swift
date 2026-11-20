import Combine
import Foundation
import StareCore

/// Editor state shared by the overlay views and the floating toolbar: the
/// current tool, the current ink and whether the armed frame is drawn.
final class EditorState: ObservableObject {
    private static let frameKey = "showArmedFrame"
    private static let cursorFrameKey = "showCursorFrame"

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

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.frameKey) == nil {
            defaults.set(true, forKey: Self.frameKey)
        }
        if defaults.object(forKey: Self.cursorFrameKey) == nil {
            defaults.set(false, forKey: Self.cursorFrameKey)
        }
        showArmedFrame = defaults.bool(forKey: Self.frameKey)
        showCursorFrame = defaults.bool(forKey: Self.cursorFrameKey)
    }
}
