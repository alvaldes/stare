/// Lifecycle of the frozen frame an area drag runs on (S11, T2b slice A).
///
/// The instant `⇧S` arms the area drag, Stare captures its own one-shot frame
/// of that display (Screen Recording, Stare's windows excluded) and the drag
/// runs on it: what the user is framing cannot change under them while they
/// choose. The lifecycle is pure logic here — the frame image and the AppKit
/// glue live in the app layer (`OverlayView` paints it as the drag's base and
/// sources blur marks from it; `OverlayController` captures it once and
/// composes the area capture over it).
///
/// Release contract: the base never outlives the drag. It is released on
/// capture, on a stray click, on `Esc` (the drag cancel), on leaving the
/// overlay (the canvases' clear) and on deactivation, and a frame that lands
/// after its drag already ended is stale and must never paint.
public struct AreaCaptureFrameState: Equatable {
    public enum Phase: Equatable {
        /// No drag, no frame.
        case idle
        /// The drag started and a frame was requested; it has not landed yet.
        /// The overlay keeps painting live content until the frame lands, so
        /// a failed capture (no Screen Recording, unavailable display) can
        /// never leave the drag waiting on a base that will not come.
        case pending
        /// The frame landed: it is the drag's base until the drag ends.
        case frozen
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    /// The area drag started and a frame was requested. Always moves to
    /// `pending`: a new drag supersedes anything left over, including a
    /// still-frozen frame from before, which must not become the new drag's
    /// base.
    public mutating func begin() {
        phase = .pending
    }

    /// The requested frame landed and becomes the drag's base. Only a
    /// `pending` drag accepts it — a frame that lands after the drag already
    /// ended is stale. Returns whether the state changed.
    @discardableResult
    public mutating func land() -> Bool {
        guard phase == .pending else { return false }
        phase = .frozen
        return true
    }

    /// The drag ended — capture, stray click, `Esc`, leaving the overlay,
    /// deactivation — and the frozen base is released. `idle` stays `idle`.
    /// Returns whether the state changed.
    @discardableResult
    public mutating func release() -> Bool {
        guard phase != .idle else { return false }
        phase = .idle
        return true
    }
}
