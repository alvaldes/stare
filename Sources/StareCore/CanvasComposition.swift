import CoreGraphics
import Foundation

/// T12/S19, slice 1 — the model and the geometry (nothing user-visible yet).
/// S19 (quoted from the peer's capture-parity work): "Canvas componible: el
/// editor puede sumar otra captura o una imagen pegada y posicionarla."
///
/// A composition is a base capture plus zero or more added layers, each with
/// its own placement, identity and z-order. Everything here is a value
/// operation in StareCore — there is no view state anywhere: a layer's
/// placement is a rect in the capture's **pixel space**, the same space
/// `EditorCropSpace.coverage` cuts from (top-left origin, image pixels), and
/// the editor later maps it onto the view through the crop space it already
/// maintains while the viewport (`EditorViewport`) composes the zoom and pan
/// on top. The zoom that looks at a layer never changes what flattening
/// saves, exactly as it never changes what the marks save.
///
/// Flattening composites the layers over the base at pixel resolution and
/// hands out the result for the existing save path unchanged. With no layers
/// the base is returned untouched — same pixels, no resample — so "no layers
/// means today's image" and every capture composed so far is unaffected.
public struct CanvasComposition: Equatable {
    /// The capture the layers are added onto; its pixel size is the canvas.
    public let base: CGImage
    /// The added layers in z-order: index 0 is the bottom (drawn first),
    /// the last index the top.
    public private(set) var layers: [CanvasLayer]

    public init(base: CGImage) {
        self.base = base
        self.layers = []
    }

    /// The canvas a placement lives in: the base's pixels, one unit each.
    public var canvas: CGRect {
        CGRect(x: 0, y: 0, width: CGFloat(base.width), height: CGFloat(base.height))
    }

    /// The pixel size of the flattened result — the base's own pixels; a
    /// layer is clipped to it, never enlarges it (see `flattened()`).
    public var pixelSize: CGSize {
        CGSize(width: base.width, height: base.height)
    }

    // MARK: - Placement geometry

    /// The smallest side a layer keeps, in canvas units, so it can never
    /// become too small to grab. It sits above the crop rule's
    /// `EditorCropRule.minimumSide` (8) with room to spare, for the same
    /// reason the crop has its own minimum: a layer below a grabbable size
    /// is unreachable by a pointer at any zoom and so is lost anyway.
    public static let minimumGrabSide: CGFloat = 16

    /// The clamped form of a placement rect, per axis:
    ///
    /// - The scaled length is capped at the canvas length — a layer can
    ///   never be larger than the canvas — and floored at
    ///   `min(minimumGrabSide, canvasLength)` — never smaller than a
    ///   grabbable side; a canvas smaller than the grab side is itself the
    ///   floor, and the layer fills it exactly.
    /// - The origin is clamped so at least `min(length, minimumGrabSide)`
    ///   canvas units of the layer stay over the canvas on that axis: a
    ///   layer may hang off an edge, but a grabbable strip of it always
    ///   remains in reach. A layer whose calibrated length is at most the
    ///   grab side fits entirely inside, and the clamp keeps it there.
    ///
    /// An intersection exactly the length of the strip (or a length exactly
    /// the canvas, or exactly the grab side) is legal — those boundaries are
    /// the clamp's own answers. The clamp is idempotent: clamping a clamped
    /// rect returns it, as `EditorViewport.clamped`'s fit does.
    ///
    /// A degenerate canvas or a non-finite rect is returned untouched;
    /// `append`, `move` and `place` never see one (`base` carries the
    /// canvas), so operations are deterministic either way.
    public static func clampedPlacement(_ rect: CGRect, in canvas: CGRect) -> CGRect {
        guard canvas.width > 0, canvas.height > 0,
            isFinite(canvas), isFinite(rect)
        else {
            return rect
        }
        let r = rect.standardized

        func clampedAxis(
            _ origin: CGFloat, _ length: CGFloat, canvasMin: CGFloat, canvasLength: CGFloat
        ) -> (origin: CGFloat, length: CGFloat) {
            let lengthFloor = min(minimumGrabSide, canvasLength)
            let bounded = min(max(length, lengthFloor), canvasLength)
            let keep = min(bounded, minimumGrabSide)
            let origin = min(
                max(origin, canvasMin + keep - bounded),
                canvasMin + canvasLength - keep)
            return (origin, bounded)
        }

        let width = clampedAxis(r.minX, r.width, canvasMin: canvas.minX, canvasLength: canvas.width)
        let height = clampedAxis(r.minY, r.height, canvasMin: canvas.minY, canvasLength: canvas.height)
        return CGRect(x: width.origin, y: height.origin, width: width.length, height: height.length)
    }

