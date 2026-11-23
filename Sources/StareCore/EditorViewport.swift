import CoreGraphics
import Foundation

/// The capture editor's viewport (S16/T9): zoom and pan over a still capture,
/// as a pure value in StareCore the way `BoardTransform` is for the board —
/// the canvas (`CaptureEditorCanvas`) is only a view over it.
///
/// The state is two numbers:
///
/// - `zoom` scales the capture's fitted display about a view point. The
///   anchoring rule is the app's one (S1/S5 on the board): the fit point
///   under the anchor stays under the anchor, so a mark visible under the
///   pointer before the zoom is still there after it.
/// - `pan` shifts the scaled result in view points, content under the
///   pointer following the pointer one to one.
///
/// The clamp keeps the image in sight in every state:
///
/// - An axis the image **covers** (the scaled image is at least as long as
///   the viewport) can slide freely but can never open a gap with the
///   viewport edge: one of the image's edges always stays in the window.
/// - An axis the image does **not** cover keeps the image entirely inside
///   the viewport, so a corner can never be panned out of sight either.
///
/// At the fit (zoom 1) both rules reduce to the fitted placement, so the
/// identity viewport is a fixed point of zoom, pan and clamp — what ⌘0
/// returns to. The zoom range starts at the fit because the fitted view
/// already shows the whole capture: with zoom < 1 the editor would only
/// shrink the picture inside its own window.
public struct EditorViewport: Equatable, Sendable {
    /// The zoom range: 1 is the fitted fit, 8 is close enough to annotate a
    /// fine detail. ⌘0 returns to 1.
    public static let minZoom: CGFloat = 1
    public static let maxZoom: CGFloat = 8
    /// One ⌘+ / ⌘− press moves the zoom by the board's step, so zoom feels
    /// the same on both surfaces.
    public static let zoomStep = BoardTransform.zoomStep

    public static let identity = EditorViewport()

    public var zoom: CGFloat
    public var pan: CGSize

    public init(zoom: CGFloat = 1, pan: CGSize = .zero) {
        self.zoom = zoom
        self.pan = pan
    }

    // MARK: - Mapping

    /// The rect the content occupies with this viewport inside `canvas`:
    /// the fitted rect scaled about its own top-left corner, shifted by
    /// `pan`, then clamped so the image cannot be panned out of sight (S16).
    /// Degenerate geometry (a zero fit or canvas, a non-finite zoom) leaves
    /// the fit untouched.
    public func displayRect(fit: CGRect, canvas: CGRect) -> CGRect {
        guard fit.width > 0, fit.height > 0, canvas.width > 0, canvas.height > 0, zoom.isFinite, zoom > 0 else {
            return fit
        }
        let scaled = CGSize(width: fit.width * zoom, height: fit.height * zoom)
        return CGRect(
            origin: CGPoint(
                x: Self.clampedAxis(
                    fit.minX + pan.width, content: scaled.width,
                    canvasMin: canvas.minX, canvasLength: canvas.width),
                y: Self.clampedAxis(
                    fit.minY + pan.height, content: scaled.height,
                    canvasMin: canvas.minY, canvasLength: canvas.height)
            ),
            size: scaled
        )
    }

    /// The view point a fit point shows at this viewport.
    public func viewPoint(fromFit point: CGPoint, fit: CGRect, canvas: CGRect) -> CGPoint {
        let origin = displayRect(fit: fit, canvas: canvas).origin
        return CGPoint(
            x: origin.x + (point.x - fit.minX) * zoom,
            y: origin.y + (point.y - fit.minY) * zoom
        )
    }

    /// The fit point a view point shows at this viewport — what a gesture at
    /// that screen position acts on, and the anchor's answer at any zoom.
    public func fitPoint(fromView point: CGPoint, fit: CGRect, canvas: CGRect) -> CGPoint {
        let origin = displayRect(fit: fit, canvas: canvas).origin
        guard zoom > 0, zoom.isFinite else { return point }
        return CGPoint(
            x: fit.minX + (point.x - origin.x) / zoom,
            y: fit.minY + (point.y - origin.y) / zoom
        )
    }

    // MARK: - Transitions

