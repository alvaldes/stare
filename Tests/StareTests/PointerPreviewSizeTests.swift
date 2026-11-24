import SwiftUI
import XCTest

@testable import Stare
import StareCore

/// S5: the pointer preview was too tall. Its tile is a fixed canvas — the
/// highlight never grows the pane — so the pane's height is the tile plus the
/// caption, and the only way to shorten it is a smaller canvas. Shrinking it
/// costs the "real size" reading of the 72 pt default, which is why the floor
/// is a rule and not a taste: the default must still paint large enough to
/// read, and the caption keeps telling the truth about the scale it draws at.
@MainActor
final class PointerPreviewSizeTests: XCTestCase {
    /// The canvas the preview had before S5.
    private let oldCanvasSide: CGFloat = 168
    /// The smallest canvas that still shows the default's glow, band and shape
    /// at a legible size rather than as a speck.
    private let legibleFloor: CGFloat = 110

    private func defaultAppearance() -> PointerAppearance {
        PointerStyle(preset: .rhombus, size: 72, colorSource: .ink).appearance(ink: .red)
    }

    func testThePreviewCanvasIsShorterThanTheOldOneAndStillLegible() {
        let side = PointerPreviewView.tileSide
        XCTAssertLessThan(side, oldCanvasSide, "S5: the preview must be shorter than the 168 pt canvas it had")
        XCTAssertGreaterThanOrEqual(side, legibleFloor, "S5: a canvas this small would shrink the default into a speck")
    }

    func testTheDefaultHighlightStillPaintsMostOfItsSizeOnTheShorterCanvas() {
        let extent = PointerHighlightRenderer.extent(for: defaultAppearance(), pulseScale: 1).width
        let scale = PointerHighlightRenderer.fitScale(
            extentSide: Double(extent),
            canvasSide: Double(PointerPreviewView.tileSide)
        )
        // Below ~0.7 the default's 72 pt ring reads as a small blob; the
        // caption would also be naming a scale that no longer means anything.
        XCTAssertGreaterThanOrEqual(scale, 0.7, "S5: the default must keep most of its size on the shorter canvas")
        XCTAssertLessThanOrEqual(scale, 1, "the preview never upscales")
    }

    func testThePaneHeightThePreviewAsksForIsTheTileAndItsCaption() {
        // The tile is square, so the pane's height is one tile plus the
        // caption row the view stacks under it (6 pt spacing + one 16 pt line).
        let height = PointerPreviewView.tileSide + 6 + 16
        XCTAssertLessThanOrEqual(height, 160, "S5: the preview must not eat a quarter of the pane again")
    }
}
