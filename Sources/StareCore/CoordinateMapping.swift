import CoreGraphics
import Foundation

/// Conversions between the three coordinate spaces Stare deals with:
///
/// - **AppKit view space**: bottom-left origin, points.
/// - **Overlay space**: top-left origin, points, local to one display. Every
///   stroke point and every capture lives here.
/// - **Capture pixel space**: top-left origin, pixels, one image of one display.
public enum CoordinateMapping {
    /// Flips a point from bottom-left origin into top-left origin.
    public static func flipped(_ point: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: height - point.y)
    }

    /// Converts an overlay-space point to capture pixels.
    public static func toPixels(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    public static func toPixels(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        )
    }

    /// Converts capture pixels back into overlay space, for capture editing.
    public static func toPoints(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard scale != 0 else { return .zero }
        return CGRect(
            x: rect.origin.x / scale,
            y: rect.origin.y / scale,
            width: rect.size.width / scale,
            height: rect.size.height / scale
        )
    }

    /// Area drag. Works in any direction, so dragging up-left is not empty.
    public static func normalizedRect(from first: CGPoint, to second: CGPoint) -> CGRect {
        PathBuilder.normalizedRect(from: first, to: second)
    }

    /// Clamps a rect to the bounds of one display, used by area capture.
    public static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        rect.intersection(bounds)
    }

    /// Maps a point in global screen coordinates (bottom-left origin, spanning
    /// every display) into a display-local overlay point.
    public static func overlayPoint(
        fromScreenPoint screenPoint: CGPoint,
        screenFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: screenPoint.x - screenFrame.minX,
            y: screenFrame.maxY - screenPoint.y
        )
    }
}
