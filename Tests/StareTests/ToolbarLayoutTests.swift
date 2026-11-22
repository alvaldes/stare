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
