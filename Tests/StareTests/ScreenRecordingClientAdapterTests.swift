import AppKit
import XCTest
@testable import Stare

/// A capture service the probe can run against headlessly: it records the
/// attempts it sees and can hang a capture the way a stalled ScreenCaptureKit
/// call does, so the adapter's wiring — `ProbeCapturePlan` driving the sizes
/// and `ProbeInFlight` guarding the refresh — is observable from a test.
final class FakeProbeCaptureService: ProbeCaptureService, @unchecked Sendable {
    private let lock = NSLock()
    private var _hasPermission = true
    private var _attempted: [CGFloat] = []
    private var _hungCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    /// Captures at a reduced size are rejected, the way ScreenCaptureKit
    /// rejects a configuration it does not like; full size is left to `hangsFullSize`.
    var failsReduced = true

    /// Full-size captures suspend until `releaseHangingCapture()` — a stalled
    /// ScreenCaptureKit call, the one whose bounded wait abandons it.
    var hangsFullSize = false

    var hasPermission: Bool {
        get { lock.withLock { _hasPermission } }
        set { lock.withLock { _hasPermission = newValue } }
    }

    /// The downscale factors the probe asked for, in order.
    var attempted: [CGFloat] { lock.withLock { _attempted } }

    /// How many captures actually entered the hang.
    var hungCount: Int { lock.withLock { _hungCount } }

    private(set) var requestedPermission = 0

    func requestPermission() {
        requestedPermission += 1
    }

    func captureDisplay(_ displayID: CGDirectDisplayID, downscale: CGFloat) async throws -> CGImage {
        lock.withLock { _attempted.append(downscale) }

        if hangsFullSize && downscale <= 1 {
            lock.withLock { _hungCount += 1 }
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                lock.withLock { continuation = c }
            }
        }
        if failsReduced && downscale > 1 {
            throw CaptureError.displayUnavailable
        }
        return Self.image
    }

    func releaseHangingCapture() {
        let released = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let c = continuation
            continuation = nil
            return c
        }
        released?.resume()
    }

    /// A tiny valid image, so a "successful" capture has something to return.
    private static let image: CGImage = {
        let width = 2, height = 2
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }()
}

/// The adapter's wiring, with the capture faked: the first version of the
/// probe's size rule shipped as dead code because nothing could see the loop
/// the adapter ran, so these tests exercise the real `canCapture()` path.
final class ScreenRecordingClientAdapterTests: XCTestCase {
    /// The probe is the production capture path end to end: the reduced size
    /// first, the full-size fallback when the reduced one is rejected, and once
    /// a size works the next probe pays for that one capture only — the wiring
    /// of `ProbeCapturePlan` inside `canCapture()`.
    func testProbeTriesReducedThenFullSizeAndRemembersTheOneThatWorked() {
        let service = FakeProbeCaptureService()
        let client = SystemScreenRecordingClient(captureService: service)

        XCTAssertTrue(client.canCapture())
        let first = service.attempted
        XCTAssertTrue(
            first.count == 2 && first[0] > 1 && first[1] == 1,
            "the reduced size is tried first and the full size is the fallback; got \(first)"
        )

        XCTAssertTrue(client.canCapture())
        XCTAssertEqual(
            service.attempted.last, 1,
            "once a size worked, the next probe pays for one capture at the remembered size"
        )
        XCTAssertEqual(service.attempted.count, 3)
    }

    /// R3-002/R4-3 at the adapter level: the bounded wait does not cancel the
    /// capture, so while the abandoned capture is still in flight the next
    /// refresh repeats the answer instead of starting another orphaned capture
    /// — and once the abandoned capture actually ends, the guard frees and the
    /// probe recovers.
    func testSecondRefreshWhileAProbeIsStillInFlightRepeatsTheAnswerWithoutCapturing() {
        let service = FakeProbeCaptureService()
        service.hangsFullSize = true
        let client = SystemScreenRecordingClient(captureService: service)

        // The first probe hangs on its full-size attempt; the bounded wait
        // expires, so this answers false.
        XCTAssertFalse(client.canCapture())
        XCTAssertEqual(service.hungCount, 1)
        let attemptsAfterFirstProbe = service.attempted.count

        // The abandoned capture is still running: the next refresh must not
        // start another one.
        XCTAssertFalse(client.canCapture())
        XCTAssertEqual(service.hungCount, 1, "a probe still in flight answers again instead of starting another capture")
        XCTAssertEqual(service.attempted.count, attemptsAfterFirstProbe, "no capture was started by the busy refresh")

        // When the abandoned capture actually completes, the pass frees and the
        // next refresh probes again — `true` can only come from a fresh
        // capture, because the cached answer is false.
        service.hangsFullSize = false
        service.releaseHangingCapture()

        let deadline = Date().addingTimeInterval(2)
        var recovered = false
        while !recovered && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            recovered = client.canCapture()
        }

        XCTAssertTrue(recovered, "the pass freed once the abandoned capture ended, and the probe recovered")
        XCTAssertEqual(service.hungCount, 1, "the abandoned capture was the only hung one")
        XCTAssertGreaterThan(service.attempted.count, attemptsAfterFirstProbe, "the recovery was a fresh capture")
    }

    /// `preflight()` and `request()` mirror the same service the capture path
    /// uses, so the onboarding model observes what a real capture runs into.
    func testPreflightMirrorsTheServiceAndRequestAsksIt() {
        let service = FakeProbeCaptureService()
        let client = SystemScreenRecordingClient(captureService: service)

        service.hasPermission = true
        XCTAssertTrue(client.preflight())
        XCTAssertEqual(service.requestedPermission, 0, "preflight never prompts")

        service.hasPermission = false
        XCTAssertFalse(client.preflight())
        XCTAssertFalse(client.request(), "request reports the permission as it is after asking")
        XCTAssertEqual(service.requestedPermission, 1)
    }
}
