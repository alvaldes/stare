import AppKit
import SwiftUI
import XCTest

@testable import Stare
import StareCore

/// Every settings pane lays out in bounded space, at every width the window can
/// be dragged to. Two attempts at equalising the card columns (B8) each broke a
/// pane — an `.infinity` proposal answered with `.infinity` gave every card an
/// unbounded height and the Capture pane died with a NaN view origin — so the
/// guard that matters is this one, on the real render, for both column widths.
@MainActor
final class SettingsPaneLayoutTests: XCTestCase {
    private final class InMemoryPreferenceStore: PreferenceStore {
        private var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    private struct StubClient: ScreenRecordingClient {
        func preflight() -> Bool { true }
        func request() -> Bool { true }
        func canCapture() -> Bool { true }
        func openPrivacySettings() {}
    }

    private func render(_ area: SettingsArea, cardsWidth: CGFloat) throws -> NSHostingView<AnyView> {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        let permission = PermissionProbe(
            permission: ScreenRecordingPermission(client: StubClient())
        )
        let hosting = NSHostingView(rootView: AnyView(
            SettingsView.pane(for: area, width: cardsWidth, model: model, permission: permission)
        ))
        hosting.frame = CGRect(
            origin: .zero,
            size: CGSize(width: cardsWidth + 2 * SettingsMetrics.panePadding, height: 900)
        )
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    func testEveryPaneLaysOutInBoundedSpaceAtBothColumnWidths() throws {
        // 720 cards width is two columns; 520 is the single-column fold.
        for cardsWidth in [CGFloat(720), 520] {
            for area in SettingsArea.allCases {
                let hosting = try render(area, cardsWidth: cardsWidth)
                var unbounded: [String] = []
                func walk(_ view: NSView) {
                    if !view.frame.width.isFinite || !view.frame.height.isFinite {
                        unbounded.append("\(type(of: view)) \(view.frame)")
                    }
                    view.subviews.forEach(walk)
                }
                walk(hosting)
                XCTAssertEqual(
                    unbounded, [],
                    "\(area.rawValue) at \(cardsWidth) laid a view out in unbounded space"
                )
            }
        }
    }

    /// B8 is rows now: one row per card of the longer column, so every row has
    /// a cell on both sides and the two cards of a row share its height.
    func testTheColumnsAreLaidOutAsOneRowPerCardOfTheLongerColumn() {
        func columns(left: Int, right: Int) -> SettingsColumns {
            SettingsColumns(
                width: 720,
                left: (0..<left).map { AnyView(Color.clear.opacity(Double($0))) },
                right: (0..<right).map { AnyView(Color.clear.opacity(Double($0))) }
            )
        }
        XCTAssertEqual(columns(left: 2, right: 1).rows, 2, "2-vs-1 is two rows, the second with a filler")
        XCTAssertEqual(columns(left: 2, right: 3).rows, 3)
        XCTAssertEqual(columns(left: 2, right: 2).rows, 2)
        XCTAssertEqual(columns(left: 0, right: 3).rows, 3)
    }

    func testAColumnIsNeverTallerThanItsOwnCardsAllow() throws {
        // The regression the equalisation caused: a column stretched past its
        // content pushed the pane's height to the whole viewport and the cards
        // spread over it. Each column now ends where its own cards do.
        let hosting = try render(.overlay, cardsWidth: 720)
        XCTAssertLessThan(
            hosting.fittingSize.height, 900,
            "the overlay pane must size to its cards, not to the viewport it is scrolled in"
        )
    }
}
