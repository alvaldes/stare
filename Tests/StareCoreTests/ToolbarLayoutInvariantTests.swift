import XCTest
@testable import StareCore

/// S5/S7 invariants of the toolbar layout under every mutation path:
/// `removing(_:intoPoolAt:)` clamps off-range pool indices instead of
/// trapping, a separator dropped beside another separator lands in the
/// nearest legal slot instead of vanishing, and 2000 seeded random mutation
/// steps can never break the reachable state: at least one tool, no
/// duplicate, no leading/trailing/adjacent separator, bar and pool disjoint,
/// their union exactly every tool, and an encode→decode round trip that
/// changes nothing — checked after every step.
final class ToolbarLayoutInvariantTests: XCTestCase {

    // MARK: - removing(_:intoPoolAt:) clamps instead of trapping

    /// The verifier's crash: a negative pool index used to reach
    /// `Array.insert(_:at:)` and die with "Negative Array index is out of
    /// range" (reproduced standalone before the fix). Now it clamps to the
    /// front of the pool.
    func testRemovingIntoPoolClampsANegativeIndexToTheFront() {
        let layout = ToolbarToolLayout(
            items: [.tool(.pen), .separator, .tool(.eraser)],
            pool: [.laser, .number])

        let clamped = layout.removing(.tool(.eraser), intoPoolAt: -1)

        XCTAssertEqual(clamped.pool.first, .eraser, "a negative index clamps to slot 0")
        XCTAssertEqual(clamped.pool.dropFirst(), [.laser, .number, .select, .highlighter, .line, .arrow, .rectangle, .ellipse, .text, .blur])
    }

    /// A too-large pool index clamps to the end of the pool — the same
    /// outcome the old "anything over the count appends" rule gave.
    func testRemovingIntoPoolClampsATooLargeIndexToTheBack() {
        let layout = ToolbarToolLayout(
            items: [.tool(.pen), .separator, .tool(.eraser)],
            pool: [.laser, .number])

        let clamped = layout.removing(.tool(.eraser), intoPoolAt: 99)

        XCTAssertEqual(clamped.pool.last, .eraser, "a too-large index clamps to the end")
        XCTAssertEqual(clamped.pool.dropLast(), [.laser, .number, .select, .highlighter, .line, .arrow, .rectangle, .ellipse, .text, .blur])
    }

    /// The boundary values keep their old meaning: 0 inserts in front of the
    /// pool, the pool's count appends. Normalisation tops the pool up with
    /// the bar's off tools after the inserted one, so the position is judged
    /// by the insertion spot, not the array's last entry.
    func testRemovingIntoPoolKeepsTheBoundaryMeanings() {
        let layout = ToolbarToolLayout(
            items: [.tool(.pen), .separator, .tool(.eraser)],
            pool: [.laser, .number])

        XCTAssertEqual(layout.removing(.tool(.eraser), intoPoolAt: 0).pool.first, .eraser)
        let appended = layout.removing(.tool(.eraser), intoPoolAt: 2)
        XCTAssertEqual(appended.pool.count, 11)
        XCTAssertEqual(appended.pool[2], .eraser, "pool.count appends right after the stored tools")
    }

    /// A separator removal ignores the pool index entirely — it must not
    /// trap on one either.
    func testRemovingASeparatorKeepsThePoolWhateverTheIndex() {
        let layout = ToolbarToolLayout(
            items: [.tool(.pen), .separator, .tool(.eraser)],
            pool: [.laser])

        let removed = layout.removing(.separator, intoPoolAt: -7)
        XCTAssertEqual(removed.items, [.tool(.pen), .tool(.eraser)])
        XCTAssertEqual(removed.pool.first, .laser, "the pool keeps its order top-up after the stored tools")
        XCTAssertEqual(removed.pool.count, 10)
    }

    // MARK: - a separator next to another separator does not vanish

    /// The cosmetic finding: dropping a separator so it lands beside an
    /// existing one used to insert two adjacent separators, which
    /// normalisation collapsed — the fresh drop vanished silently. Now it
    /// lands in the nearest legal slot (strictly between two tools).
    func testASeparatorInsertedBesideAnotherSeparatorLandsInTheNearestLegalSlot() {
        let layout = ToolbarToolLayout(items: [
            .tool(.pen), .separator, .tool(.eraser), .tool(.arrow),
        ])

        // Dropped between the existing separator and the eraser: the only
        // legal gap is between eraser and arrow, one slot away.
        let after = layout.inserting(.separator, at: 2)
        XCTAssertEqual(after.items, [
            .tool(.pen), .separator, .tool(.eraser), .separator, .tool(.arrow),
        ])

        // Dropped the other side of the same separator (slot 1): the nearest
        // legal slot is still the eraser–arrow gap.
        let before = layout.inserting(.separator, at: 1)
        XCTAssertEqual(before.items, [
            .tool(.pen), .separator, .tool(.eraser), .separator, .tool(.arrow),
        ])
    }

    /// A bar with no tool-to-tool gap left has no legal slot for another
    /// separator: the insert is refused (the layout is unchanged) rather
    /// than silently eating anything.
    func testASeparatorInsertWithNoLegalSlotIsRefused() {
        let layout = ToolbarToolLayout(items: [.tool(.pen), .separator, .tool(.eraser)])
        let original = layout

        let refusedAtAdjacent = layout.inserting(.separator, at: 1)
        XCTAssertEqual(refusedAtAdjacent, original)
        let refusedAtOtherSide = layout.inserting(.separator, at: 2)
        XCTAssertEqual(refusedAtOtherSide, original)
    }

