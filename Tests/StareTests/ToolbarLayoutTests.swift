import SwiftUI
import XCTest
@testable import Stare
import StareCore

/// T6/S5: the drawing toolbar renders exactly the stored item list — tools
/// and real separators, in order — while the capture editor keeps its fixed
/// family-grouped palette and off-bar tools stay shortcut-armed. The tests
/// run on the detached `EditorState()` the selftest harness uses, and read
/// the section the real `ToolbarView` maps over (`toolSection`), so a
/// regression in the view's resolution shows here, not just in the pure
/// model.
@MainActor
final class ToolbarLayoutTests: XCTestCase {

    // MARK: - Default bar

    func testFreshStateRendersTodaysItems() {
        // A detached state ships the standard layout: every tool in the
        // documented order with a separator between the families.
        let view = ToolbarView(state: EditorState(), onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        XCTAssertEqual(view.toolSection, ToolbarToolLayout.standard.items)
        XCTAssertTrue(view.toolSection.contains(.separator))
    }

    // MARK: - The bar follows the layout

    func testTheBarSectionIsExactlyTheLayoutsItemsIncludingSeparators() {
        let state = EditorState()
        let layout = ToolbarToolLayout(items: [
            .tool(.pen), .separator, .tool(.eraser), .separator, .tool(.laser),
        ])
        state.toolbarTools = layout

        let view = ToolbarView(state: state, onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        // The bar draws the stored list exactly: nothing re-grouped, nothing
        // reordered, separators left exactly where the user placed them.
        XCTAssertEqual(view.toolSection, layout.items)
        XCTAssertEqual(Set(view.toolSection), Set(layout.items))
    }

    func testTheOrganiserPreviewRendersTheDraftItemsDirectly() {
        // The Settings organiser's live preview passes the draft item list;
        // that must win over the state's own stored layout, so what the user
        // arranges is what the preview shows.
        let state = EditorState()
        state.toolbarTools = ToolbarToolLayout.standard

        let draft = ToolbarToolLayout(items: [
            .tool(.eraser), .separator, .tool(.pen),
        ])
        let view = ToolbarView(
            state: state,
            onUndo: {}, onRedo: {}, onClear: {}, onDone: {},
            toolItems: draft.items
        )
        XCTAssertEqual(view.toolSection, draft.items)
        XCTAssertNotEqual(view.toolSection, state.toolbarTools.items)
    }

    // MARK: - The `⁞` and what waits behind it (S1/S2/S6)

    func testAFreshBarKeepsTheDrawingToolsAndPutsTheExtrasBehindTheOverflow() {
        let view = ToolbarView(state: EditorState(), onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        // The short bar is what a fresh install draws…
        XCTAssertEqual(view.toolSection.compactMap(\.tool), ToolbarToolLayout.standardVisibleTools)
        // …and the extras are one click away instead of gone.
        XCTAssertTrue(view.showsOverflow)
        XCTAssertEqual(view.hiddenTools, ToolbarToolLayout.standard.pool)
        XCTAssertFalse(view.toolSection.compactMap(\.tool).contains(.spotlight))
    }

    func testABarThatHoldsEveryToolDrawsNoOverflowAtAll() {
        let state = EditorState()
        state.toolbarTools = ToolbarToolLayout(items: Tool.toolbarGroups.flatMap { $0 }.map(ToolbarLayoutItem.tool))
        XCTAssertTrue(state.toolbarTools.pool.isEmpty)

        let view = ToolbarView(state: state, onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        // Nothing waits behind it, so there is no `⁞`: a bar holding every
        // tool looks exactly as it always did.
        XCTAssertFalse(view.showsOverflow)
        XCTAssertTrue(view.hiddenTools.isEmpty)
    }

    func testTheOrganiserPreviewReadsTheDraftsPoolNotTheSavedOne() {
        let state = EditorState()
        state.toolbarTools = ToolbarToolLayout.standard
        // The draft pools everything but the pen: twelve tools wait behind
        // the `⁞`, not the saved layout's five.
        let draft = ToolbarToolLayout(items: [.tool(.pen)], pool: [])
        let view = ToolbarView(
            state: state,
            onUndo: {}, onRedo: {}, onClear: {}, onDone: {},
            toolItems: draft.items,
            toolPool: draft.hiddenTools
        )
        XCTAssertEqual(view.toolSection, draft.items)
        XCTAssertEqual(view.hiddenTools, draft.hiddenTools)
        XCTAssertNotEqual(view.hiddenTools, state.toolbarTools.hiddenTools)
    }

    func testTheCaptureEditorDrawsNoOverflow() {
        let editor = ToolbarView(
            state: EditorState(),
            onUndo: {}, onRedo: {}, onClear: {}, onDone: {},
            toolGroups: Tool.captureEditorGroups
        )
        // The editor's palette is already narrowed to what works over a still
        // image: it never grows a `⁞`.
        XCTAssertFalse(editor.showsOverflow)
        XCTAssertTrue(editor.hiddenTools.isEmpty)
    }

    func testAToolBehindTheOverflowStillAnswersItsKeyAndTheControlSaysSo() {
        let state = EditorState()
        let hidden = state.toolbarTools.hiddenTools
        // S6: the spotlight sits behind the `⁞` and its key still arms it.
        XCTAssertTrue(hidden.contains(.spotlight))
        XCTAssertEqual(state.shortcutRouter.resolve(Character("d")), .tool(.spotlight))
        state.select(.spotlight)
        XCTAssertTrue(state.isToolMarked(.spotlight))
        // …and the collapsed control says which tool that is, instead of dots.
        XCTAssertEqual(
            ToolbarOverflowSpec.symbolName(selected: state.tool, hidden: hidden),
            Tool.spotlight.symbolName
        )
    }

    // MARK: - Fixed surfaces stay fixed

    func testTheCaptureEditorKeepsItsFixedPalette() {
        let state = EditorState()
        state.toolbarTools = ToolbarToolLayout.standard

        let editor = ToolbarView(
            state: state,
            onUndo: {}, onRedo: {}, onClear: {}, onDone: {},
            toolGroups: Tool.captureEditorGroups
        )
        XCTAssertEqual(editor.fixedToolGroups, Tool.captureEditorGroups)
        // The fixed palette is the grouped one, not the item list: the bar
        // draws family dividers there because the editor's surface never
        // takes the persisted layout.
        XCTAssertTrue(editor.fixedToolGroups != nil)
    }

    // MARK: - A shortcut is not the bar

    func testAOffBarToolStaysShortcutArmedAndMarkable() {
        let state = EditorState()
        state.toolbarTools = ToolbarToolLayout(items: [.tool(.pen)])

        // The bar does not draw the laser…
        let view = ToolbarView(state: state, onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        XCTAssertFalse(view.toolSection.compactMap(\.tool).contains(.laser))
        // …but its shortcut routes exactly as before,
        XCTAssertEqual(state.shortcutRouter.resolve(Character("f")), .tool(.laser))
        // and if the laser is the armed tool (for example armed by that
        // shortcut or by an undo) the marking machinery answers as usual, so
        // the bar marks it the moment it comes back.
        state.select(.laser)
        XCTAssertTrue(state.isToolMarked(.laser))
    }
}
