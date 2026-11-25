import CoreGraphics
import Foundation

/// One image layer on a whiteboard page (T2b/S2). The board's capture history
/// (`⌥⇧I`) can paste a capture onto the open page instead of only copying it,
/// and the page carries it as ONE layer that pans and zooms with the page
/// like the marks do: the rect is stored in **page space** (top-left origin,
/// the same conventions the overlay uses), so `viewRect(for:)` through
/// `BoardTransform` decides where the board shows it at any pan or zoom.
///
/// Everything the board shows includes the layer: it draws above the page
/// colour and beneath the marks, and it is composited into the base the
/// capture and a blur mark's beneath-image both start from
/// (`composited(over:transform:scale:)`), at exactly the pixels the board
/// shows. The layer is a session value like the pages themselves — the boot
/// archive never stores it.
///
/// One image per page: pasting again replaces the page's layer.
public struct BoardImage: Equatable, Sendable {

    /// The layer's identity. Contents never identify a layer: a replacement
    /// of the page's layer with the same image at the same rect is a new layer.
    public let id: UUID
    public var image: CGImage
    /// The placement in page space (top-left origin, page points): the rect
    /// the image is drawn into, so the rect's size relative to the image's
    /// own pixel size is the layer's scale.
    public var rect: CGRect

    public init(image: CGImage, rect: CGRect) {
        self.id = UUID()
        self.image = image
        self.rect = rect
    }

    // MARK: - Placement geometry

