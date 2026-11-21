import CoreGraphics
import Foundation

/// Click pulse for the pointer highlight: while pointer mode is running, a
/// click makes the highlight grow briefly and settle back, so a click reads
/// as a click instead of a just a moving dot.
///
/// The curve is a pure function of the time elapsed since the click, with no
/// AppKit state at all: it is testable headless and can never stick, because
/// past the pulse duration the scale is 1 again and stays there until a new
/// click starts a new pulse. A click during a running pulse restarts the
/// curve from its new anchor.
public struct PointerPulse: Equatable {
    /// Click instant to the peak of the growth.
    public let riseDuration: TimeInterval
    /// Peak down to the settle dip.
    public let dipDuration: TimeInterval
    /// Dip back to rest. Together with the two phases above this is the whole
    /// pulse: `scale` is 1 again from `duration` onwards.
    public let settleDuration: TimeInterval
    /// How much bigger the highlight is at the peak (1.35 reads as a pulse,
    /// not a jump).
    public let peakScale: CGFloat
    /// How much smaller the highlight dips just before settling, which reads
    /// as the ring landing rather than shrinking linearly.
    public let dipScale: CGFloat
    /// Timestamp of the click being pulsed; nil while resting.
    public private(set) var startedAt: TimeInterval?

    public init(
        riseDuration: TimeInterval = 0.09,
        dipDuration: TimeInterval = 0.08,
        settleDuration: TimeInterval = 0.28,
        peakScale: CGFloat = 1.35,
        dipScale: CGFloat = 0.94
    ) {
        self.riseDuration = riseDuration
        self.dipDuration = dipDuration
        self.settleDuration = settleDuration
        self.peakScale = peakScale
        self.dipScale = dipScale
    }

    /// Total time a click keeps pulsing, from the click instant to rest.
    public var duration: TimeInterval {
        riseDuration + dipDuration + settleDuration
    }

    /// Starts or restarts the pulse at `now`.
    public mutating func start(at now: TimeInterval) {
        startedAt = now
    }

    /// Whether a pulse is still running at `now`.
    public func isPulsing(at now: TimeInterval) -> Bool {
        guard let startedAt else { return false }
        return now >= startedAt && now < startedAt + duration
    }

    /// Scale multiplier at `now`. Exactly 1 at the click instant, `peakScale`
    /// at the end of the rise, 1 again from `duration` on, and 1 whenever no
    /// click started a pulse.
    public func scale(at now: TimeInterval) -> CGFloat {
        guard let startedAt else { return 1 }
        let elapsed = now - startedAt
        guard elapsed >= 0 else { return 1 }

        if elapsed <= riseDuration {
            let progress = riseDuration > 0 ? CGFloat(elapsed / riseDuration) : 1
            return 1 + (peakScale - 1) * Self.easeOutCubic(progress)
        }

        let dipEnd = riseDuration + dipDuration
        if elapsed <= dipEnd {
            let progress = dipDuration > 0 ? CGFloat((elapsed - riseDuration) / dipDuration) : 1
            return peakScale + (dipScale - peakScale) * Self.easeInOutSine(progress)
        }

        let end = dipEnd + settleDuration
        guard elapsed < end, settleDuration > 0 else { return 1 }
        let progress = CGFloat((elapsed - dipEnd) / settleDuration)
        return dipScale + (1 - dipScale) * Self.easeInOutSine(progress)
    }

    /// Fast attack, soft landing at the peak.
    private static func easeOutCubic(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    /// Smooth there-and-back for the settle phases.
    private static func easeInOutSine(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return (1 - cos(.pi * clamped)) / 2
    }
}
