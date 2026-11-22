import Foundation

/// The Screen Recording probe's in-flight guard.
///
/// The permission refresh calls the probe about once a second, and the probe's
/// wait is bounded by `ProbeCaptureSize.timeout` — but the capture it starts is
/// not cancelled when that wait ends (cancellation is cooperative and does not
/// abort the screenshot), so a persistently stalled ScreenCaptureKit call
/// would accumulate one orphaned capture per refresh tick while the caller has
/// already returned.
///
/// The guard's lifecycle, one probe pass at a time:
///
/// - `begin()` starts a pass and hands back its `Pass`, or answers with the
///   last known answer when a pass is still in flight — the caller returns
///   that instead of launching another capture.
/// - When the pass's bounded wait expires, `timeOut(_:answer:)` records what
///   the caller answered while keeping the pass in flight: the capture it
///   abandoned is still running, so the next refresh must repeat the answer.
/// - When a pass's capture actually completes, `finish(_:answer:)` records the
///   real answer and frees the next probe. A call for a pass a newer probe
///   displaced is ignored, so a late completion can neither free nor rewrite a
///   probe that already moved on.
/// - The hold on an abandoned pass is bounded by `rearmAfter`. A capture that
///   never completes would otherwise keep the guard busy forever and the probe
///   answering `false` until the app restarts, so once the window elapses the
///   next `begin()` retires the stalled pass and starts a fresh probe, whose
///   result is the answer from then on.
///
/// While a pass is in flight with no recorded answer yet (the very first
/// probe), a caller that asks gets `false`: nothing has been captured, so
/// nothing may be claimed.
///
/// The capture itself needs AppKit and ScreenCaptureKit and lives in the app
/// target, which has no runner; this pure rule lives here so it has a test.
public struct ProbeInFlight {
    /// One started probe pass. `finish` and `timeOut` only apply to the pass
    /// they name, so a completion from an abandoned pass cannot free a newer
    /// probe's guard.
    public struct Pass: Equatable {
        fileprivate let generation: Int
    }

    /// What `begin()` told the caller.
    public enum Outcome: Equatable {
        /// Launch the probe; hold this pass and hand it back when the capture
        /// completes or the wait expires.
        case proceed(Pass)
        /// A probe is already in flight; return this answer instead of
        /// launching another capture.
        case answer(Bool)
    }

    /// How long an abandoned pass may keep the guard busy before the next
    /// refresh is allowed to start a fresh probe.
    ///
    /// The hold exists because an abandoned capture is still running and one
    /// capture per refresh tick is exactly what the guard prevents. It cannot
    /// be unbounded, though: cancellation is cooperative and does not abort a
    /// stalled ScreenCaptureKit call, so a capture that never completes would
    /// leave the guard busy forever and the permission UI claiming "cannot
    /// capture" until the app restarted. Re-arming trades a bounded trickle of
    /// captures — one per window, not one per tick — for letting the probe
    /// recover on its own.
    public static let rearmAfter: TimeInterval = 10

    private var nextGeneration = 0
    private var activePass: Pass?

    /// When the active pass's bounded wait expired, if it did: the instant its
    /// re-arm window starts counting.
    private var abandonedAt: Date?

    /// What the last recorded probe pass answered, if any.
    public private(set) var lastAnswer: Bool?

    /// Whether a probe pass is running and has not finished yet.
    public var isBusy: Bool { activePass != nil }

    public init() {}

    /// Marks a probe pass as starting.
    ///
    /// `now` is a parameter because this rule has no clock of its own and its
    /// window must be testable without waiting ten seconds.
    public mutating func begin(now: Date = Date()) -> Outcome {
        if activePass != nil {
            let heldFor = abandonedAt.map { now.timeIntervalSince($0) } ?? 0
            if heldFor < Self.rearmAfter {
                return .answer(lastAnswer ?? false)
            }
            // The window elapsed: retire the stalled pass. Its abandoned
            // capture is gone from the guard's accounting, so its late
            // completion can no longer free or rewrite the fresh probe.
            activePass = nil
            abandonedAt = nil
        }
        nextGeneration += 1
        let pass = Pass(generation: nextGeneration)
        activePass = pass
        return .proceed(pass)
    }

    /// The bounded wait expired for `pass`: records the answer the caller
    /// returned while keeping the pass in flight, because the capture it
    /// abandoned is still running and the next refresh must repeat this answer
    /// instead of starting another capture — for at most `rearmAfter`, so a
    /// capture that never completes cannot wedge the probe until a restart.
    public mutating func timeOut(_ pass: Pass, answer: Bool, now: Date = Date()) {
        guard pass == activePass else { return }
        lastAnswer = answer
        abandonedAt = now
    }

    /// The capture behind `pass` actually completed: records the real answer
    /// and frees the next probe. Ignored for a pass a newer probe displaced.
    public mutating func finish(_ pass: Pass, answer: Bool) {
        guard pass == activePass else { return }
        lastAnswer = answer
        activePass = nil
        abandonedAt = nil
    }
}