    /// Zooms to `target` (clamped into the zoom range) anchored at a view
    /// point: the fit point under the anchor is still shown at the anchor
    /// after the zoom, before the clamp — a clamp at the viewport edge may
    /// then shift the view, exactly like every zoom that reaches a border.
    /// A target that changes nothing (including one below the minimum from a
    /// fit, or beyond the ceiling from the ceiling) returns the viewport
    /// itself.
    public func zoomed(to target: CGFloat, anchoredAt anchor: CGPoint, fit: CGRect, canvas: CGRect) -> EditorViewport {
        let destination = min(max(target, Self.minZoom), Self.maxZoom)
        guard destination != zoom,
            fit.width > 0, fit.height > 0,
            canvas.width > 0, canvas.height > 0
        else { return self }
        // The fit point under the anchor relative to the fit's top-left
        // corner must stay at the same screen offset: view(rel) = anchor.
        let rel = CGSize(
            width: (anchor.x - fit.minX - pan.width) / zoom,
            height: (anchor.y - fit.minY - pan.height) / zoom
        )
        var result = EditorViewport(
            zoom: destination,
            pan: CGSize(
                width: anchor.x - fit.minX - rel.width * destination,
                height: anchor.y - fit.minY - rel.height * destination
            )
        )
        return result.clamped(fit: fit, canvas: canvas)
    }

    /// One multiplicative zoom step (⌘+, ⌘−, ⌘ + scroll), anchored like
    /// every other zoom.
    public func zoomed(byStep step: CGFloat, anchoredAt anchor: CGPoint, fit: CGRect, canvas: CGRect) -> EditorViewport {
        zoomed(to: zoom * step, anchoredAt: anchor, fit: fit, canvas: canvas)
    }

    /// Pans by a view-point delta (content follows the pointer), clamped.
    public func panned(by delta: CGSize, fit: CGRect, canvas: CGRect) -> EditorViewport {
        var result = self
        result.pan = CGSize(width: pan.width + delta.width, height: pan.height + delta.height)
        return result.clamped(fit: fit, canvas: canvas)
    }

    /// The viewport with its pan clamped; the zoom never changes here.
    public func clamped(fit: CGRect, canvas: CGRect) -> EditorViewport {
        var result = self
        result.pan = CGSize(
            width: effectiveX(fit: fit, canvas: canvas) - fit.minX,
            height: effectiveY(fit: fit, canvas: canvas) - fit.minY
        )
        return result
    }

    /// The clamped top of the image's x / y axis in view coordinates.
    private func effectiveX(fit: CGRect, canvas: CGRect) -> CGFloat {
        guard canvas.width > 0, canvas.height > 0, fit.width > 0, fit.height > 0, zoom.isFinite, zoom > 0 else {
            return fit.minX
        }
        return Self.clampedAxis(
            fit.minX + pan.width, content: fit.width * zoom,
            canvasMin: canvas.minX, canvasLength: canvas.width)
    }

    private func effectiveY(fit: CGRect, canvas: CGRect) -> CGFloat {
        guard canvas.width > 0, canvas.height > 0, fit.width > 0, fit.height > 0, zoom.isFinite, zoom > 0 else {
            return fit.minY
        }
        return Self.clampedAxis(
            fit.minY + pan.height, content: fit.height * zoom,
            canvasMin: canvas.minY, canvasLength: canvas.height)
    }

    /// The clamps of one axis. A covered axis (content at least as long as
    /// the viewport) keeps an edge glued to the viewport: its origin may
    /// slide between `canvasMax − content` and `canvasMin`, never opening a
    /// gap. An uncovered axis keeps the content fully inside: its origin may
    /// slide between `canvasMin` and `canvasMax − content`. A length that
    /// exactly equals the viewport's satisfies both with the single fixed
    /// point `canvasMin`, which is why the fit is a fixed point of clamping.
    private static func clampedAxis(
        _ origin: CGFloat, content: CGFloat, canvasMin: CGFloat, canvasLength: CGFloat
    ) -> CGFloat {
        let canvasMax = canvasMin + canvasLength
        if content >= canvasLength {
            return min(max(origin, canvasMax - content), canvasMin)
        }
        return min(max(origin, canvasMin), canvasMax - content)
    }
}

