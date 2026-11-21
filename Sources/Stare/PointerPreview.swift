import AppKit
import SwiftUI
import StareCore

/// Renders the pointer highlight from a `StareCore.PointerStyle` and an ink into an
/// image at its real point size. The only drawing code is
/// `PointerHighlightRenderer`, the one production renderer the overlay draws
/// with — the Settings preview and the selftest therefore paint exactly the
/// pixels the overlay paints, and can never drift from the real highlight.
enum PointerHighlightPreview {
    /// Side of the square bitmap that fits the whole highlight, including the
    /// glow reach and margin, in points, taken from the appearance's own
    /// extent so it can never clip the drawing.
    static func side(for style: StareCore.PointerStyle, ink: Ink, pulseScale: CGFloat = 1) -> CGFloat {
        let extent = PointerHighlightRenderer.extent(for: style.appearance(ink: ink), pulseScale: pulseScale)
        return max(extent.width, extent.height).rounded(.up)
    }

    /// Transparent image of the highlight centred in its bitmap, sized in
    /// points; nil when the bitmap context cannot be created. `pulseScale` and
    /// `rotation` render a click-pulse instant (the selftest's rotated and
    /// peak renders); the Settings preview always draws the rest state.
    static func image(
        for style: StareCore.PointerStyle,
        ink: Ink,
        scale: CGFloat,
        pulseScale: CGFloat = 1,
        rotation: CGFloat = 0
    ) -> NSImage? {
        cgImage(for: style, ink: ink, scale: scale, pulseScale: pulseScale, rotation: rotation).map { cgImage in
            let side = side(for: style, ink: ink, pulseScale: pulseScale)
            return NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
        }
    }

    /// The same render as an opaque-alpha-preserving bitmap at `scale` pixels
    /// per point, for pixel checks in the selftest.
    static func cgImage(
        for style: StareCore.PointerStyle,
        ink: Ink,
        scale: CGFloat,
        pulseScale: CGFloat = 1,
        rotation: CGFloat = 0
    ) -> CGImage? {
        let side = side(for: style, ink: ink, pulseScale: pulseScale)
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
        // The overlay draws in a flipped view (top-left origin), so the marker
        // tip's nib — the only flip-variant geometry — points toward
        // `center.y - radius` = the top of the screen on ⌥⇧M. Flipping this
        // bitmap the same way makes the preview show the nib pointing up too;
        // the four symmetric geometries are unaffected.
        context.translateBy(x: 0, y: side)
        context.scaleBy(x: 1, y: -1)
        PointerHighlightRenderer.draw(
            in: context,
            center: CGPoint(x: side / 2, y: side / 2),
            appearance: style.appearance(ink: ink),
            pulseScale: pulseScale,
            rotation: rotation
        )
        return context.makeImage()
    }
}

/// The Settings preview: the highlight the user is configuring, drawn by the
/// production renderer at the real chosen size over a light and a dark
/// background side by side. Every bound change re-evaluates the body and
/// re-renders, so dragging a slider updates it live; there is no Apply
/// button and nothing needs a restart.
struct PointerPreviewView: View {
    let style: StareCore.PointerStyle
    /// Ink the highlight is shown in. The pane passes a representative ink;
    /// a style whose colour follows the active ink takes the real active ink
    /// while drawing.
    let ink: Ink

    var body: some View {
        HStack(spacing: 12) {
            tile(background: .white)
            tile(background: Color(white: 0.16))
        }
    }

    private var side: CGFloat {
        PointerHighlightPreview.side(for: style, ink: ink)
    }

    private func tile(background: Color) -> some View {
        ZStack {
            background
            if let image = PointerHighlightPreview.image(for: style, ink: ink, scale: previewScale) {
                Image(nsImage: image)
                    .resizable()
                    .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side)
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
