import SwiftUI
import XCTest
@testable import Stare
import StareCore

/// T8/S10: the drawing toolbar renders exactly the persisted tool layout —
/// the stored order with the hidden tools skipped, no gaps, no phantom items,
/// nothing duplicated — while the capture editor keeps its fixed palette and
/// a hidden tool stays shortcut-armed. The tests run on the detached
/// `EditorState()` the selftest harness uses, and read the section the real
/// `ToolbarView` maps over (`toolSection`), so a regression in the view's
/// resolution shows here, not just in the pure model.
@MainActor
final class ToolbarLayoutTests: XCTestCase {

    private var defaultOrder: [Tool] { ToolbarToolLayout.defaultOrder }

    // MARK: - Default bar

    func testFreshStateRendersTodaysGroups() {
        // A detached state ships the standard layout, whose groups are
        // exactly the groups the bar has always drawn.
        let view = ToolbarView(state: EditorState(), onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        XCTAssertEqual(view.toolSection, Tool.toolbarGroups)
    }

    // MARK: - The bar follows the layout

    func testTheBarSectionIsThePersistedLayoutsVisibleGroups() {
        let state = EditorState()
        state.toolbarTools = ToolbarToolLayout.standard
            .setting(.number, isVisible: false)
            .moving(.eraser, by: -1)

        let view = ToolbarView(state: state, onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        XCTAssertEqual(view.toolSection, state.toolbarTools.visibleGroups)
        // No gaps, no phantom items, no duplicates: the flat section is the
        // stored order minus the hidden tool, and each tool appears once.
        let flat = view.toolSection.flatMap { $0 }
        XCTAssertEqual(flat, state.toolbarTools.visibleTools)
        XCTAssertEqual(Set(flat).count, flat.count)
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
        XCTAssertEqual(editor.toolSection, Tool.captureEditorGroups)
    }

    // MARK: - A shortcut is not the bar

    func testAHidingToolStaysShortcutArmedAndMarkable() {
        let state = EditorState()
        state.toolbarTools = ToolbarToolLayout.standard.setting(.laser, isVisible: false)

        // The bar does not draw the laser…
        let view = ToolbarView(state: state, onUndo: {}, onRedo: {}, onClear: {}, onDone: {})
        XCTAssertFalse(view.toolSection.flatMap { $0 }.contains(.laser))
        // …but its shortcut routes exactly as before,
        XCTAssertEqual(state.shortcutRouter.resolve(Character("f")), .tool(.laser))
        // and if the laser is the armed tool (for example armed by that
        // shortcut or by an undo) the marking machinery answers as usual, so
        // the bar marks it the moment it is shown again.
        state.select(.laser)
        XCTAssertTrue(state.isToolMarked(.laser))
    }
}
