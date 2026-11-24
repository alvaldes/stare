import CoreGraphics
import Foundation

/// The one mapping between a board page's space and the view's space
/// (T5/S5): `view = (page − offset) × zoom`. At zoom 1 it reduces to the old
/// translation-only rule (`page = view + offset`), so a page that never zooms
/// keeps its stored points exactly where they were. The mapping lives here,
/// in StareCore, instead of arithmetic spread through the view — the view,
/// the selection chrome and the capture compositor all read it from this one
/// place.
public struct BoardTransform: Equatable, Sendable {
    /// The zoom range: 0.25× reads a page-wide view on any display, 8× is close
    /// enough to draw a fine detail. ⌘0 returns to 1.
    public static let minZoom: CGFloat = 0.25
    public static let maxZoom: CGFloat = 8
    /// One ⌘+ / ⌘− press moves the zoom by this factor.
    public static let zoomStep: CGFloat = 1.25

    public static let identity = BoardTransform(offset: .zero, zoom: 1)

    /// How far the page origin sits from the display's top-left corner, in page
    /// units (the pan offset).
    public var offset: CGSize
    public var zoom: CGFloat

    public init(offset: CGSize = .zero, zoom: CGFloat = 1) {
        self.offset = offset
        self.zoom = zoom
    }

    /// The zoom clamped into the stated range.
    public var clamped: BoardTransform {
        BoardTransform(offset: offset, zoom: min(max(zoom, Self.minZoom), Self.maxZoom))
    }

    /// A zoom to `target` anchored at `anchor`, a **view** point: the page
    /// point under the anchor never moves, so whatever is under the pointer
    /// stays under the pointer. A clamped target that changes nothing returns
    /// the transform itself.
    public func zoomed(to target: CGFloat, anchoredAt anchor: CGPoint) -> BoardTransform {
        let destination = min(max(target, Self.minZoom), Self.maxZoom)
        guard destination != zoom else { return self }
        // page(anchor-before) == page(anchor-after):
        //   anchor/z1 + o1 == anchor/z0 + o0
        let offset = CGSize(
            width: offset.width + anchor.x * (1 / zoom - 1 / destination),
            height: offset.height + anchor.y * (1 / zoom - 1 / destination)
        )
        return BoardTransform(offset: offset, zoom: destination)
    }

