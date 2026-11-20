import Combine
import Foundation
import StareCore

/// Editor state shared by the overlay views and the floating toolbar: the
/// current tool, the current ink and whether the armed frame is drawn.
final class EditorState: ObservableObject {
    private static let frameKey = "showArmedFrame"

    @Published var tool: Tool = .pen
    @Published var ink: Ink = .red
    @Published var showArmedFrame: Bool {
        didSet { UserDefaults.standard.set(showArmedFrame, forKey: Self.frameKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.frameKey) == nil {
            defaults.set(true, forKey: Self.frameKey)
        }
        showArmedFrame = defaults.bool(forKey: Self.frameKey)
    }
}
