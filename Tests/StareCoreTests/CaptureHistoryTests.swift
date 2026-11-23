import CoreGraphics
import XCTest
@testable import StareCore

/// The session capture history (T3/S12): the last captures this session made
/// stay reachable, each one the composed image the live session delivered —
/// the same image the capture card hands the editor. In memory only: nothing
/// is persisted, nothing is written to disk, so an app quit is the clear.
final class CaptureHistoryStoreTests: XCTestCase {

    private func solidImage(_ width: Int, _ height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: Recording

    func testTheHistoryStartsEmpty() {
        XCTAssertEqual(CaptureHistory(capacity: 3).entries, [])
    }

    func testRecordingPrependsTheNewestCapture() throws {
        let history = CaptureHistory(capacity: 3)
        let first = try XCTUnwrap(solidImage(10, 10))
        let second = try XCTUnwrap(solidImage(20, 10))
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)

        history.record(first, at: firstDate)
        history.record(second, at: secondDate)

        XCTAssertEqual(history.entries.count, 2)
        // Newest first: the history lists itself the way the pane shows it.
        XCTAssertEqual(history.entries.map(\.image.width), [20, 10])
        XCTAssertEqual(history.entries[0].date, secondDate)
        XCTAssertEqual(history.entries[1].date, firstDate)
    }

    func testOnlyTheLastNCapturesStayRemembered() throws {
        let history = CaptureHistory(capacity: 2)
        for index in 1...3 {
            history.record(try XCTUnwrap(solidImage(10 * index, 10)), at: Date(timeIntervalSince1970: TimeInterval(index)))
        }

        // Two of three: the newest two stayed, the oldest capture left.
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertEqual(history.entries.map(\.image.width), [30, 20])
    }

    func testTheRememberedCaptureIsTheComposedImageItself() throws {
        let history = CaptureHistory(capacity: 2)
        let composed = try XCTUnwrap(solidImage(10, 10))

        history.record(composed, at: Date())

        // Identity, not a copy: the card opens this very image, and a
        // recomposition could wait in marks the live session no longer holds.
        XCTAssertTrue(history.entries[0].image === composed)
    }

    func testEachRecordMakesANewIdentifiableEntry() throws {
        let history = CaptureHistory(capacity: 2)
        history.record(try XCTUnwrap(solidImage(10, 10)), at: Date())
        history.record(try XCTUnwrap(solidImage(20, 10)), at: Date())

        XCTAssertEqual(Set(history.entries.map(\.id)).count, 2)
    }

    // MARK: Clearing

    func testClearForgetsEveryCaptureTheSessionMade() throws {
        let history = CaptureHistory(capacity: 3)
        history.record(try XCTUnwrap(solidImage(10, 10)), at: Date())
        history.record(try XCTUnwrap(solidImage(20, 10)), at: Date())

        history.clear()

        XCTAssertEqual(history.entries, [])
        // And the history keeps working after the clear: a memory store that
        // cannot accept again would strand the next captures.
        history.record(try XCTUnwrap(solidImage(5, 5)), at: Date())
        XCTAssertEqual(history.entries.count, 1)
    }

}
