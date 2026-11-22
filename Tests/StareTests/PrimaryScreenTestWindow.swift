import AppKit
import Foundation
import XCTest

/// Where a test window may appear: the primary screen, and only there.
///
/// The human watches content on their secondary monitors while `swift test`
/// runs. A window whose screen the test does not pin — one placed by the
/// pointer's location (`NSEvent.mouseLocation`), by `NSScreen.main`, by a
/// cascade offset, or one built for every display — can land on those
/// monitors and interrupt what the human is watching. Every window a test
/// shows is placed through this helper, which returns a frame on
/// `NSScreen.screens.first` — the menu-bar display, always the array's first
/// entry — fully inside that screen's `visibleFrame`, so the frame cannot
/// reach another display and never covers the menu bar or the Dock.
///
/// Do not simplify this away or bypass it: the constraint protects the
/// human's other monitors, not the test's own correctness. A test whose
/// window the primary cannot host skips cleanly instead of straying.
enum PrimaryScreenTestWindow {
    /// A frame of exactly `size`, centred inside the primary screen's
    /// `visibleFrame`. `nil` when there is no screen (callers skip) or the
    /// primary's visible frame cannot hold `size` — a window the primary
    /// cannot host must be refused, never placed half off the screen.
    static func frame(for size: CGSize) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let visible = primary.visibleFrame
        guard size.width <= visible.width, size.height <= visible.height else { return nil }
        return CGRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// Pins the helper's contract: every frame it returns is exactly the
/// requested size, sits wholly inside the primary screen's `visibleFrame`,
/// and never reaches another display — and a request the primary cannot
/// hold is refused instead of being placed off-screen.
@MainActor
final class PrimaryScreenTestWindowTests: XCTestCase {
    func testEveryFrameStaysOnThePrimaryScreen() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the constraint needs a real display")
        let primary = try XCTUnwrap(NSScreen.screens.first)
        let visible = primary.visibleFrame
        let sizes = [
            CGSize(width: 1, height: 1),
            CGSize(width: 900, height: 600),
            visible.size,
        ]
        for size in sizes {
            let frame = try XCTUnwrap(
                PrimaryScreenTestWindow.frame(for: size),
                "a frame the primary can host must never be refused")
            XCTAssertEqual(frame.width, size.width, accuracy: 0.5)
            XCTAssertEqual(frame.height, size.height, accuracy: 0.5)
            XCTAssertTrue(
                visible.contains(frame),
                "\(frame) must sit inside the primary screen's visible frame \(visible)")
            for screen in NSScreen.screens.dropFirst() {
                XCTAssertFalse(
                    frame.intersects(screen.frame),
                    "\(frame) may never reach another display: the human watches them while the tests run")
            }
        }
    }

    func testAnOversizedRequestIsRefusedInsteadOfStraying() throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "the constraint needs a real display")
        let primary = try XCTUnwrap(NSScreen.screens.first)
        let oversized = CGSize(
            width: primary.visibleFrame.width + 1,
            height: primary.visibleFrame.height + 1)
        XCTAssertNil(
            PrimaryScreenTestWindow.frame(for: oversized),
            "a frame the primary cannot hold must be refused, never placed off-screen")
    }
}
