import Foundation
import XCTest
@testable import Stare
import StareCore
import UniformTypeIdentifiers

/// T4/S4: the bar/pool organiser must actually move items, not just look as
/// if it does ("la opción 'In the pool' funciona porque no creo que lo haga").
/// The tests instantiate the real `BarPane` and fire its REAL drop handlers
/// (`handleBarDrop`, `handlePoolDrop`, `handlePoolEndDrop`) on a real
/// `PreferencesModel` over an in-memory store, so what is pinned is the exact
/// code a drop runs and exactly the draft both zones render from
/// (`model.toolbarTools`): the stage passes `model.toolbarTools.items` to the
/// real `ToolbarView` and the pool reads `model.toolbarTools.pool`.
/// The SwiftUI receipt itself (a `performDrop` calling into the delegate)
/// cannot be driven by a unit test — `DropInfo` is constructed only by
/// SwiftUI — and the payload hop into the main actor is already pinned by
/// `SettingsOrganiserDropTests`.
@MainActor
final class SettingsOrganiserTransferTests: XCTestCase {

    /// An in-memory `PreferenceStore`: the drop handlers persist on every
    /// write, and these tests must never touch the user's real preferences.
    private final class InMemoryPreferenceStore: PreferenceStore {
        private var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    /// A complete, normalised layout: every tool is accounted for, so the
    /// expectations below never race the "anything it never mentions lands
    /// in the pool" tail of normalisation — the fixtures name the off-bar
    /// tools deliberately, as a real user's draft would.
    private func layout(
        items: [ToolbarLayoutItem],
        pool: [Tool]
    ) -> ToolbarToolLayout {
        ToolbarToolLayout(items: items, pool: pool)
    }

    /// The pane whose handlers the tests fire, on an isolated model draft.
    private func makePane(
        items: [ToolbarLayoutItem],
        pool: [Tool]
    ) -> (pane: BarPane, model: PreferencesModel) {
        let model = PreferencesModel(store: InMemoryPreferenceStore())
        model.toolbarTools = layout(items: items, pool: pool)
        let pane = BarPane(model: model, cardsWidth: 600)
        return (pane, model)
    }

    /// The expectation as intent: the tools that must remain on the bar, in
    /// order, and the tools that must wait in the pool, in that order. The
    /// layout normalises the intent exactly as a stored draft would be, so
    /// the comparison is between two fully normalised documents.
    private func expect(
        items: [ToolbarLayoutItem],
        pool: [Tool]
    ) -> ToolbarToolLayout {
        layout(items: items, pool: pool)
    }

    /// Every tool the given items leave off the bar, in the documented
    /// default order — the tail normalisation always appends behind the
    /// stored pool entries.
    private func offBar(
        items: [ToolbarLayoutItem],
        except neverNamed: [Tool] = []
    ) -> [Tool] {
        let onBar = Set(items.compactMap(\.tool))
        let appended = Set(neverNamed)
        return ToolbarToolLayout.defaultOrder.filter { !onBar.contains($0) && !appended.contains($0) }
    }

    // MARK: - Bar → pool

    /// Dropping a bar tool on the pool's dashed end zone takes it off the bar
    /// and puts it at the end of the pool, behind what was already there.
    /// The payload is the trailing tool — the bar's first tool cannot leave
    /// (T3/S2), so the drag-out fixtures use one that may. (The separator's
    /// emptying here is normalisation's own invariant — with one tool left
    /// no tool-tool gap remains for it.)
    func testDroppingABarToolOnThePoolEndZoneTakesItOffTheBarIntoThePool() {
        let (pane, model) = makePane(
            items: [.tool(.pen), .separator, .tool(.eraser)],
            pool: [.laser]
        )

        pane.handlePoolEndDrop(payload: .tool(.eraser))

        XCTAssertEqual(
            model.toolbarTools,
            expect(
                items: [.tool(.pen)],
                pool: [.laser] + offBar(items: [.tool(.pen)], except: [.eraser]) + [.eraser]),
            "the eraser left the bar and waits at the very end of the pool")
    }

    /// Dropping a bar tool onto a pool chip places it in the pool at the
    /// dropped spot — before or after the chip, whatever the drop's side
    /// says — and it is off the bar in the same write. The payload is the
    /// trailing tool, because the bar's first tool cannot leave (T3/S2).
    func testDroppingABarToolOnAPoolChipEntersThePoolAtThatSpot() {
        let (pane, model) = makePane(
            items: [.tool(.pen), .tool(.eraser)],
            pool: [.laser, .blur]
        )

        // The eraser lands on the blur chip's before-half.
        pane.handlePoolDrop(target: .tool(.blur), edge: .before, payload: .tool(.eraser))

        XCTAssertEqual(
            model.toolbarTools,
            expect(items: [.tool(.pen)], pool: [.laser, .eraser, .blur]),
            "the eraser entered the pool exactly where it was dropped")

        // And the same drop on a chip's after-half lands after it.
        let (later, laterModel) = makePane(
            items: [.tool(.pen), .tool(.eraser)],
            pool: [.laser, .blur]
        )
        later.handlePoolDrop(target: .tool(.blur), edge: .after, payload: .tool(.eraser))
        XCTAssertEqual(
            laterModel.toolbarTools,
            expect(items: [.tool(.pen)], pool: [.laser, .blur, .eraser]))
    }

