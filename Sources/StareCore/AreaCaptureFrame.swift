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
    /// Which armed drag a frame belongs to. Each `begin` mints a fresh one:
    /// a frame that lands after its own drag already ended — or after `Esc`
    /// and a re-arm while its capture was still in flight — carries a token
    /// the state no longer recognises and must never become the new drag's
    /// base.
    public struct Token: Equatable {
        let rawValue: Int
    }

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
    /// The pending drag's token, nil outside `.pending`.
    public private(set) var pendingToken: Token?
    /// The identity minted by the last `begin`, bumped on each arm.
    private var generation = 0

    public init() {}

    /// The area drag started and a frame was requested. Always moves to
    /// `pending`: a new drag supersedes anything left over, including a
    /// still-frozen frame from before, which must not become the new drag's
    /// base — its token is minted fresh, so an earlier drag's frame can no
    /// longer land as this drag's base either.
    @discardableResult
    public mutating func begin() -> Token {
        generation += 1
        let token = Token(rawValue: generation)
        phase = .pending
        pendingToken = token
        return token
    }

    /// The requested frame landed and becomes the drag's base. Only the
    /// frame of the still-pending drag accepts — a frame that lands without
    /// its drag's identity, or with a superseded token, is stale. Returns
    /// whether the state changed.
    @discardableResult
    public mutating func land(_ token: Token?) -> Bool {
        guard phase == .pending, let token, token == pendingToken else { return false }
        phase = .frozen
        pendingToken = nil
        return true
    }

    /// The drag ended — capture, stray click, `Esc`, leaving the overlay,
    /// deactivation — and the frozen base is released. `idle` stays `idle`.
    /// Returns whether the state changed.
    @discardableResult
    public mutating func release() -> Bool {
        guard phase != .idle else { return false }
        phase = .idle
        pendingToken = nil
        return true
    }
}
