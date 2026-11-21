import AppKit
import StareCore

/// Owns the live screen frames that blur marks paint (T5/S3, live blur).
///
/// A blur mark must show what is on the screen *now*, so while one is visible
/// the source refreshes the latest frame per display on a slow timer with
/// `SCScreenshotManager`: a continuous `SCStream` would be overkill, and the
/// one-shot path in `CaptureService` is already proven. Captures run at half
/// the display's pixel size, because a blur destroys the detail anyway.
///
/// All state lives on the main thread, like the rest of the overlay. The async
/// capture never blocks the main thread (no semaphore bridge on the timer
/// path), and when a capture is still in flight the next tick drops the frame
/// instead of queueing it.
///
/// `@unchecked Sendable` is the honest contract here: the state is confined to
/// the main thread (timer, `wake`, `stop`, and the main-queue hop after each
/// capture), and only the immutable capture closure crosses isolation.
final class LiveFrameSource: @unchecked Sendable {
    /// Blur refresh cadence: enough to track what moves under the mark, cheap
    /// enough to never compete with the drawing itself.
    static let framesPerSecond: Double = 6
    /// Blur destroys detail, so half the display pixels are plenty.
    static let downscale: CGFloat = 0.5

    /// Fetches one frame for a display at the given downscale. Injectable so
    /// the self test can feed a synthetic frame through the real path.
    typealias FrameCapture = @Sendable (CGDirectDisplayID, CGFloat) async throws -> CGImage

    /// Called on the main thread after a new frame lands on a display.
    var onFrame: ((CGDirectDisplayID) -> Void)?
    /// Which displays currently need frames, asked on the main thread: the
    /// controller turns this into "canvases whose session has a blur mark".
    var displaysNeedingFrames: () -> [CGDirectDisplayID] = { [] }

    private let capture: FrameCapture
    private var frames: [CGDirectDisplayID: CGImage] = [:]
    private var inFlight: Set<CGDirectDisplayID> = []
    private var timer: Timer?

    init(
        capture: @escaping FrameCapture = { displayID, downscale in
            try await CaptureService().captureDisplay(displayID, downscale: downscale)
        }
    ) {
        self.capture = capture
    }

    deinit {
        timer?.invalidate()
    }

    /// The latest frame captured for a display, nil until the first one lands.
    func frame(for displayID: CGDirectDisplayID) -> CGImage? {
        frames[displayID]
    }

    /// Re-evaluates interest right away. Starts the refresh timer and fetches
    /// a first frame when some display needs one; stops everything (dropping
    /// stale frames) when the last blur mark is gone. This is called whenever
    /// marks change anywhere, so it is cheap when nothing is interested.
    func wake() {
        let wanted = Set(displaysNeedingFrames())
        guard !wanted.isEmpty else {
            stop()
            return
        }
        // Only blur marks ever paint a frame, so a display that lost its marks
        // must not keep a stale one around: prune before the next paint.
        frames = frames.filter { wanted.contains($0.key) }
        for displayID in wanted {
            fetchFrame(for: displayID)
        }
        if timer == nil {
            timer = Timer.scheduledTimer(
                withTimeInterval: 1.0 / Self.framesPerSecond,
                repeats: true
            ) { [weak self] _ in
                self?.wake()
            }
        }
    }

    /// No interest anymore: deactivate, clearAll, or the canvases went away.
    func stop() {
        timer?.invalidate()
        timer = nil
        frames.removeAll()
        inFlight.removeAll()
    }

    private func fetchFrame(for displayID: CGDirectDisplayID) {
        // Drop, never queue: a frame that lands late is already stale.
        guard !inFlight.contains(displayID) else { return }
        inFlight.insert(displayID)
        let capture = self.capture
        let downscale = Self.downscale
        Task.detached(priority: .utility) {
            let image = try? await capture(displayID, downscale)
            DispatchQueue.main.async {
                self.inFlight.remove(displayID)
                guard let image else { return }
                self.frames[displayID] = image
                self.onFrame?(displayID)
            }
        }
    }
}