/// The scroll wheel's pan-or-zoom **gate** (S16/T9, review of
/// `feat/capture-extras`): what one scroll event does when it reaches the
/// capture editor — pan, zoom, or nothing. It sits next to the viewport its
/// pan feeds and keeps the whole decision out of the editor so the rules are
/// pinneable without a window, the same discipline `ScrollZoom.Gesture` set
/// for the zoom itself. The gate only routes: what a ⌘ + scroll event does
/// inside the zoom stays that gesture state machine's business (direction
/// lock phases, its own momentum rejection) — one zoom state machine, never
/// a second one.
///
/// Three rules, all the gate's own:
///
/// - **Momentum rejection, matched to the zoom's.** An event with
///   `momentumPhase != .none` belongs to no live gesture — `ScrollZoom.Gesture`
///   says exactly that for zooming — and it says so for panning too. Every
///   momentum event arrives *after* a scroll stream's own `.ended`, which is
///   what makes the zoom's tail the reviewed bug: the gesture was already
///   torn down, no ⌘ was held, and raw feeding kicked the viewport after the
///   zoom had finished. The same rule keeps a plain scroll's flick from
///   coasting the content past where the finger left it.
/// - **Zoom routing.** With ⌘ held the event belongs to the zoom gesture;
///   without ⌘ while the gesture still holds, it is the gesture's wind-down
///   (⌘ released mid-gesture, or its closing phases) and pans nothing.
/// - **Felt direction.** Pan deltas arrive in AppKit's content-directed
///   numbering, which under natural scrolling (`isDirectionInvertedFromDevice`)
///   is the opposite of the direction the user feels. The felt delta negates
///   the raw one there, so the content follows the finger on every device:
///   an inverted one pans the same felt direction as a device without the
///   setting, and whoever keeps the default keeps the direction this editor
///   has always panned in.
public enum ScrollPan: Sendable {
    /// One scroll event reduced to what the gate decides on. `phase` rides
    /// with the zoom branch (`ScrollZoom.Event` takes it) and with the
    /// handler's closing rule; the gate itself keys off the momentum phase,
    /// which is exactly the "momentum that follows a `.ended`" signal.
    public struct Event: Equatable, Sendable {
        /// `NSEvent.scrollingDeltaX` as the device reported it.
        public var deltaX: CGFloat
        /// `NSEvent.scrollingDeltaY` as the device reported it.
        public var deltaY: CGFloat
        /// `NSEvent.isDirectionInvertedFromDevice` — natural scrolling.
        public var isDirectionInvertedFromDevice: Bool
        /// `NSEvent.momentumPhase`.
        public var momentumPhase: ScrollZoom.MomentumPhase
        /// Whether the zoom modifier (⌘) was down for this event.
        public var commandHeld: Bool
        /// The editor still holds a ⌘ + scroll zoom gesture when the event
        /// arrives — the state a wind-down event ends.
        public var zoomGestureLive: Bool

        public init(
            deltaX: CGFloat = 0,
            deltaY: CGFloat = 0,
            isDirectionInvertedFromDevice: Bool = false,
            momentumPhase: ScrollZoom.MomentumPhase = .none,
            commandHeld: Bool = false,
            zoomGestureLive: Bool = false
        ) {
            self.deltaX = deltaX
            self.deltaY = deltaY
            self.isDirectionInvertedFromDevice = isDirectionInvertedFromDevice
            self.momentumPhase = momentumPhase
            self.commandHeld = commandHeld
            self.zoomGestureLive = zoomGestureLive
        }
    }

    /// What the event does to the viewport: pan by the felt delta, feed the
    /// zoom gesture, or move nothing.
    public enum Decision: Equatable, Sendable {
        case pan(delta: CGSize)
        case zoom
        case ignore
    }

    /// Decides what `event` does to the viewport (S16/T9).
    public static func decide(for event: Event) -> Decision {
        // Momentum belongs to no live gesture: reject it before touching any
        // state, exactly as `ScrollZoom.Gesture` does for the zoom — the
        // flick's tail after the zoom's own `.ended` must not kick the
        // viewport, and it must not coast the pan either.
        guard event.momentumPhase == .none else { return .ignore }
        if event.commandHeld { return .zoom }
        if event.zoomGestureLive { return .ignore }
        // The deltas arrive in AppKit's content-directed numbering, which is
        // the opposite of the felt direction when natural scrolling is on:
        // negate there, so the content follows the finger on every device.
        let invert: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        return .pan(delta: CGSize(width: event.deltaX * invert, height: event.deltaY * invert))
    }
}
