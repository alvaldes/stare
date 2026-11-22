import CoreGraphics

/// The arithmetic that turns a window's place on the display into a crop of the
/// image a window capture produced. Pure geometry, so it is testable without
/// pixels.
///
/// Precondition for every function here: `windowBounds` and `displayBounds` are
/// in the same global, top-left-origin space that `CGWindowListCopyWindowInfo`
/// and `CGDisplayBounds` use. The AppKit layer is responsible for never handing
/// over a bottom-left-origin frame.
public enum WindowCaptureGeometry {
    /// Where the window sits inside a full-display image of `displayBounds`,
    /// scaled to pixels and clamped so the crop can never leave the image.
    ///
    /// Returns `.zero` when nothing of the window overlaps the display: the
    /// caller then has no window to crop and should fall back to the whole
    /// image rather than composite marks onto nothing.
    public static func cropRect(
        windowBounds: CGRect,
        displayBounds: CGRect,
        scale: CGFloat,
        imageSize: CGSize
    ) -> CGRect {
        // A scale or an image of zero means there are no pixels to crop from,
        // and the arithmetic below would produce garbage rather than fail.
        guard scale > 0, imageSize.width > 0, imageSize.height > 0 else { return .zero }
        guard !windowBounds.isEmpty, !displayBounds.isEmpty else { return .zero }

        // Both rects are already in the same global top-left space, so the
        // window's position inside this display is a plain subtraction of the
        // display's origin.
        let local = CGRect(
            x: windowBounds.minX - displayBounds.minX,
            y: windowBounds.minY - displayBounds.minY,
            width: windowBounds.width,
            height: windowBounds.height
        )
        let scaled = CGRect(
            x: local.minX * scale,
            y: local.minY * scale,
            width: local.width * scale,
            height: local.height * scale
        )

        // A window hanging off the edge of its display is normal — a wide
        // window dragged half off-screen — so the crop clips instead of
        // failing. Anything with no overlap left is nothing to composite onto.
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let clamped = scaled.integral.intersection(imageBounds)
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return .zero }
        return clamped
    }
}
