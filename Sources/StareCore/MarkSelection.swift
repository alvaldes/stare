import CoreGraphics
import Foundation

/// A handle of the selection overlay. Pure geometry: the app maps these to
/// drawn boxes and cursor shapes, but the decision of what a click grabs
/// lives here so the overlay and tests agree.
public enum MarkHandle: Equatable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    /// The circle above the top centre that turns the mark.
    case rotation
    /// Anywhere inside the mark that is not a handle.
    case body
}

/// The selection of several marks (T6/S8): the ordered set of selected ids,
/// the shift rules and the marquee rule. Pure StareCore, so the drawing
/// overlay, the whiteboard and the tests agree on what a drag and a
/// shift-click select. The ids keep the session's draw order; the first one is
/// the mark the drag chrome acts on.
public struct MarkMultiSelection: Equatable, Sendable {
    public private(set) var ids: [UUID]

    public init() { ids = [] }

    public init(ids: [UUID]) { self.ids = ids }

    public var isEmpty: Bool { ids.isEmpty }

    public var count: Int { ids.count }

    /// The selection's primary: the one mark the handles, the move drag and
    /// the single-mark chrome address.
    public var first: UUID? { ids.first }

    public var single: UUID? { ids.count == 1 ? ids.first : nil }

    public func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// A plain click on a mark: the selection becomes exactly that mark,
    /// whatever was selected before (T11/S6 behaviour).
    public mutating func replace(with id: UUID) { ids = [id] }

    /// A plain marquee: the selection becomes exactly the intersected marks.
    /// An empty result keeps the selection untouched — a drag over nothing must
    /// never throw the user's selection away.
    public mutating func replace(with newIDs: [UUID]) {
        guard !newIDs.isEmpty else { return }
        ids = newIDs
    }

    /// ⇧+click: an unselected mark joins the selection, a selected one leaves.
    public mutating func toggle(_ id: UUID) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
    }

    /// ⇧ marquee: the intersected marks join whatever is already selected.
    public mutating func add(_ newIDs: [UUID]) {
        for id in newIDs where !ids.contains(id) { ids.append(id) }
    }

    @discardableResult
    public mutating func remove(_ id: UUID) -> Bool {
        guard let index = ids.firstIndex(of: id) else { return false }
        ids.remove(at: index)
        return true
    }

    public mutating func clear() { ids.removeAll() }

    /// The marks a page-space marquee selects, in draw order: every committed
    /// mark whose drawn (rotated) bounds intersect the rectangle — a mark
    /// inside it and a mark whose box it merely clips both answer. A marquee
    /// that never grew selects nothing, and the pointer tool's own stray
    /// marks (no geometry) never answer. The rectangle is passed in page
    /// space: the view maps its screen-space drag through `BoardTransform
    /// .rect(toPage:)`, so a zoomed board selects what the user sees under it.
    public static func ids(
        intersectingMarquee rect: CGRect,
        in strokes: [Stroke]
    ) -> [UUID] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        return strokes
            .filter { $0.tool != .select && rect.intersects($0.displayBounds) }
            .map(\.id)
    }
}

/// One selected mark: which stroke it is, where it now sits (rotated bounds
/// included) and which handle a view-space point grabs. Resolved entirely in
/// StareCore, no AppKit.
public struct MarkSelection: Equatable, Sendable {
    public let strokeID: UUID
    /// Axis-aligned bounds of the mark once rotated, for culling and body hits.
    public let displayBounds: CGRect
    /// The unrotated box the handles sit on.
    public let unrotatedBounds: CGRect
    /// Centre of the mark: the pivot of the rotation.
    public let anchor: CGPoint
    public let rotation: CGFloat

    /// Sizes the overlay passes back to `handle(at:)`; they only have to agree
    /// with what it draws.
    public static let defaultHandleSize: CGFloat = 12
    public static let defaultRotationHandleOffset: CGFloat = 20

    public init(stroke: Stroke) {
        self.strokeID = stroke.id
        self.displayBounds = stroke.displayBounds
        self.unrotatedBounds = stroke.bounds
        self.anchor = stroke.anchor
        self.rotation = stroke.rotation
    }

    public init(
        strokeID: UUID,
        displayBounds: CGRect,
        unrotatedBounds: CGRect,
        anchor: CGPoint,
        rotation: CGFloat
    ) {
        self.strokeID = strokeID
        self.displayBounds = displayBounds
        self.unrotatedBounds = unrotatedBounds
        self.anchor = anchor
        self.rotation = rotation
    }

    /// View-space centre of every grabbable handle: the four corners of the
    /// mark as it now looks, plus the rotation circle above the top centre.
    public func handlePoints(rotationHandleOffset: CGFloat) -> [MarkHandle: CGPoint] {
        let transform = Stroke.rotationTransform(around: anchor, by: rotation)
        var points: [MarkHandle: CGPoint] = [:]
        for handle in [MarkHandle.topLeft, .topRight, .bottomLeft, .bottomRight] {
            points[handle] = corner(of: handle).applying(transform)
        }
        let rotationAnchor = CGPoint(
            x: unrotatedBounds.midX,
            y: unrotatedBounds.minY - rotationHandleOffset
        )
        points[.rotation] = rotationAnchor.applying(transform)
        return points
    }

    /// Which handle a view-space point grabs: the nearest handle centre within
    /// `handleSize`/2, otherwise `.body` when the point is inside the mark,
    /// otherwise nil.
    public func handle(
        at point: CGPoint,
        handleSize: CGFloat = MarkSelection.defaultHandleSize,
        rotationHandleOffset: CGFloat = MarkSelection.defaultRotationHandleOffset
    ) -> MarkHandle? {
        let reach = handleSize / 2
        let points = handlePoints(rotationHandleOffset: rotationHandleOffset)

        var nearest: (handle: MarkHandle, distance: CGFloat)?
        for (handle, centre) in points {
            let dx = point.x - centre.x
            let dy = point.y - centre.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance <= reach, distance < (nearest?.distance ?? .infinity) {
                nearest = (handle, distance)
            }
        }
        if let nearest { return nearest.handle }
        return displayBounds.contains(point) ? .body : nil
    }

    private func corner(of handle: MarkHandle) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: unrotatedBounds.minX, y: unrotatedBounds.minY)
        case .topRight: CGPoint(x: unrotatedBounds.maxX, y: unrotatedBounds.minY)
        case .bottomLeft: CGPoint(x: unrotatedBounds.minX, y: unrotatedBounds.maxY)
        case .bottomRight: CGPoint(x: unrotatedBounds.maxX, y: unrotatedBounds.maxY)
        case .rotation, .body: anchor
        }
    }
}
