import CoreGraphics

/// Pure decisions of the area drag's magnifier (S11, T2b slice B).
///
/// While the area drag runs, a loupe follows the pointer showing the pixels
/// around it from the **frozen frame**, with a crosshair through the pointer's
/// pixel so the exact edge being chosen is visible. It never covers the pixel
/// being chosen: it hangs a gap away from the pointer, flips to the other side
/// near a display edge, and is clamped inside the display.
///
/// The loupe reads the frozen frame only. Without Screen Recording there is
/// no frozen frame (the drag then runs live, exactly as before the freeze),
/// so there is nothing truthful to magnify and the loupe stays absent — a
/// magnifier over the moving live screen would lie about the pixel edge being
/// chosen. The whiteboard never freezes either (no `onAreaSelectionFrame`
/// wiring), so a board drag never grows a loupe. The view paints all of this
/// from a `plan`; nothing here touches AppKit.
public enum AreaCaptureLoupe {
    /// Loupe side, in view points.
    public static let side: CGFloat = 120
    /// On-screen magnification: one source point paints `magnification`
    /// points. The source square is `side / magnification` around the pointer.
    public static let magnification: CGFloat = 4
    /// Gap between the pointer and the loupe's near edge, so the loupe never
    /// covers the pixel being chosen.
    public static let pointerGap: CGFloat = 24

    /// Everything the view paints, decided once: where the loupe sits, which
    /// pixels of the frozen frame it magnifies, where those pixels land, and
    /// where the pointer's pixel sits inside it — the crosshair's point.
    public struct Plan: Equatable {
        /// The loupe's frame in view space, never covering the pointer and
        /// never leaving the display.
        public let frame: CGRect
        /// The pixels of the frozen frame the loupe magnifies (top-left
        /// image origin, the convention `CGImage.cropping(to:)` crops by —
        /// the same one the editor's `EditorCropSpace` states). Clamped to
        /// the frame, so near a display edge the source stops at the frame's
        /// edge and nothing is invented.
        public let source: CGRect
        /// Where `source` lands in view space. Smaller than (or overhanging)
        /// `frame` near an edge: the empty rest of the loupe stays empty
        /// instead of stretching the pixels.
        public let destination: CGRect
        /// Where the pointer's pixel sits — the crosshair marks it.
        public let crosshair: CGPoint
    }

    /// Where the loupe paints, around `point` inside `bounds` (the display,
    /// top-left origin). The default side hangs below-right of the pointer;
    /// each axis flips to the other side when the default would leave the
    /// display; the result is clamped inside the display, and the side itself
    /// never exceeds the display.
    public static func frame(around point: CGPoint, bounds: CGRect) -> CGRect {
        frame(around: point, side: side, pointerGap: pointerGap, bounds: bounds)
    }

    /// The parameterized form the shipped defaults call and the tests
    /// exercise at display sizes the constants never meet.
    public static func frame(
        around point: CGPoint,
        side: CGFloat,
        pointerGap: CGFloat,
        bounds: CGRect
    ) -> CGRect {
        let fittedSide = min(side, max(bounds.width, 0), max(bounds.height, 0))
        let fitsRight = point.x + pointerGap + fittedSide <= bounds.maxX
        let fitsBelow = point.y + pointerGap + fittedSide <= bounds.maxY
        let x = fitsRight ? point.x + pointerGap : point.x - pointerGap - fittedSide
        let y = fitsBelow ? point.y + pointerGap : point.y - pointerGap - fittedSide
        return CGRect(
            x: min(max(x, bounds.minX), max(bounds.maxX - fittedSide, bounds.minX)),
            y: min(max(y, bounds.minY), max(bounds.maxY - fittedSide, bounds.minY)),
            width: fittedSide,
            height: fittedSide
        )
    }

    /// The loupe's plan for the pointer at `point` over the frozen frame, nil
    /// when there is nothing truthful to magnify: the pointer's source square
    /// misses the display, or the frame's pixel scale is unusable.
    public static func plan(
        at point: CGPoint,
        bounds: CGRect,
        framePixelSize: CGSize,
        pixelsPerPoint: CGFloat
    ) -> Plan? {
        guard bounds.width > 0, bounds.height > 0, pixelsPerPoint > 0 else { return nil }

        // The source square in view space, centred on the pointer, clamped to
        // the display: the drag is clamped too, but a drag event can land a
        // hair outside the window and must not invent pixels.
        let sourceSide = side / magnification
        let viewRect = CGRect(
            x: point.x - sourceSide / 2,
            y: point.y - sourceSide / 2,
            width: sourceSide,
            height: sourceSide
        ).intersection(bounds)
        guard !viewRect.isNull, !viewRect.isEmpty else { return nil }

        // To the frame's pixel coordinates. Both spaces here are top-left
        // origin: the view's y grows downward from `bounds.minY` and
        // `CGImage.cropping(to:)` crops from the frame's top row, so the
        // conversion is the bounds-relative offset itself — which also keeps
        // it correct when the display's view does not sit at (0,0).
        let pixelRect = CGRect(
            x: (viewRect.minX - bounds.minX) * pixelsPerPoint,
            y: (viewRect.minY - bounds.minY) * pixelsPerPoint,
            width: viewRect.width * pixelsPerPoint,
            height: viewRect.height * pixelsPerPoint
        )
        let source = pixelRect
            .intersection(CGRect(origin: .zero, size: framePixelSize))
            .integral
            .intersection(CGRect(origin: .zero, size: framePixelSize))
        guard !source.isNull, !source.isEmpty, source.width > 0, source.height > 0 else { return nil }

        // The freeze contract is one capture of the whole display, so the
        // pixel rect always covers `viewRect`; the pointer's pixel therefore
        // lands exactly at the projection below, and the crosshair marks the
        // pixel being chosen at the loupe's centre.
        let loupeFrame = frame(around: point, bounds: bounds)
        let centre = CGPoint(x: loupeFrame.midX, y: loupeFrame.midY)
        let destination = CGRect(
            x: centre.x - (point.x - viewRect.minX) * magnification,
            y: centre.y - (point.y - viewRect.minY) * magnification,
            width: viewRect.width * magnification,
            height: viewRect.height * magnification
        )
        return Plan(
            frame: loupeFrame,
            source: source,
            destination: destination,
            crosshair: centre
        )
    }
}
