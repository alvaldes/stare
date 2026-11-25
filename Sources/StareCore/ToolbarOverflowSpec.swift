import Foundation

/// The bar's overflow control (S1/S6): the `⁞` that holds the tools which are
/// not the main ones. The values are pure so the toolbar view stays a view and
/// the tests can pin the glyph, the axis, and how the control reports the
/// active tool without inspecting SwiftUI internals.
public enum ToolbarOverflowSpec {
    /// The collapsed control's glyph: three dots, one per line.
    public static let glyph = "ellipsis"

    /// The dots run along the bar's own axis — a vertical bar stacks them, a
    /// horizontal one lays them out — so the same symbol turns.
    public static func rotationDegrees(isVertical: Bool) -> Double {
        isVertical ? 90 : 0
    }

    /// S6: the bar always says which tool is active, even when that tool lives
    /// behind the `⁞`. The control takes the active tool's own symbol then, and
    /// the plain dots whenever the active tool is on the bar (where it marks
    /// itself) or nothing waits behind it.
    public static func symbolName(selected: Tool?, hidden: [Tool]) -> String {
        guard let selected, hidden.contains(selected) else { return glyph }
        return selected.symbolName
    }

    /// What the control's tooltip says: the tool that is active and hiding
    /// here, and every tool waiting behind it. Spelled out in words — the
    /// three dots are a mark on the bar, not something to read in a sentence.
    public static func help(selected: Tool?, hidden: [Tool]) -> String {
        guard !hidden.isEmpty else { return "No hidden tools" }
        let names = hidden.map(\.displayName).joined(separator: ", ")
        guard let selected, hidden.contains(selected) else {
            return "More tools: \(names)"
        }
        return "\(selected.displayName) is active and hidden · More tools: \(names)"
    }
}