    /// Moving an existing separator next to its neighbour — the organiser's
    /// in-place reorder of a separator — must keep both separators: the
    /// moved one lands in the nearest legal slot.
    func testAMovedSeparatorLandsInTheNearestLegalSlotAndKeepsEverySeparator() {
        let layout = ToolbarToolLayout(items: [
            .tool(.pen), .separator, .tool(.eraser), .tool(.arrow),
        ])

        // Dropping the separator at the eraser–arrow gap (slot 3) is legal
        // and lands there…
        let repositioned = layout.moving(.separator, to: 3)
        XCTAssertEqual(repositioned.items, [
            .tool(.pen), .tool(.eraser), .separator, .tool(.arrow),
        ])

        // …and a two-separator bar moved into a neighbouring slot keeps both.
        let two = ToolbarToolLayout(items: [
            .tool(.pen), .separator, .tool(.eraser), .separator, .tool(.arrow),
        ])
        let moved = two.moving(.separator, to: 3)
        XCTAssertEqual(moved.items.filter { $0.tool == nil }.count, 2, "no separator may vanish")
        XCTAssertFalse(
            zip(moved.items, moved.items.dropFirst()).contains { $0.0.tool == nil && $0.1.tool == nil },
            "no two separators may end up adjacent")
    }

    // MARK: - the fuzz: 2000 random mutation steps, every invariant, every step

    /// A tiny seeded LCG so a failing seed reproduces exactly.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }

        /// A uniformly drawn value in `0..<bound`.
        mutating func below(_ bound: Int) -> Int {
            Int(next() % UInt64(max(bound, 1)))
        }

        /// A slot index spanning three past each end, so the clamps and the
        /// nearest-legal-slot search are exercised by the fuzz itself.
        mutating func spanIndex(_ count: Int) -> Int {
            below(count + 6) - 3
        }

        mutating func itemIndex(_ count: Int) -> Int { spanIndex(count) }
        mutating func poolIndex(_ count: Int) -> Int { spanIndex(count) }
    }

    private func assertInvariants(_ layout: ToolbarToolLayout, step: Int) {
        XCTAssertFalse(layout.visibleTools.isEmpty, "step \(step): the bar lost its last tool")
        XCTAssertEqual(
            layout.visibleTools.count, Set(layout.visibleTools).count,
            "step \(step): a duplicate tool survived")
        if let first = layout.items.first, first.tool == nil {
            XCTFail("step \(step): leading separator at the bar's head: \(layout.items)")
        }
        if let last = layout.items.last, last.tool == nil {
            XCTFail("step \(step): trailing separator at the bar's tail: \(layout.items)")
        }
        for (left, right) in zip(layout.items, layout.items.dropFirst()) {
            XCTAssertTrue(
                !(left.tool == nil && right.tool == nil),
                "step \(step): adjacent separators in \(layout.items)")
        }
        XCTAssertTrue(
            Set(layout.visibleTools).isDisjoint(with: layout.pool),
            "step \(step): a tool is both on the bar and in the pool")
        XCTAssertEqual(
            layout.visibleTools.count + layout.pool.count,
            ToolbarToolLayout.defaultOrder.count,
            "step \(step): bar ∪ pool is no longer every tool exactly once")
        XCTAssertEqual(
            Set(layout.visibleTools).union(layout.pool),
            Set(ToolbarToolLayout.defaultOrder),
            "step \(step): bar ∪ pool lost or gained a tool")
    }

    func testTwoThousandRandomMutationStepsKeepEveryLayoutInvariant() throws {
        var rng = SeededGenerator(seed: 0xC0FFEE)
        var layout = ToolbarToolLayout.standard
        assertInvariants(layout, step: -1)

        for step in 0..<2000 {
            let tool = ToolbarToolLayout.defaultOrder[rng.below(ToolbarToolLayout.defaultOrder.count)]
            let item: ToolbarLayoutItem = rng.below(4) == 0 ? .separator : .tool(tool)

            switch rng.below(6) {
            case 0:
                layout = layout.inserting(item, at: rng.itemIndex(layout.items.count))
            case 1:
                let moved = layout.items[rng.below(layout.items.count)]
                layout = layout.moving(moved, to: rng.itemIndex(layout.items.count))
            case 2:
                let at = rng.below(layout.items.count)
                layout = layout.removing(layout.items[at], intoPoolAt: rng.poolIndex(layout.pool.count))
            case 3:
                layout = layout.removing(item)
            case 4:
                layout = layout.movingInPool(tool, to: rng.poolIndex(layout.pool.count))
            default:
                layout = layout.inserting(.tool(tool), at: rng.itemIndex(layout.items.count))
            }

            assertInvariants(layout, step: step)

            let data = try JSONEncoder().encode(layout)
            let decoded = try JSONDecoder().decode(ToolbarToolLayout.self, from: data)
            XCTAssertEqual(decoded, layout, "step \(step): encode→decode round trip changed the layout")
            layout = decoded
        }
    }
}
