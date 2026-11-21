import AppKit
import SwiftUI
import StareCore

/// Renders the pointer highlight from a `StareCore.PointerAppearance` into an
/// image. The only drawing code is `PointerHighlightRenderer`, the one
/// production renderer the overlay draws with — the Settings preview and the
/// selftest therefore paint exactly the pixels the overlay paints, and can
/// never drift from the real highlight.
enum PointerHighlightPreview {
    /// Side of the square bitmap that fits the whole highlight of this
    /// appearance — including the glow reach and margin — in points, taken
    /// from the appearance's own extent so it can never clip the drawing.
    static func side(for appearance: PointerAppearance, pulseScale: CGFloat = 1) -> CGFloat {
        let extent = PointerHighlightRenderer.extent(for: appearance, pulseScale: pulseScale)
        return max(extent.width, extent.height).rounded(.up)
    }

    /// Transparent image of the highlight centred in its bitmap, sized in
    /// points; nil when the bitmap context cannot be created. `pulseScale` and
    /// `rotation` render a click-pulse instant (the selftest's rotated render);
    /// the Settings preview draws its rest state through a scaled appearance.
    static func image(
        for appearance: PointerAppearance,
        scale: CGFloat,
        pulseScale: CGFloat = 1,
        rotation: CGFloat = 0
    ) -> NSImage? {
        cgImage(for: appearance, scale: scale, pulseScale: pulseScale, rotation: rotation).map { cgImage in
            let side = side(for: appearance, pulseScale: pulseScale)
            return NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
        }
    }

    /// The same render as an opaque-alpha-preserving bitmap at `scale` pixels
    /// per point, for pixel checks in the selftest.
    static func cgImage(
        for appearance: PointerAppearance,
        scale: CGFloat,
        pulseScale: CGFloat = 1,
        rotation: CGFloat = 0
    ) -> CGImage? {
        let side = side(for: appearance, pulseScale: pulseScale)
        let pixels = max(1, Int(side * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixels,
                height: pixels,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        // The overlay draws in a flipped view (top-left origin), so flipping
        // this bitmap the same way keeps the render's orientation honest; the
        // symmetric geometries are unaffected.
        context.translateBy(x: 0, y: side)
        context.scaleBy(x: 1, y: -1)
        PointerHighlightRenderer.draw(
            in: context,
            center: CGPoint(x: side / 2, y: side / 2),
            appearance: appearance,
            pulseScale: pulseScale,
            rotation: rotation
        )
        return context.makeImage()
    }
}

/// The Settings preview: the highlight the user is configuring, drawn by the
/// production renderer over a light and a dark background side by side, inside
/// a fixed canvas that never changes with the chosen size — an oversized
/// highlight is scaled down to fit and the caption says the percentage, so
/// nothing in the pane resizes, reflows or scrolls because of the size value.
/// Every bound change re-evaluates the body and re-renders, so dragging a
/// slider updates it live; there is no Apply button and nothing needs a
/// restart.
struct PointerPreviewView: View {
    let style: StareCore.PointerStyle
    /// Ink the highlight is shown in. The pane passes a representative ink;
    /// a style whose colour follows the active ink takes the real active ink
    /// while drawing.
    let ink: Ink

    /// Side of each preview tile, in points: a fixed canvas, deliberately
    /// larger than the default 72 pt highlight's full extent (161 pt) so the
    /// default draws at its real size, and every larger size scales down into
    /// it instead of resizing the pane. The selftest reports it as
    /// `previewTile=`.
    static let tileSide: CGFloat = 168

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                tile(background: .white)
                tile(background: Color(white: 0.16))
            }
            Text(caption)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// What the preview draws and what it says about it, both derived from the
    /// same fit scale so neither can lie: the appearance is uniformly scaled
    /// into the fixed canvas, and the caption names the percentage and the
    /// real size whenever scaling happened.
    private var fitScale: Double {
        PointerHighlightRenderer.fitScale(
            extentSide: Double(PointerHighlightPreview.side(for: appearance)),
            canvasSide: Double(Self.tileSide)
        )
    }

    private var appearance: PointerAppearance {
        style.appearance(ink: ink)
    }

    private var caption: String {
        PointerHighlightRenderer.previewFitCaption(scale: fitScale, size: style.size)
    }

    private func tile(background: Color) -> some View {
        let scale = fitScale
        let drawn = scale < 1 ? appearance.scaled(by: scale) : appearance
        return ZStack {
            background
            if let image = PointerHighlightPreview.image(for: drawn, scale: previewScale) {
                // Drawn at its own point size — smaller than the tile when
                // scaled down — and centred; never stretched to the tile.
                Image(nsImage: image)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: Self.tileSide, height: Self.tileSide)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }

    /// The bitmap is built at the main screen's scale for crispness,
    /// defaulting to 2x where there is no screen (offscreen selftest hosts).
    private var previewScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }
}
