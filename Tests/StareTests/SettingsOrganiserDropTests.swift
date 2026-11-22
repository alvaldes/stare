import Foundation
import XCTest
@testable import Stare
import StareCore

/// S5: the organiser's drop path hops to the main actor before anything
/// touches `PreferencesModel`. `NSItemProvider.loadObject`'s completion is
/// NOT the main thread, and the pre-fix organiser applied the layout
/// mutation straight from that completion (measured by the independent
/// verifier: `onMain=false`) — a `UserDefaults` write off main, and two
/// quick drops that could read the same draft and lose one. The tests drive
/// the delegates' real payload path (`DropInfo` itself cannot be constructed
/// outside SwiftUI, so the decode-and-deliver seam `performDrop` calls is
/// the public surface the tests fire from a background queue).
final class SettingsOrganiserDropTests: XCTestCase {

    /// Thread-safe witness for where and how drop applications ran.
    private final class DropWitness: @unchecked Sendable {
        private let lock = NSLock()
        private var applications: [(item: ToolbarLayoutItem, onMain: Bool)] = []

        func record(_ item: ToolbarLayoutItem) {
            lock.lock()
            applications.append((item, Thread.isMainThread))
            lock.unlock()
        }

        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return applications.count
        }

        var allOnMain: Bool {
            lock.lock(); defer { lock.unlock() }
            return applications.allSatisfy(\.onMain)
        }

        var items: [ToolbarLayoutItem] {
            lock.lock(); defer { lock.unlock() }
            return applications.map(\.item)
        }
    }

    /// A provider holding an organiser payload, as a drag-start would make.
    private func provider(_ identifier: String) -> NSItemProvider {
        NSItemProvider(object: identifier as NSString)
    }

    // MARK: - The completion's thread (the fact the hop must keep)

    /// Documentation pinned so nobody removes the hop: the completion of
    /// `loadObject(ofClass:)` is not the main thread. If this ever goes
    /// green-in-reverse (AppKit starts delivering on main), the hop is still
    /// correct — but this test then stops being the guard and the finding's
    /// history should be re-measured.
    func testALoadObjectCompletionCallsBackOffTheMainThread() throws {
        let provider = provider("separator")
        let decoded = expectation(description: "payload loaded")
        var onMain = true
        var item: ToolbarLayoutItem?
        provider.loadObject(ofClass: NSString.self) { object, _ in
            onMain = Thread.isMainThread
            item = (object as? String).flatMap(ToolbarLayoutItem.init(identifier:))
            decoded.fulfill()
        }
        wait(for: [decoded], timeout: 10)
        XCTAssertNotNil(item, "the plain-text payload loads and decodes")
        XCTAssertFalse(
            onMain,
            "loadObject's completion is off the main thread — the hop in ToolbarOrganiserHooks.deliverPayload must stay")
    }

    // MARK: - The bar slot delegate's drop path

    /// The verifier's blocker: two drops fired in quick succession from
    /// background threads must BOTH land, and every application must run on
    /// the main actor — that is what makes the read-modify-write of the
    /// draft serial and loss-free.
    func testTwoBarSlotDropsFiredFromABackgroundQueueBothLandOnTheMainActor() async throws {
        let witness = DropWitness()
        let delegate = ToolbarSlotDropDelegate(
            target: .tool(.pen),
            size: CGSize(width: 28, height: 26),
            axisVertical: false
        ) { _, _, payload in
            witness.record(payload)
        }

        let identifiers = ["tool:pen", "tool:eraser"]
        try await Task.detached(priority: .utility) { [delegate] in
            for identifier in identifiers {
                delegate.dropPayload(from: NSItemProvider(object: identifier as NSString), edge: .after)
            }
        }.value

        let deadline = Date().addingTimeInterval(10)
        while witness.count < 2 && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(witness.count, 2, "two quick drops must both apply — neither may be lost")
        XCTAssertEqual(
            Set(witness.items), Set([.tool(.pen), .tool(.eraser)]),
            "both drops' payloads were delivered")
        XCTAssertTrue(witness.allOnMain, "every drop application ran on the main actor")
    }

    // MARK: - The shared payload hop the pool-end delegate uses

    /// The pool end zone's drop (a placed separator coming back off the
    /// bar, a tool landing at the pool's end) runs the same shared hop.
    /// Fired from a background queue exactly like a real drag's completion.
    func testTheSharedPayloadHopDeliversFromABackgroundQueueOnTheMainActor() async throws {
        let witness = DropWitness()

        let providers = [provider("separator"), provider("tool:laser")]
        try await Task.detached(priority: .utility) {
            for item in providers {
                ToolbarOrganiserHooks.deliverPayload(of: item) { payload in
                    witness.record(payload)
                }
            }
        }.value

        let deadline = Date().addingTimeInterval(10)
        while witness.count < 2 && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(witness.count, 2)
        XCTAssertEqual(Set(witness.items), Set([.separator, .tool(.laser)]))
        XCTAssertTrue(witness.allOnMain)
    }
}
