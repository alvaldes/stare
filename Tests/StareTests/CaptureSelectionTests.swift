import XCTest
@testable import Stare
import StareCore

/// S6: in the capture editor the crop participates in the same selected-tool
/// state the drawing tools use — one armed item at a time, not two. Picking
/// crop unmarks the active tool, picking any tool unmarks crop, and a fresh
/// state marks exactly one item. The tests run on the detached `EditorState()`
/// the capture editor itself uses.
@MainActor
final class CaptureSelectionTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateMarksExactlyTheRestoredTool() {
        let state = EditorState()
        state.tool = .rectangle

        XCTAssertTrue(state.isToolMarked(.rectangle), "the restored tool is the one marked item")
        XCTAssertFalse(state.isCropMarked, "a fresh state marks the tool, never crop")
        for tool in Tool.captureEditorTools where tool != .rectangle {
            XCTAssertFalse(state.isToolMarked(tool), "\(tool.rawValue) must not be marked too")
        }
    }

    // MARK: - Picking crop clears the tool

    func testSelectingCropUnmarksTheActiveTool() {
        let state = EditorState()
        state.tool = .pen

        state.selectCrop()

        XCTAssertTrue(state.isCropMarked, "crop is the armed item after it is picked")
        XCTAssertFalse(state.isToolMarked(.pen), "the active tool is unmarked when crop is picked")
        XCTAssertFalse(state.isToolMarked(.blur), "no other tool is marked either")
    }

    func testSelectingCropKeepsTheRememberedToolUnchanged() {
        let state = EditorState()
        state.tool = .pen

        state.selectCrop()

        XCTAssertEqual(state.tool, .pen, "crop arms itself without changing the tool, so drawing resumes with it")
    }

    // MARK: - Picking a tool clears the crop

    func testSelectingAToolUnmarksCrop() {
        let state = EditorState()
        state.selectCrop()
        XCTAssertTrue(state.isCropMarked)

        state.select(.pen)

        XCTAssertTrue(state.isToolMarked(.pen), "the picked tool is the armed item again")
        XCTAssertFalse(state.isCropMarked, "picking any tool gives the crop up")
    }

    func testSelectingTheSameRememberedToolAlsoUnmarksCrop() {
        let state = EditorState()
        state.tool = .pen
        state.selectCrop()
        XCTAssertTrue(state.isCropMarked)

        // The remembered tool is still `tool`: picking it again must still be a
        // real transition that unmarks crop.
        state.select(.pen)

        XCTAssertFalse(state.isCropMarked)
        XCTAssertTrue(state.isToolMarked(.pen))
    }

    // MARK: - Giving the crop up

    func testEndingTheCropReturnsTheMarkToTheRememberedTool() {
        let state = EditorState()
        state.tool = .ellipse
        state.selectCrop()

        state.endCropSelection()

        XCTAssertTrue(state.isToolMarked(.ellipse), "the mark goes back to the remembered tool")
        XCTAssertFalse(state.isCropMarked)
    }
}
