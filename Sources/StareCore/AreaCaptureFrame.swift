/// Lifecycle of the frozen frame an area drag runs on (S11, T2b slice A).
///
/// Stare keeps one frame of each display stocked in the background — taken
/// when the overlay's canvas is built and refreshed after each area capture —
/// so a `⇧S` drag freezes on a frame that already exists: a frame asked for by
/// the same gesture that needs it would have to win a capture whose latency is
/// usually longer than the drag itself. Only when nothing is stocked (the
/// stock capture failed, the session was cleared, or `⇧S` arrives inside a
/// still-flying first capture) does the drag ask for its own frame as it
/// always did — the `pending` path below — and a failed ask leaves the drag
/// running live. The lifecycle is pure logic here; the frame imagery, the
/// stocked copy and the AppKit glue live in the app layer (`OverlayView`
/// paints it as the drag's base and sources blur marks from it;
/// `OverlayController` captures it and composes the area capture over it).
///
/// Release contract: the drag's own base never outlives the drag. It is
/// released on capture, on a stray click, on `Esc` (the drag cancel), and a
/// frame that lands after its drag already ended is stale and must never
/// paint. The stocked frame is not the drag's base until a drag arms on it:
/// releasing a drag keeps the stock, while the overlay's `clear` (the
/// leaving-the-overlay path, also the deactivation path) drops the stock so
/// the next session starts clean — nothing stale carries over.
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