    /// A page-space point's place in the view.
    public func point(fromPage point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.width) * zoom, y: (point.y - offset.height) * zoom)
    }

    /// The page-space point under a view point: what a stroke at that screen
    /// position stores.
    public func point(toPage point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / zoom + offset.width, y: point.y / zoom + offset.height)
    }

    /// A page-space rect's place in the view (dirty rects, capture crops).
    public func rect(fromPage rect: CGRect) -> CGRect {
        let origin = point(fromPage: CGPoint(x: rect.minX, y: rect.minY))
        let end = point(fromPage: CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(
            x: min(origin.x, end.x),
            y: min(origin.y, end.y),
            width: abs(end.x - origin.x),
            height: abs(end.y - origin.y)
        )
    }

    /// The page-space rect under a view rect: what a region of the view
    /// covers in page space (culling, grid painting).
    public func rect(toPage rect: CGRect) -> CGRect {
        let origin = point(toPage: CGPoint(x: rect.minX, y: rect.minY))
        let end = point(toPage: CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(
            x: min(origin.x, end.x),
            y: min(origin.y, end.y),
            width: abs(end.x - origin.x),
            height: abs(end.y - origin.y)
        )
    }

    /// A page-space length's size in the view.
    public func length(fromPage length: CGFloat) -> CGFloat {
        length * zoom
    }

    /// A view-space length's size in page space: what a screen-constant size
    /// (handle squares, hit radii) measures in page units.
    public func pageLength(_ length: CGFloat) -> CGFloat {
        length / zoom
    }

    /// The transform a CGContext concatenates so page-space drawing lands in
    /// view space.
    public var cgAffineTransform: CGAffineTransform {
        CGAffineTransform(translationX: -offset.width, y: -offset.height)
            .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
    }

    /// ⌘ + scroll zoom (S1): a zoom step from a scroll event's delta, anchored
    /// at a view point like every other zoom — the same one model of zoom
    /// (`BoardTransform`), never a second state. Without the command
    /// (`isZooming` false) the transform is returned untouched: plain scroll
    /// never changes the zoom.
    public func zoomed(forScrollDelta delta: CGFloat, isZooming: Bool, anchoredAt anchor: CGPoint) -> BoardTransform {
        guard isZooming else { return self }
        return zoomed(to: zoom * ScrollZoom.zoomFactor(forScrollDelta: delta), anchoredAt: anchor)
    }
}

/// ⌘ + scroll zoom (S1): the pure scroll-delta → zoom-step decision, kept in
/// StareCore next to the zoom model it feeds. Scrolling up (positive delta)
/// zooms in, scrolling down zooms out, and the factor is continuous in the
/// delta so trackpad precision scrolling and mouse wheel notches both feel
/// like steps of the same zoom.
public enum ScrollZoom: Sendable {
    /// The accumulated precise-scroll points that amount to one
    /// `BoardTransform.zoomStep`. A mouse wheel notch reports ~10 points, so
    /// one notch lands between one and two keyboard steps; trackpad events
    /// report small fractions and accumulate smoothly.
    public static let pointsPerStep: CGFloat = 8

    /// The multiplicative zoom factor a scroll event's precise delta applies:
    /// `zoomStep ^ (delta / pointsPerStep)`. A zero or non-finite delta changes
    /// nothing (factor 1).
    public static func zoomFactor(forScrollDelta delta: CGFloat) -> CGFloat {
        guard delta.isFinite, delta != 0 else { return 1 }
        return pow(BoardTransform.zoomStep, delta / pointsPerStep)
    }

    /// `NSEvent.Phase` without AppKit (v0.5/S2): the raw values are AppKit's
    /// real ones — a bit set, probed against `NSEvent.Phase` on this machine:
    /// began 1, stationary 2, changed 4, ended 8, cancelled 16, mayBegin 32.
    /// A live trackpad scroll event reports `.changed` (4); the gesture-closing
    /// values are `.ended` (8) and `.cancelled` (16). The view maps AppKit's
    /// numbers straight onto these (same numbering), so a wrong value here
    /// would close the gesture on every event or never close it — the bit
    /// indices this table once carried did exactly that. A synthesized
    /// `CGEvent(scrollWheelEvent2Source:)` maps its
    /// `scrollWheelEventScrollPhase` field 1 → `.began`, 2 → `.changed`,
    /// 4 → `.ended`, 8 → `.cancelled`, and its
    /// `scrollWheelEventMomentumPhase` field 1 → momentum begin,
    /// 2 → momentum continued, 3 → momentum end (probe-verified), which is
    /// what the selftest and hardware-shaped tests drive.
    public enum Phase: Int, Sendable {
        case none = 0
        case began = 1
        case stationary = 2
        case changed = 4
        case ended = 8
        case cancelled = 16
        case mayBegin = 32
    }

    /// `NSEvent.MomentumPhase` without AppKit (v0.5/S2): the momentum phase
    /// shares `NSEvent.Phase`'s bit numbering (probed through
    /// `NSEvent(cgEvent:)` on this machine): begin 1, stationary 2,
    /// continued 4 (the changed bit), end 8 (the ended bit). Every nonzero
    /// value therefore decodes to a named momentum case the gesture rejects;
    /// none of them falls through to `.none`, which would zoom the flick.
    public enum MomentumPhase: Int, Sendable {
        case none = 0
        case begin = 1
        case stationary = 2
        case continued = 4
        case end = 8
    }

    /// One scroll event reduced to the properties the gesture's own state
    /// machine decides on (v0.5/S2): the content-directed delta, the phase
    /// pair that says whether a live gesture exists, and the device's
    /// natural-scrolling preference. Pure values keep StareCore free of AppKit.
    public struct Event: Equatable, Sendable {
        /// `NSEvent.scrollingDeltaY`: content-directed, already normalised
        /// against the device by AppKit.
        public var deltaY: CGFloat
        /// `NSEvent.phase`.
        public var phase: ScrollZoom.Phase
        /// `NSEvent.momentumPhase`.
        public var momentumPhase: ScrollZoom.MomentumPhase

        public init(
            deltaY: CGFloat,
            phase: ScrollZoom.Phase = .none,
            momentumPhase: ScrollZoom.MomentumPhase = .none
        ) {
            self.deltaY = deltaY
            self.phase = phase
            self.momentumPhase = momentumPhase
        }
    }

    /// What one scroll event does to the zoom (v0.5/S2): either it feeds the
    /// one zoom model a multiplicative factor, or the gesture holds.
    public enum Decision: Equatable, Sendable {
        /// Multiply the zoom by `factor` (anchored, clamped, through
        /// `BoardTransform` as every other zoom is).
        case zoom(factor: CGFloat)
        /// The event moves no zoom state.
        case noZoom
    }

    /// ⌘ + scroll gesture state machine (v0.5/S2): the pure rule that keeps a
    /// whole gesture monotonic on top of the one shared factor. Three
    /// mechanisms, all the gesture's own state:
    ///
    /// - **Direction lock.** Inside a precise-delta gesture the deltas carry
    ///   the fingers' micro-movements, so small opposite-signed deltas
    ///   interleave with the dominant direction; under the multiplicative
    ///   mapping each one visibly kicks the zoom back. The first nonzero
    ///   delta latches the direction, and an event against it zooms nothing
    ///   until the opposite evidence outweighs the jitter threshold — only
    ///   then does the gesture deliberately continue the other way.
    /// - **Momentum rejection.** After the fingers lift (`phase == .ended`)
    ///   AppKit keeps delivering deltas with `momentumPhase != .none`; they
    ///   belong to no live gesture and must not zoom, or a flick overshoots
    ///   the zoom the user asked for.
    /// - **Direction preserved, not normalised.** `scrollingDeltaY` is
    ///   content-directed, so the two natural-scrolling settings report
    ///   opposite signs for the same physical flick. Normalising through
    ///   `isDirectionInvertedFromDevice` would make the settings agree, but it
    ///   would invert the direction for whoever is on the default setting —
    ///   the owner's machine among them — and a zoom that reverses overnight is
    ///   worse than one that differs between devices. The raw delta keeps the
    ///   mapping this board already had. The factor itself stays the one shared
    ///   function, so a trackpad's fractions and a wheel's notches feed
    ///   `BoardTransform` through the same zoom model.
    public struct Gesture: Sendable {
        /// Opposite points a gesture must show before they count as a
        /// deliberate direction change rather than jitter: one full zoom
        /// step's worth of scrolling. Jitter deltas are small and arrive
        /// interleaved with consistent deltas (which reset the accounting),
        /// while a wheel notch or a firm reversal crosses it in one event.
        public static let reversalThresholdPoints: CGFloat = ScrollZoom.pointsPerStep

        /// The direction locked while the gesture runs: +1 zooming in, −1
        /// zooming out, nil while no gesture is live.
        private var lockedDirection: CGFloat?
        /// Opposite points seen since the last consistent event: the
        /// evidence that the user is deliberately changing direction.
        private var reversalPoints: CGFloat = 0

        public init() {}

        /// Decides what `event` does to the zoom (v0.5/S2).
        public mutating func decide(for event: ScrollZoom.Event) -> ScrollZoom.Decision {
            // Momentum belongs to no live gesture: reject it before touching
            // any state, so the flick never overshoots and the lock waits
            // untouched for the gesture's own phases.
            guard event.momentumPhase == .none else { return .noZoom }
            // Whatever the delta below decided, the gesture's phases close
            // it here: the next gesture may zoom the other way.
            defer {
                if event.phase == .ended || event.phase == .cancelled {
                    lockedDirection = nil
                    reversalPoints = 0
                }
            }
            // The delta stays as AppKit reports it: see the "direction
            // preserved" note above — normalising across the natural-scrolling
            // setting would have flipped the zoom for the default setting.
            let delta = event.deltaY
            guard delta.isFinite, delta != 0 else { return .noZoom }
            let sign: CGFloat = delta > 0 ? 1 : -1
            if let locked = lockedDirection {
                if locked == sign {
                    // Consistent with the lock: the opposite evidence was
                    // jitter, forget it.
                    reversalPoints = 0
                } else {
                    // Against the lock: hold unless the opposite evidence
                    // says the user is deliberately changing direction.
                    reversalPoints += abs(delta)
                    guard reversalPoints >= Self.reversalThresholdPoints else { return .noZoom }
                    lockedDirection = sign
                    reversalPoints = 0
                }
            } else {
                // The gesture's first nonzero delta latches the direction.
                lockedDirection = sign
            }
            return .zoom(factor: ScrollZoom.zoomFactor(forScrollDelta: delta))
        }
    }
}

/// The Freeform-style dot grid over a board page (T6/S6). Dots live in page
/// space — they pan and zoom with the content — at the base pitch from the
/// page origin, with a screen-anchored size and colour that read on both a
/// white and a black page.
public enum DotGrid: Sendable {
    /// Page points between dots at zoom 1.
    public static let spacing: CGFloat = 24
    /// The on-screen pitch never drops below this many view points, whatever
    /// the zoom: at very low zoom a fixed spacing turns into mush, so the grid
    /// coarsens by powers of two instead.
    public static let minimumScreenSpacing: CGFloat = 12
    /// A dot's radius on screen, in view points — never scaled with the zoom.
    public static let dotRadius: CGFloat = 1.1

    /// The page-space pitch the board shows at `zoom`: the first power-of-two
    /// multiple of the base spacing whose on-screen pitch is readable. The
    /// result keeps `spacing · zoom` in [minimum, 2 × minimum) while it can,
    /// and above that is the base spacing again — density stays readable at
    /// every zoom level without ever growing the dot count.
    public static func pageSpacing(atZoom zoom: CGFloat) -> CGFloat {
        guard zoom > 0, zoom.isFinite else { return spacing }
        var pitch = spacing
        while pitch * zoom < minimumScreenSpacing {
            pitch *= 2
        }
        return pitch
    }

    /// The dots inside a page-space rect, on the pitch (anchored at the page
    /// origin), in row-major order. The view passes its dirty rect so a
    /// per-frame paint only enumerates what needs repainting.
    public static func dots(in rect: CGRect, spacing: CGFloat) -> [CGPoint] {
        guard rect.width > 0, rect.height > 0, spacing > 0, spacing.isFinite else { return [] }
        let firstX = (rect.minX / spacing).rounded(.down) * spacing
        let firstY = (rect.minY / spacing).rounded(.down) * spacing
        var dots: [CGPoint] = []
        var y = firstY
        while y <= rect.maxY {
            var x = firstX
            while x <= rect.maxX {
                let dot = CGPoint(x: x, y: y)
                if rect.contains(dot) { dots.append(dot) }
                x += spacing
            }
            y += spacing
        }
        return dots
    }

    /// The dots visible on a page at `zoom`, within the page-space rect.
    public static func dots(in rect: CGRect, zoom: CGFloat) -> [CGPoint] {
        dots(in: rect, spacing: pageSpacing(atZoom: zoom))
    }
}

/// A whiteboard page's solid background. Three choices: white, black, or
/// follow the system — white in light mode, black in dark mode. The choice is
/// a value of the page itself, so the page keeps its own identity (⌘B knows
/// whether the user picked a colour or the page still follows the theme); the
/// concrete colour is resolved against the appearance wherever one is
/// consumed — paint, capture base, beneath-blur image. Inks are never
/// remapped, so a mark colour that vanishes against the background is the
/// user's call.
public enum BoardBackground: String, CaseIterable, Codable, Equatable, Sendable {
    /// Follows the system appearance: light → white, dark → black.
    case system
    case white
    case black

    /// The concrete page colour: a system page resolves against `isDark`, an
    /// explicit choice is itself.
    public func resolved(isDark: Bool) -> BoardBackground {
        switch self {
        case .system: isDark ? .black : .white
        case .white: .white
        case .black: .black
        }
    }

    /// The colour this background paints with `isDark` as the appearance.
    public func cgColor(isDark: Bool) -> CGColor {
        resolved(isDark: isDark).cgColor
    }

    /// The explicit colour of a white or black page. A `.system` page has no
    /// colour of its own: production callers pass the appearance through
    /// `cgColor(isDark:)`; this parameterless form resolves `.system` as white
    /// (light mode) only so explicit-choice call sites keep compiling.
    public var cgColor: CGColor {
        switch self {
        case .system, .white: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .black: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        }
    }

    public var displayName: String {
        switch self {
        case .system: "Follow the system"
        case .white: "White"
        case .black: "Black"
        }
    }

    public var toggled: BoardBackground {
        self == .white ? .black : .white
    }

    /// A solid, opaque image at display pixel size: the base a page's capture
    /// composes over, so a whiteboard capture is never transparent and never
    /// shows the desktop hidden behind the board. A `.system` page resolves
    /// against `isDark` at capture time, so the result is always concrete.
    public func captureBase(width: Int, height: Int, isDark: Bool) -> CGImage? {
        resolved(isDark: isDark).captureBase(width: width, height: height)
    }

    /// The explicit-choice form of the capture base; `.system` resolves as
    /// white (light mode). See `cgColor` for why this form exists.
    public func captureBase(width: Int, height: Int) -> CGImage? {
        guard width >= 1, height >= 1,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// One whiteboard page: its own marks (own `DrawingSession`, so undo, redo and
/// the numbered sequence restart per page), its own background colour and its
/// own pan offset over the endless canvas.
///
/// Stroke points are stored in **page space** (top-left origin, the same
/// `CoordinateMapping` conventions the overlay uses): `viewPoint = pagePoint -
/// offset`. Changing the display or the window size never moves existing marks.
public struct BoardPage: Equatable, Sendable {
    public var session: DrawingSession
    public var background: BoardBackground
    /// How far the page origin sits from the display's top-left corner.
    public var offset: CGSize
    /// Screen zoom of this page's canvas (T5/S5): `view = (page − offset) × zoom`.
    /// A view that never zooms keeps 1, where the mapping is the old rule.
    public var zoom: CGFloat
    /// The page's ONE image layer (T2b/S2): a capture pasted from the history
    /// (`⌥⇧I` with the board open). It draws above the page colour and beneath
    /// the marks, in page space through `BoardImage`, so it pans and zooms
    /// with the page, and every capture and blur includes it. One image per
    /// page: pasting again replaces it. A session value like the pages
    /// themselves — never written to the boot archive (see `persisted`).
    public var image: BoardImage?

    /// The page's full view mapping, in one place: everything that maps between
    /// page space and view space reads this.
    public var transform: BoardTransform {
        BoardTransform(offset: offset, zoom: zoom)
    }

    public init(
        session: DrawingSession = DrawingSession(),
        background: BoardBackground = .white,
        offset: CGSize = .zero,
        zoom: CGFloat = 1,
        image: BoardImage? = nil
    ) {
        self.session = session
        self.background = background
        self.offset = offset
        self.zoom = zoom
        self.image = image
    }
}

/// Per display: the ordered pages of one whiteboard, plus which one is
/// presented. A class on purpose — the overlay and the view share the same
/// instance, so every mutation lands in one place and closing the board keeps
/// the pages alive without any write-back sync.
public final class WhiteboardPages {
    public private(set) var pages: [BoardPage]
    public private(set) var currentIndex: Int

    /// Starts with a single page on the given background. The default stays
    /// `.white` here; the controller passes the page-colour preference so a
    /// fresh board starts on the user's choice (system by default).
    public init(background: BoardBackground = .white) {
        pages = [BoardPage(background: background)]
        currentIndex = 0
    }

    public var count: Int { pages.count }
    public var currentPage: BoardPage { pages[currentIndex] }

    /// The live session of the view is authoritative while its page is
    /// presented: the view hands it back here after every change and when the
    /// page or the panel changes, so the page keeps its marks.
    public func adopt(_ session: DrawingSession) {
        pages[currentIndex].session = session
    }

    /// › — moves on, or creates a new page past the last one inheriting the
    /// current page's background. Returns whether a page was created.
    @discardableResult
    public func selectNext() -> Bool {
        if currentIndex == pages.count - 1 {
            let inherited = pages[currentIndex].background
            pages.append(BoardPage(background: inherited))
            currentIndex += 1
            return true
        }
        currentIndex += 1
        return false
    }

    /// ‹ — moves back one page. At the first page it stays put and returns
    /// false: nothing is created behind the user. Returns whether it moved.
    @discardableResult
    public func selectPrevious() -> Bool {
        guard currentIndex > 0 else { return false }
        currentIndex -= 1
        return true
    }

    /// Moves to the page at `index`. A valid index is always accepted (even the
    /// already-presented one) and `currentIndex` then names it; anything out of
    /// range is refused and the board is left exactly as it was. Returns
    /// whether the board presents the requested page.
    @discardableResult
    public func select(index: Int) -> Bool {
        guard index >= 0, index < pages.count else { return false }
        currentIndex = index
        return true
    }

    /// ⌘⌫ — deletes the current page. The board can never go empty, so with a
    /// single page the delete is refused and nothing changes; callers disable
    /// the affordance for that case. Returns whether a page was deleted.
    @discardableResult
    public func deleteCurrentPage() -> Bool {
        guard pages.count > 1 else { return false }
        pages.remove(at: currentIndex)
        // Deleting the last page pulls the index back into range; deleting any
        // other page hands the slot to the page that followed it.
        if currentIndex == pages.count { currentIndex -= 1 }
        return true
    }

    /// ⌥← — swaps the current page with the one before it. At the first page
    /// there is nothing to the left, so it is refused and nothing changes.
    /// Returns whether the page moved. The page itself (marks, background,
    /// offset, identity) stays exactly what it was and remains current.
    @discardableResult
    public func moveCurrentPageLeft() -> Bool {
        guard currentIndex > 0 else { return false }
        pages.swapAt(currentIndex, currentIndex - 1)
        currentIndex -= 1
        return true
    }

    /// ⌥→ — swaps the current page with the one after it. At the last page
    /// there is nothing to the right, so it is refused. Returns whether the
    /// page moved.
    @discardableResult
    public func moveCurrentPageRight() -> Bool {
        guard currentIndex < pages.count - 1 else { return false }
        pages.swapAt(currentIndex, currentIndex + 1)
        currentIndex += 1
        return true
    }

    /// ⌘B — flips only the current page between white and black. A page that
    /// follows the system resolves against `isDark` first, so the flip starts
    /// from the colour the user actually sees and lands on the opposite
    /// explicit choice; an explicit page just flips.
    public func toggleBackground(isDark: Bool = false) {
        pages[currentIndex].background = pages[currentIndex].background.resolved(isDark: isDark).toggled
    }

    /// Shifts the current page's pan offset. `pan` adds to the offset: after
    /// `pan(by: d)` a point drawn on screen moves by `-d`.
    public func pan(by delta: CGSize) {
        let offset = pages[currentIndex].offset
        pages[currentIndex].offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
    }

    /// Sets the current page's pan offset outright, used by tests and panning resets.
    public func setOffset(_ offset: CGSize) {
        pages[currentIndex].offset = offset
    }

    /// The current page's zoom.
    public var zoom: CGFloat { pages[currentIndex].zoom }

    /// The current page's full page ↔ view mapping.
    public var viewTransform: BoardTransform { pages[currentIndex].transform }

    /// Zooms the current page to `target`, anchored at `anchor` (a view point):
    /// the page point under the anchor never moves. The target is clamped into
    /// the zoom range. Returns whether the page's view changed.
    @discardableResult
    public func zoom(to target: CGFloat, anchoredAt anchor: CGPoint) -> Bool {
        let current = pages[currentIndex].transform
        let updated = current.zoomed(to: target, anchoredAt: anchor)
        guard updated != current else { return false }
        pages[currentIndex].offset = updated.offset
        pages[currentIndex].zoom = updated.zoom
        return true
    }

    /// ⌘0 — restores the current page's pan and zoom together: offset back to
    /// zero and zoom back to one. Marks never move (their stored points are
    /// page space), so nothing else changes.
    public func resetView() {
        pages[currentIndex].offset = .zero
        pages[currentIndex].zoom = 1
    }

    // MARK: - The page image layer (T2b/S2)

    /// Pastes `image` as the current page's image layer: centred in the
    /// visible view area at the image's own pixel size, clamped into that
    /// area by the editor's own clamp (`BoardImage.pasted`), stored in page
    /// space so it pans and zooms with the page. One image per page: any
    /// layer the page already carried is replaced. Returns the new layer, or
    /// nil for a degenerate image.
    @discardableResult
    public func paste(_ image: CGImage, inView visibleViewRect: CGRect) -> BoardImage? {
        guard image.width > 0, image.height > 0 else { return nil }
        let layer = BoardImage.pasted(image, inView: visibleViewRect, transform: pages[currentIndex].transform)
        pages[currentIndex].image = layer
        return layer
    }

    /// Moves the current page's image layer by `delta` page points, clamped
    /// into `visible` — the page-space rect the gesture clamps against (the
    /// visible area, captured when the drag began). Returns whether it moved.
    @discardableResult
    public func movePageImage(by delta: CGSize, clampedTo visible: CGRect) -> Bool {
        guard let layer = pages[currentIndex].image else { return false }
        let destination = layer.rect.applying(CGAffineTransform(translationX: delta.width, y: delta.height))
        return placePageImage(at: destination, clampedTo: visible)
    }

    /// Replaces the current page image layer's placement outright — a corner
    /// resize drag's live application, or a move's destination — clamped into
    /// `visible` by the same clamp a paste uses. Returns whether the page had
    /// an image to place and the placement changed anything.
    @discardableResult
    public func placePageImage(at rect: CGRect, clampedTo visible: CGRect) -> Bool {
        guard let layer = pages[currentIndex].image else { return false }
        var updated = layer
        updated.rect = CanvasComposition.clampedPlacement(rect, in: visible)
        guard updated != layer else { return false }
        pages[currentIndex].image = updated
        return true
    }

    /// ⌫ — removes the current page's image layer. Returns whether there was
    /// one to remove.
    @discardableResult
    public func removePageImage() -> Bool {
        guard pages[currentIndex].image != nil else { return false }
        pages[currentIndex].image = nil
        return true
    }
}

/// The persisted form of one board page (T10/S11): the page's marks (see
/// `DrawingSession.persistedStrokes` — already without transient laser marks),
/// its background, its pan offset and its zoom. The background rides as its
/// raw value via `Codable`. The page's image layer (T2b/S2) is deliberately
/// NOT here: it lives as long as the session, like the pages, and is never
/// written to disk.
public struct PersistedBoardPage: Codable, Equatable, Sendable {
    public var strokes: [PersistedStroke]
    public var background: BoardBackground
    public var offset: CGSize
    public var zoom: CGFloat

    public init(strokes: [PersistedStroke], background: BoardBackground, offset: CGSize, zoom: CGFloat) {
        self.strokes = strokes
        self.background = background
        self.offset = offset
        self.zoom = zoom
    }
}

/// The persisted form of one display's whole board (T10/S11): the ordered
/// pages and which one was presented when the session was saved.
public struct PersistedBoard: Codable, Equatable, Sendable {
    public var pages: [PersistedBoardPage]
    public var currentIndex: Int

    public init(pages: [PersistedBoardPage], currentIndex: Int) {
        self.pages = pages
        self.currentIndex = currentIndex
    }
}

/// The stored-form seam for board pages (T10/S11).
extension BoardPage {
    /// The stored form of the page: its non-transient marks, its background,
    /// its pan and its zoom.
    public var persisted: PersistedBoardPage {
        PersistedBoardPage(
            strokes: session.persistedStrokes.map(\.persisted),
            background: background,
            offset: offset,
            zoom: zoom
        )
    }

    /// Rebuilds the page from its stored form: marks come back exactly as
    /// they were saved, with the numbered sequence continuing per page.
    public init(persisted page: PersistedBoardPage) {
        self.init(
            session: .restored(strokes: page.strokes.compactMap(Stroke.init(persisted:))),
            background: page.background,
            offset: page.offset,
            zoom: page.zoom
        )
    }
}

/// The stored-form seam for the board (T10/S11).
public extension WhiteboardPages {
    /// The stored form of the whole board: every page in order, without any
    /// transient mark, and which page was presented.
    func persistedBoard() -> PersistedBoard {
        PersistedBoard(pages: pages.map(\.persisted), currentIndex: currentIndex)
    }

    /// Rebuilds a board from its stored form: the same pages, in the same
    /// order, presenting the page that was presented. A stored board with no
    /// pages — or one whose current index names a page it does not have — is
    /// clamped into a state a fresh board can be: one page, at index 0. A nil
    /// stored board builds a fresh single page on `fallbackBackground`, the
    /// same thing a board without stored state has always opened with.
    convenience init(restoring stored: PersistedBoard, fallbackBackground: BoardBackground) {
        guard !stored.pages.isEmpty else {
            self.init(background: fallbackBackground)
            return
        }
        // The index is clamped before anything indexes with it, so a partial
        // or foreign document can never trap the board.
        let currentIndex = min(max(stored.currentIndex, 0), stored.pages.count - 1)
        self.init(background: stored.pages[currentIndex].background)
        pages = stored.pages.map(BoardPage.init(persisted:))
        self.currentIndex = currentIndex
    }
}