    /// `CGRect` has no `isFinite` of its own in this SDK.
    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
    }

    // MARK: - Value operations

    /// Adds a layer on top of the z-order, with its placement clamped into
    /// the canvas. The new layer gets a fresh identity, so two layers built
    /// from the same image at the same placement are distinct.
    @discardableResult
    public mutating func append(_ image: CGImage, at placement: CGRect) -> CanvasLayer {
        let layer = CanvasLayer(image: image, placement: Self.clampedPlacement(placement, in: canvas))
        layers.append(layer)
        return layer
    }

    /// Removes exactly the layer with that identity and returns it, or nil
    /// when no layer carries it. Identity, never contents: a twin with the
    /// same image and the same placement stays.
    @discardableResult
    public mutating func remove(id: UUID) -> CanvasLayer? {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return nil }
        return layers.remove(at: index)
    }

    /// Moves the layer with that identity in the z-order so it sits at
    /// `index` (0 is the bottom, the layer count before the move is the
    /// top). An index outside that range clamps, so every value move lands;
    /// an unknown identity changes nothing. The other layers keep their
    /// relative order.
    public mutating func reorder(id: UUID, to index: Int) {
        guard let current = layers.firstIndex(where: { $0.id == id }) else { return }
        let layer = layers.remove(at: current)
        layers.insert(layer, at: min(max(index, 0), layers.count))
    }

    /// Shifts the layer with that identity by `delta` canvas units, clamped
    /// like every placement; the other layers do not move. Returns the moved
    /// layer, or nil for an unknown identity.
    @discardableResult
    public mutating func move(id: UUID, by delta: CGSize) -> CanvasLayer? {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return nil }
        let current = layers[index].placement
        let destination = current.applying(CGAffineTransform(translationX: delta.width, y: delta.height))
        layers[index].placement = Self.clampedPlacement(destination, in: canvas)
        return layers[index]
    }

    /// Replaces the layer's whole placement — position and scale together,
    /// since a rewrite of one usually shifts the other — clamped like every
    /// placement. Returns the placed layer, or nil for an unknown identity.
    @discardableResult
    public mutating func place(id: UUID, at placement: CGRect) -> CanvasLayer? {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return nil }
        layers[index].placement = Self.clampedPlacement(placement, in: canvas)
        return layers[index]
    }

    /// The layer with that identity, if any.
    public func layer(withID id: UUID) -> CanvasLayer? {
        layers.first { $0.id == id }
    }

    /// Restores a whole layer list in z-order — the journal's canvas step
    /// handing its snapshot back to the editor's undo. No clamping and no
    /// re-identifying: the snapshot's placements are already clamped values
    /// and its identities are the layers' own.
    public mutating func restore(_ layers: [CanvasLayer]) {
        self.layers = layers
    }

    // MARK: - Flattening

    /// Writes the composition out as one image at the base's pixel
    /// resolution, ready for the existing save path unchanged: layers are
    /// drawn in z-order over the base, scaled into their placement rects,
    /// clipped by the canvas — a layer hanging off the edge is cut at it,
    /// never enlarges the output. The base is drawn 1:1 at its own size, so
    /// placed layers land on exactly the pixels their rects name, like
    /// `MarkCompositor`'s marks do.
    ///
    /// With no layers the base image is returned **itself** — no context, no
    /// redraw, no resample. An empty composition must degrade to exactly
    /// today's image, byte for byte, because every capture saved so far went
    /// through an equivalent no-layer state.
    public func flattened() -> CGImage? {
        guard base.width > 0, base.height > 0 else { return nil }
        guard !layers.isEmpty else { return base }
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
        context.draw(base, in: CGRect(x: 0, y: 0, width: CGFloat(base.width), height: CGFloat(base.height)))
        for layer in layers {
            let rect = layer.placement
            guard !rect.isNull, !rect.isEmpty, Self.isFinite(rect),
                layer.image.width > 0, layer.image.height > 0
            else { continue }
            // Placements are top-left origin; the bitmap context is
            // bottom-left, the same flip `MarkCompositor` carries for
            // overlay space.
            context.draw(
                layer.image,
                in: CGRect(x: rect.minX, y: CGFloat(base.height) - rect.maxY, width: rect.width, height: rect.height))
        }
        return context.makeImage()
    }
}

public struct CanvasLayer: Equatable {
    /// The layer's identity. Contents never identify a layer: two layers may
    /// show the same image at the same placement and stay distinct.
    public let id: UUID
    public var image: CGImage
    /// The placement in the canvas' pixel space (top-left origin): the rect
    /// the image is drawn into, so the rect's size relative to the image's
    /// own size is the layer's scale.
    public var placement: CGRect

    public init(image: CGImage, placement: CGRect) {
        self.id = UUID()
        self.image = image
        self.placement = placement
    }
}