    /// A placed separator comes back off the bar through the pool's end
    /// zone — one of the ways out now, since every pool target takes it
    /// (T4/S3). It never becomes a pool item: the pool ends unchanged.
    func testDroppingAPlacedSeparatorOnThePoolEndZoneTakesItOffTheBar() {
        let (pane, model) = makePane(
            items: [.tool(.pen), .separator, .tool(.eraser)],
            pool: [.laser]
        )

        pane.handlePoolEndDrop(payload: .separator)

        XCTAssertEqual(
            model.toolbarTools,
            expect(items: [.tool(.pen), .tool(.eraser)], pool: [.laser]),
            "the placed separator left the bar; the pool is unchanged")
    }

    /// The bar can never go empty, so the last tool refuses to leave it: the
    /// draft comes back exactly as it was.
    func testTheLastToolRefusesToLeaveTheBar() {
        let (pane, model) = makePane(
            items: [.tool(.pen)],
            pool: [.eraser]
        )
        let draft = model.toolbarTools

        pane.handlePoolEndDrop(payload: .tool(.pen))

        XCTAssertEqual(model.toolbarTools, draft, "the draft is unchanged")
    }

    /// A separator dropped onto a pool chip changes nothing: separators do
    /// not stack in the pool.
    func testASeparatorDropOnAPoolChipChangesNothing() {
        let (pane, model) = makePane(
            items: [.tool(.pen)],
            pool: [.eraser]
        )
        let draft = model.toolbarTools

        pane.handlePoolDrop(target: .tool(.eraser), edge: .before, payload: .separator)

        XCTAssertEqual(model.toolbarTools, draft)
    }

    // MARK: - Pool → bar

    /// Dropping a pool chip onto the bar inserts it at the dropped position —
    /// the target's position plus the drop's side — and the pool stops
    /// showing it. A placed separator the drop does not name keeps its place.
    func testDroppingAPoolChipOnTheBarInsertsItAtTheDroppedSpot() {
        let (pane, model) = makePane(
            items: [.tool(.pen), .separator, .tool(.eraser)],
            pool: [.laser]
        )

        // The laser lands on the eraser's after-half.
        pane.handleBarDrop(target: .tool(.eraser), edge: .after, payload: .tool(.laser))

        XCTAssertEqual(
            model.toolbarTools,
            expect(
                items: [.tool(.pen), .separator, .tool(.eraser), .tool(.laser)],
                pool: []),
            "the laser joined the bar at the dropped spot and left the pool")
    }

    /// A pool tool dropped beside a placed separator does not disturb it: the
    /// separator stays a real item strictly between two tools, never
    /// collapsed, never re-homed.
    func testDroppingAPoolChipBesideAPlacedSeparatorKeepsTheSeparator() {
        let (pane, model) = makePane(
            items: [.tool(.pen), .separator, .tool(.eraser)],
            pool: [.laser]
        )

        // The laser lands on the pen's after-half — the separator's own
        // before-side.
        pane.handleBarDrop(target: .tool(.pen), edge: .after, payload: .tool(.laser))

        XCTAssertEqual(
            model.toolbarTools,
            expect(
                items: [.tool(.pen), .tool(.laser), .separator, .tool(.eraser)],
                pool: []))
    }

    // MARK: - Pool reorder

    /// Dropping a pool chip onto another pool chip reorders the pool by its
    /// halves without disturbing the bar.
    func testDroppingAPoolChipOnAnotherPoolChipReordersThePool() {
        let (pane, model) = makePane(
            items: [.tool(.pen)],
            pool: [.laser, .blur, .select]
        )

        // The select chip lands on the laser chip's before-half.
        pane.handlePoolDrop(target: .tool(.laser), edge: .before, payload: .tool(.select))

        XCTAssertEqual(
            model.toolbarTools,
            expect(items: [.tool(.pen)], pool: [.select, .laser, .blur]),
            "the pool reordered at the dropped spot; the bar is untouched")
    }

