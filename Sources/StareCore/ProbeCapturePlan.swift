import CoreGraphics

/// Runs the Screen Recording probe's capture attempts and remembers which size
/// worked — per display, and only while it keeps working.
///
/// The permission refresh calls the probe about once a second, and a display
/// whose reduced size is rejected by ScreenCaptureKit would otherwise pay for a
/// second, full-resolution capture on every tick. `run` therefore records the
/// size that succeeded and asks `ProbeCaptureSize` for the attempt list, which
/// yields exactly that one size from then on.
///
/// Two rules keep the memory from becoming a trap, both from a native review:
/// the memory is keyed by display, because the probe is per display and a
/// factor that works on one says nothing about another; and a remembered size
/// that fails is forgotten on the spot, with the sizes it displaced tried in the
/// same pass, so one transient failure cannot leave the probe answering
/// "cannot capture" forever.
///
/// The capture is injected so this rule has a test: the code that performs the
/// capture needs AppKit and ScreenCaptureKit and lives in the app target, which
/// has no runner.
public struct ProbeCapturePlan {
    /// The factor the last successful probe answered with, per display.
    public private(set) var lastSucceeded: [CGDirectDisplayID: CGFloat] = [:]

    public init() {}

    /// Tries the sizes `ProbeCaptureSize` allows for this display, in order.
    ///
    /// - Parameters:
    ///   - displayID: the display being probed; the memory is keyed by it.
    ///   - displayDownscale: the factor for that display.
    ///   - capture: one capture attempt; returns the failure, or `nil` when the
    ///     capture succeeded.
    /// - Returns: whether any attempt captured.
    @discardableResult
    public mutating func run(
        displayID: CGDirectDisplayID,
        displayDownscale: CGFloat,
        capture: (CGFloat) -> Error?
    ) -> Bool {
        let remembered = lastSucceeded[displayID]

        for downscale in ProbeCaptureSize.attempts(
            displayDownscale: displayDownscale,
            lastSucceeded: remembered
        ) {
            if capture(downscale) == nil {
                lastSucceeded[displayID] = downscale
                return true
            }
        }

        // Nothing worked. Forget the remembered size so the next probe starts
        // over, and finish this pass with the sizes it had displaced: a
        // transient failure must not leave the probe stuck.
        lastSucceeded[displayID] = nil
        guard let remembered else { return false }

        for downscale in ProbeCaptureSize.attempts(
            displayDownscale: displayDownscale,
            lastSucceeded: nil
        ) where downscale != remembered {
            if capture(downscale) == nil {
                lastSucceeded[displayID] = downscale
                return true
            }
        }
        return false
    }
}