    /// The clamped placement a new paste uses: centred on the visible view
    /// area at the image's own pixel size, fitted whole when it does not fit,
    /// clamped into that area by the capture editor's own clamp
    /// (`CanvasComposition.clampedPlacement`, the same math a drop or a ⌘V
    /// paste goes through there), then mapped into page space through
    /// `transform` so it pans and zooms with the page.
    /// The centre deliberately does not depend on the pointer, exactly like
    /// the editor's paste: a keyboard gesture with a defined centre.
    public static func pasted(
        _ image: CGImage,
        inView visibleViewRect: CGRect,
        transform: BoardTransform
    ) -> BoardImage {
        let own = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        let area = visibleViewRect.standardized
        guard area.width > 0, area.height > 0, area.width.isFinite, area.height.isFinite else {
            // No visible area to centre in — a paste while the board has no
            // laid-out canvas. Centring on nothing would put the layer at a
            // negative half-size the user could never find, so it lands at
            // the page origin at its own pixel size instead.
            let atOrigin = CGRect(origin: .zero, size: own)
            return BoardImage(image: image, rect: transform.rect(toPage: atOrigin))
        }
        // The fit and the clamp both happen in PAGE space, which is where every
        // later clamp of this layer runs (a move and a resize drag). Doing them
        // in view space left the paste admitting a placement the first drag then
        // pushed: the grab minimum is 16 POINTS, so at zoom 2 the paste allowed
        // 8 page points from the edge and the drag demanded 16.
        // The FIT is measured in view points — the image lands at its own pixel
        // size on screen, whatever the page's zoom — and the RESULT is clamped in
        // page space, which is where every later clamp of this layer runs (a move
        // and a resize drag). Clamping the view rect instead left the paste
        // accepting a placement the first drag then pushed: the grab minimum is
        // 16 POINTS, so at zoom 2 the paste allowed 8 page points from the edge
        // and the drag demanded 16.
        let size = fittedSize(
            own,
            in: CGSize(
                width: area.width * Self.insertedAreaFraction,
                height: area.height * Self.insertedAreaFraction
            )
        )
        let centred = CGRect(
            x: area.midX - size.width / 2,
            y: area.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let pageArea = transform.rect(toPage: area)
        let centredPage = transform.rect(toPage: centred)
        return BoardImage(image: image, rect: CanvasComposition.clampedPlacement(centredPage, in: pageArea))
    }

    /// The most of the visible area a fresh paste may take. A capture bigger
    /// than this shrinks to it, so a pasted screenshot reads as an object on
    /// the page instead of covering the board edge to edge (the owner's second
    /// pass: "no ocupe la pantalla completa"). An image that fits at its own
    /// size is never enlarged.
    public static let insertedAreaFraction: CGFloat = 0.6

    /// The image's own pixel size, scaled DOWN by ONE factor when it does not
    /// fit the area it is inserted into, so it keeps its shape. An image that
    /// fits is left at its own size.
    ///
    /// The shared clamp cannot do this by itself: it caps each axis at the
    /// canvas independently, which squeezes the picture AND leaves the origin
    /// where the wider size had put it — the layer ends up distorted and off
    /// centre, filling the page edge to edge.
    public static func fittedSize(_ own: CGSize, in area: CGSize) -> CGSize {
        guard own.width > 0, own.height > 0, area.width > 0, area.height > 0 else { return own }
        let scale = min(1, area.width / own.width, area.height / own.height)
        return CGSize(width: own.width * scale, height: own.height * scale)
    }

    /// The layer's place in the view: where the board draws it (and where a
    /// capture or a blur beneath-image composites it) at the page's transform.
    public func viewRect(for transform: BoardTransform) -> CGRect {
        transform.rect(fromPage: rect)
    }

    // MARK: - Compositing

    /// Returns `base` with the layer composited where the board's view shows
    /// it, at `scale` image pixels per view point — the same mapping the marks
    /// go through in `MarkCompositor.composite`, so a capture and a blur mark's
    /// beneath-image include the layer at exactly the pixels the board shows.
    /// The placements are top-left origin like the view; the bitmap context is
    /// bottom-left, so the draw is flipped the same way
    /// `CanvasComposition.flattened` flips its layers. A layer that hangs off
    /// the base is CLIPPED, not squeezed: the draw happens at the full scaled
    /// rect's own scale and the context clips to the visible intersection —
    /// the same semantics as the board view's `context.draw` clipping — so
    /// the pixels shown are exactly the pixels the view shows.
    ///
    /// A degenerate or fully off-base placement returns `base` unchanged — the
    /// layer clips to the base, it never enlarges it.
    public func composited(over base: CGImage, transform: BoardTransform, scale: CGFloat) -> CGImage? {
        guard base.width > 0, base.height > 0 else { return nil }
        let view = viewRect(for: transform)
        guard !view.isNull, view.width.isFinite, view.height.isFinite else { return base }
        let full = CGRect(x: 0, y: 0, width: CGFloat(base.width), height: CGFloat(base.height))
        let scaledView = view.applying(CGAffineTransform(scaleX: scale, y: scale))
        let pixels = scaledView.intersection(full)
        guard !pixels.isNull, !pixels.isEmpty else { return base }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: base.width,
                height: base.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.draw(base, in: full)
        // Bottom-left coordinates: flip both the clip and the draw rect.
        let flippedScaledView = CGRect(
            x: scaledView.minX,
            y: CGFloat(base.height) - scaledView.maxY,
            width: scaledView.width,
            height: scaledView.height
        )
        context.saveGState()
        context.clip(to: CGRect(
            x: pixels.minX,
            y: CGFloat(base.height) - pixels.maxY,
            width: pixels.width,
            height: pixels.height
        ))
        // Scale comes from the FULL scaled rect — the squeeze would show
        // pixels the view never showed.
        context.draw(image, in: flippedScaledView)
        context.restoreGState()
        return context.makeImage()
    }
}

/// Where a picked capture-history item goes (T2b/S2): into the open
/// whiteboard as the current page's image layer, or to the clipboard the way
/// a pick always behaved when no board is open. The pure decision the panel's
/// pick seam routes through, kept out of the window order so it can be tested
/// as a unit.
public enum HistoryPickDestination: Equatable, Sendable {
    case whiteboardPage
    case clipboard

    /// The board takes the pick only while it is open AND the board actually
    /// has a view to paste into — while the board is being rebuilt no canvas
    /// exists, and the pick falls back to the clipboard instead of being
    /// silently dropped.
    public static func destination(isBoardActive: Bool, hasBoardView: Bool) -> HistoryPickDestination {
        isBoardActive && hasBoardView ? .whiteboardPage : .clipboard
    }

    public static func destination(isBoardActive: Bool) -> HistoryPickDestination {
        destination(isBoardActive: isBoardActive, hasBoardView: true)
    }
}