    /// T3/S2: the bar's first tool cannot leave, on any pool target — the
    /// drag-out refuses and the draft stays exactly as it was. Before the
    /// fix the same drop "worked" (the gesture completed) and the pen
    /// silently left the bar.
    func testTheFirstToolCannotLeaveThroughThePoolEndZone() {
        let (pane, model) = makePane(
            items: [.tool(.pen), .separator, .tool(.eraser)],
            pool: [.laser]
        )
        let draft = model.toolbarTools

        pane.handlePoolEndDrop(payload: .tool(.pen))

        XCTAssertEqual(
            model.toolbarTools, draft,
            "the bar's first tool cannot leave: the drag-out is refused and the draft is unchanged")
    }

    /// T3/S2: the same refusal on a pool chip, either half of it.
    func testTheFirstToolCannotLeaveThroughAPoolChip() {
        let (pane, model) = makePane(
            items: [.tool(.pen), .tool(.eraser)],
            pool: [.laser, .blur]
        )
        let draft = model.toolbarTools

        pane.handlePoolDrop(target: .tool(.laser), edge: .before, payload: .tool(.pen))
        XCTAssertEqual(
            model.toolbarTools, draft,
            "the bar's first tool cannot leave through a pool chip either")

        pane.handlePoolDrop(target: .tool(.blur), edge: .after, payload: .tool(.pen))
        XCTAssertEqual(model.toolbarTools, draft)
    }

    // MARK: - Separators come off onto any pool target (T4/S3)

    /// T4/S3: a placed separator used to leave only through the pool's
    /// dashed end zone, because the pool chips accepted tools only. Now any
    /// pool target takes it off the bar; the drop's side lands it nowhere
    /// but off the bar, because the pool never stores separators as pool
    /// items.
    func testAPlacedSeparatorComesOffOntoAnyPoolChip() {
        let (pane, model) = makePane(
            items: [.tool(.pen), .separator, .tool(.eraser)],
            pool: [.laser]
        )

        pane.handlePoolDrop(target: .tool(.laser), edge: .before, payload: .separator)

        XCTAssertEqual(
            model.toolbarTools,
            expect(items: [.tool(.pen), .tool(.eraser)], pool: [.laser]),
            "the placed separator came off through a pool chip; the pool never stores separators")

        let (later, laterModel) = makePane(
            items: [.tool(.pen), .separator, .tool(.eraser)],
            pool: [.laser]
        )
        later.handlePoolDrop(target: .tool(.laser), edge: .after, payload: .separator)
        XCTAssertEqual(
            laterModel.toolbarTools,
            expect(items: [.tool(.pen), .tool(.eraser)], pool: [.laser]),
            "either half of the chip takes the separator off")
    }

    // MARK: - Reordering in place, across a placed separator (T5/S5)

    /// T5/S5: moving a bar tool across a placed separator used to drop that
    /// separator — `[pen, sep, eraser]`, pen onto the eraser's after-edge,
    /// produced `[eraser, pen]` while `[eraser, sep, pen]` was reachable —
    /// forcing a round trip through the pool to keep the divider. Now the
    /// separator relocates to the nearest legal slot instead.
    func testAMovedToolAcrossAPlacedSeparatorRelocatesTheSeparator() {
        let (pane, model) = makePane(
            items: [.tool(.pen), .separator, .tool(.eraser)],
            pool: []
        )

        pane.handleBarDrop(target: .tool(.eraser), edge: .after, payload: .tool(.pen))

        XCTAssertEqual(
            model.toolbarTools,
            expect(items: [.tool(.eraser), .separator, .tool(.pen)], pool: []),
            "the pen landed where it was dropped and the separator it crossed was relocated, not deleted")
    }

    // MARK: - One draft, two zones

    /// Both zones write the same `model.toolbarTools` draft the stage and the
    /// pool render from: a pool→bar drop changes the bar's item list at once,
    /// and a following bar→pool drop changes the pool's list on the same
    /// model. Neither zone renders a stale copy.
    func testBothZonesWriteTheSameDraftTheStageAndThePoolRenderFrom() {
        let (pane, model) = makePane(
            items: [.tool(.pen), .tool(.eraser)],
            pool: [.laser]
        )

        // Pool → bar: the pool loses the laser and the bar gains it in the
        // same write, so the stage re-lays itself from the change.
        pane.handleBarDrop(target: .tool(.pen), edge: .after, payload: .tool(.laser))
        XCTAssertEqual(
            model.toolbarTools,
            expect(items: [.tool(.pen), .tool(.laser), .tool(.eraser)], pool: []))

        // Bar → pool on the same draft: the pool gains the eraser and the bar
        // loses it in the same write, so the pool re-lays itself too.
        pane.handlePoolEndDrop(payload: .tool(.eraser))
        XCTAssertEqual(
            model.toolbarTools,
            expect(
                items: [.tool(.pen), .tool(.laser)],
                pool: offBar(items: [.tool(.pen), .tool(.laser)], except: [.eraser]) + [.eraser]))
    }
}
