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

    private var nextGeneration = 0
    private var activePass: Pass?

    /// What the last recorded probe pass answered, if any.
    public private(set) var lastAnswer: Bool?

    /// Whether a probe pass is running and has not finished yet.
    public var isBusy: Bool { activePass != nil }

    public init() {}

    /// Marks a probe pass as starting.
    public mutating func begin() -> Outcome {
        if activePass != nil {
            return .answer(lastAnswer ?? false)
        }
        nextGeneration += 1
        let pass = Pass(generation: nextGeneration)
        activePass = pass
        return .proceed(pass)
    }

    /// The bounded wait expired for `pass`: records the answer the caller
    /// returned while keeping the pass in flight, because the capture it
    /// abandoned is still running and the next refresh must repeat this answer
    /// instead of starting another capture.
    public mutating func timeOut(_ pass: Pass, answer: Bool) {
        guard pass == activePass else { return }
        lastAnswer = answer
    }

    /// The capture behind `pass` actually completed: records the real answer
    /// and frees the next probe. Ignored for a pass a newer probe displaced.
    public mutating func finish(_ pass: Pass, answer: Bool) {
        guard pass == activePass else { return }
        lastAnswer = answer
        activePass = nil
    }
}
