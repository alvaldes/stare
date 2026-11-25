import XCTest

@testable import Stare
import StareCore

/// T3/S4 + T4/S5: the Settings pool card reads as the bar's hidden section —
/// the tools behind the bar's `⁞`, one ordered strip, never a graveyard — and
/// the preview bar is the draft's whole bar: the `⁞` included, drawing the
/// draft's hidden tools, not the saved layout's. The card's reading is pinned
/// through `BarPane`'s own constants and the preview through the very
/// `ToolbarView` the stage renders, so nothing here inspects SwiftUI
/// internals.
@MainActor
final class SettingsHiddenSectionTests: XCTestCase {

    /// An in-memory `PreferenceStore`, so the tests never touch the user's
    /// real preferences — the same isolation the organiser tests use.
    private final class InMemoryPreferenceStore: PreferenceStore {
        private var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    // MARK: The card says what the section is (T3/S4)

    /// S4: the pool is the bar's hidden section, not a "removed" bucket.
    /// The card's title carries the bar's own `⁞`, its symbol is the same
    /// glyph, and its help says what lives there and the two drags that move
    /// a tool between the sections. Pinned as the exact constants `poolCard`
    /// renders.
    func testThePoolCardReadsAsTheBarsHiddenSection() {
        XCTAssertEqual(BarPane.poolCardTitle, "More tools")
        XCTAssertEqual(BarPane.poolCardSymbol, ToolbarOverflowSpec.glyph)
        XCTAssertEqual(BarPane.poolCardHelp, """
        These tools are hidden: the bar keeps them, one click away while drawing, \
        and they keep their shortcuts. Drag one onto the bar to bring it back, and \
        drag a bar tool onto a spot here to hide it. A tool is never nowhere. A \
        placed separator comes back off the bar through any spot here, and the \
        bar's first tool cannot leave — the preview dims it. Right-click a separator \
        on the bar to remove it.
        """)
    }

    // MARK: The preview draws the draft's hidden tools (T4/S5)

    /// S5: the preview bar is the same bar the overlay draws — with the
    /// shipped layout it offers the `⁞` and its hidden tools are the shipped
    /// pool. And the pool it draws is the DRAFT's: the fixture never syncs
    /// the preview state's mirror (that happens on appear in the real pane),
    /// so a draft that differs from the shipped default proves the stage
    /// pins `model.toolbarTools.hiddenTools` as a value rather than leaving
    /// the view to the saved state's.
    func testThePreviewBarShowsTheShippedOverflowAndTheDraftsPool() {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.toolbarTools = .standard
        let pane = BarPane(model: model, cardsWidth: 600)

        let bar = pane.previewToolbar
        XCTAssertTrue(bar.showsOverflow, "S5: with the shipped layout the preview bar offers the ⁞")
        XCTAssertEqual(bar.hiddenTools, ToolbarToolLayout.standard.hiddenTools)
        XCTAssertFalse(bar.hiddenTools.isEmpty, "S3: the shipped bar keeps extras behind the ⁞")

        // The draft's pool, not the saved state's: the preview state's mirror
        // still holds the shipped `.standard` here, so the reported pool can
        // only come from the value the stage pins into the view.
        model.toolbarTools = ToolbarToolLayout(items: [.tool(.pen)], pool: [.laser, .blur])
        let redrafted = pane.previewToolbar
        XCTAssertEqual(redrafted.hiddenTools, model.toolbarTools.hiddenTools, "the preview draws the draft's pool")
        XCTAssertNotEqual(
            redrafted.hiddenTools, ToolbarToolLayout.standard.hiddenTools,
            "the draft must differ from the state's mirror for this pin to bite")
        XCTAssertEqual(redrafted.toolSection, [.tool(.pen)], "the draft's own item list, too")
    }
}
