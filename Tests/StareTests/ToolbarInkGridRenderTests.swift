import AppKit
import SwiftUI
import XCTest
@testable import Stare
import StareCore

/// S10/L29: the bar folds its inks into two columns when it is a column, and
/// keeps the single row when it is a row. The palette is the tallest block in a
/// vertical bar — eight rows at a 28 pt pitch, 220 pt, 30 % of the column — so the fold
/// is what the owner asked for after naming the column's height twice.
///
/// Measured on the real hosted bar, not on a mock: the panel is built on the
/// detached state (no preferences model, so nothing is read from or written to
/// this machine's stored bar layout), the orientation and the tool layout are
/// pinned explicitly so the measurements cannot drift with a saved layout, and
/// the hosting view's fitting size is read in both orientations. A render probe
/// needs a display, so it skips without one.
///
/// Recorded measurements (this Mac, shipped default bar content):
/// - before the fold (one ink per row, both orientations):
///   vertical 44×742, horizontal 748×42
/// - after the fold, first attempt (two columns of 20 pt cells, vertical only):
///   vertical 62×630, horizontal 748×42 — 112 pt of height bought for
///   18 pt of width, and the owner rejected the width: "se ve mas ancha y
///   no debe cambiar el ancho" (S11)
/// - with 12 pt cells and no gap (S11/L30): vertical 44×630 — the pill is back
///   at the width the single-column bar always had, because the tool cell's
///   26 pt drives it again
/// - now (11 pt square cells, 2 pt of air both ways, 10 pt dots):
///   vertical 44×572, horizontal 748×42 — the same width, 170 pt shorter than the
///   single-column bar. The cells went from 11×24 to 11×11 because a 10 pt dot
///   in a 24 pt tall cell left 18 pt of air between rows against 3 pt between
///   columns: the grid read as loose vertically and tight horizontally (L33).
///   Air is now the same in both directions — 2 pt of spacing plus the 0.5 pt
///   margin the cell leaves around each dot, so 3 pt between neighbouring dots,
///   matching what the horizontal row puts between its 15 pt dots.
final class ToolbarInkGridRenderTests: XCTestCase {
    /// The single-column vertical bar's recorded fitting height (one ink per
    /// row, before the fold). The fold must still save a real cut against it,
    /// independent of the exact pinned size below.
    static let singleColumnVerticalHeight: CGFloat = 742

    static let singleColumnVerticalWidth: CGFloat = 44

    private func fittingSize(vertical: Bool) -> CGSize {
        let state = EditorState()
        state.toolbarOrientation = vertical ? .vertical : .horizontal
        // Pinned explicitly so the measurement cannot depend on a saved
        // layout; the state is detached (no preferences model), so this write
        // stays in memory.
        state.toolbarTools = ToolbarToolLayout.standard
        let panel = ToolbarPanel(
            state: state,
            onUndo: {},
            onRedo: {},
            onClear: {},
            onDone: {}
        )
        defer { panel.orderOut(nil) }
        guard let hosting = panel.contentView else { return .zero }
        return hosting.fittingSize
    }

    func testTheVerticalBarFitsTheFoldedInkGrid() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the probe needs a real display")
        let fit = fittingSize(vertical: true)
        XCTAssertEqual(
            fit.width, 44, accuracy: 2,
            "the folded vertical bar must be back at the single-column width, 44, measured \(fit.width)×\(fit.height)")
        XCTAssertEqual(
            fit.height, 572, accuracy: 2,
            "the folded vertical bar must keep the fold's height, 572, measured \(fit.width)×\(fit.height)")
        // The pin above could drift if the bar's other blocks change; the
        // saving the fold must produce is pinned on its own so a revert of
        // the two-column grid fails loudly instead of silently re-pinning.
        XCTAssertLessThanOrEqual(
            fit.height, Self.singleColumnVerticalHeight - 100,
            "the fold must save at least 100 pt against the single-column bar (\(fit.height))")
        // The owner's hard rule (S11): the folded vertical bar must not be one
        // point wider than the single-column bar. A wider pill fails here no
        // matter how the width pin above is updated.
        XCTAssertLessThanOrEqual(
            fit.width, Self.singleColumnVerticalWidth,
            "the folded vertical bar must not be wider than the single-column bar (\(Self.singleColumnVerticalWidth) pt), measured \(fit.width)")
    }

    func testTheHorizontalBarKeepsItsSingleRow() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the probe needs a real display")
        let fit = fittingSize(vertical: false)
        XCTAssertEqual(
            fit.width, 748, accuracy: 2,
            "the horizontal bar must stay 748 pt wide, measured \(fit.width)×\(fit.height)")
        XCTAssertEqual(
            fit.height, 42, accuracy: 2,
            "the horizontal bar must stay 42 pt tall, measured \(fit.width)×\(fit.height)")
    }
}
