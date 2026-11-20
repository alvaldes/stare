import Combine
import Foundation
import StareCore

/// Editor state shared by the overlay views and the floating toolbar: the
/// current tool, the current ink and whether a drawing session is running.
final class EditorState: ObservableObject {
    @Published var tool: Tool = .pen
    @Published var ink: Ink = .red
}
