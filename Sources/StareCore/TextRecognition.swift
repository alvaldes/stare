import CoreGraphics
import Foundation

/// The pure decisions of on-device text and QR recognition (T5/S7):
/// how observations become the clipboard string, the plan for the
/// selection, the crop of a screen selection into display pixels, and the
/// user-facing copy. The Vision glue lives in the app layer
/// (`Stare/TextRecognitionClient.swift`); nothing here runs a network call —
/// Vision recognition is on-device by construction (S8).
///
/// Nothing collides with anything else this app answers to. The pinned-image
/// contract already reserved ⌥⇧O for OCR (`PinnedImageHotkeyDefaults`); this
/// feature takes it, and the collision test in `TextRecognitionTests` pins
/// that it stays free.
public enum TextRecognitionHotkeyDefaults {
    public static let binding = HotkeyBinding(key: .o, modifiers: [.option, .shift])
    public static let displayName = "⌥⇧O"
}

/// One recognition observation: a text line or a QR payload, with the centre
/// of its bounding box in the recognition image's own coordinate space
/// (bottom-left origin, as Vision reports it), so **larger `centerY` means
/// higher on the page** and **larger `centerX` means further right**.
public struct TextRecognitionObservation: Equatable, Sendable {
    public let payload: String
    public let centerY: Double
    public let centerX: Double

    public init(payload: String, centerY: Double, centerX: Double) {
        self.payload = payload
        self.centerY = centerY
        self.centerX = centerX
    }
}

/// What a recognition produced: a non-empty clipboard string, or nothing —
/// an empty result is reported, never copied (a silent empty copy would
/// clobber the user's clipboard).
public enum TextRecognitionOutcome: Equatable, Sendable {
    case clipboard(String)
    case nothingFound
}

/// The capture plan a finished selection gets (T5/S7):
///
/// - **Undersize** — a drag below the 4×4 stray-click minimum
///   (`AreaSelectionGeometry.isCaptureWorthy`) dismisses the gesture: no
///   capture, no recognition, clipboard untouched.
/// - **In budget** — the selection is recognised at its own display scale.
/// - **Oversize** — a selection whose longest pixel side would pass the
///   pixel budget is downscaled to exactly that budget before Vision sees
///   it, so selecting a whole display cannot hand the recogniser a
///   framebuffer-sized image.
public enum TextCapturePlan: Equatable, Sendable {
    case dismiss
    case capture(scale: CGFloat)
}

public enum TextRecognition {
    /// The longest pixel side recognition accepts before a downscale kicks
    /// in. Vision itself accepts large inputs, but a whole-display drag
    /// should not cost framebuffer-size memory and time for text.
    public static let maxPixelSideDefault: CGFloat = 4096

    /// The 4×4 stray-click minimum area capture already trusts.
    public static let minimumSelection = CGSize(width: 4, height: 4)

    /// Turns observations into the clipboard string. The invariant it holds:
    /// the reading order — top to bottom, left to right within one line — is
    /// decided by position, not by kind or arrival order, so text and QR
    /// payloads interleave exactly the way they appear on screen. Each
    /// observation's own edge whitespace is trimmed; interior text is kept.
    /// An empty or whitespace-only result is `.nothingFound`.
    public static func clipboardOutcome(
        from observations: [TextRecognitionObservation]
    ) -> TextRecognitionOutcome {
        let lines = observations
            .filter { !$0.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.centerY != rhs.centerY { return lhs.centerY > rhs.centerY }
                return lhs.centerX < rhs.centerX
            }
            .map { $0.payload.trimmingCharacters(in: .whitespacesAndNewlines) }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .nothingFound : .clipboard(text)
    }

    /// The plan for a finished selection, in screen points on the display
    /// the pointer chose. See `TextCapturePlan` for the three cases.
    public static func plan(
        selection: CGRect,
        displayScale: CGFloat,
        minimum: CGSize = minimumSelection,
        maxPixelSide: CGFloat = maxPixelSideDefault
    ) -> TextCapturePlan {
        guard AreaSelectionGeometry.isCaptureWorthy(selection, minimum: minimum) else {
            return .dismiss
        }
        let longestPixelSide = max(selection.width, selection.height) * displayScale
        guard longestPixelSide > maxPixelSide else { return .capture(scale: displayScale) }
        return .capture(scale: displayScale * (maxPixelSide / longestPixelSide))
    }

    /// Maps a selection from global screen coordinates (bottom-left origin,
    /// spanning every display) into the capture's pixel space (top-left
    /// origin, local to the display the selection sits on) — the same two
    /// mappings area capture already trusts (`CoordinateMapping`), composed
    /// for a rectangle.
    public static func cropRect(
        selection: CGRect,
        in screenFrame: CGRect,
        pixelScale: CGFloat
    ) -> CGRect {
        let top = CoordinateMapping.flipped(
            CGPoint(x: selection.minX, y: selection.maxY),
            height: screenFrame.height
        )
        return CoordinateMapping.toPixels(
            CGRect(origin: CGPoint(x: selection.minX - screenFrame.minX, y: top.y),
                   size: selection.size),
            scale: pixelScale
        )
    }
}

/// The user-facing copy the gesture reports through its own hint surface.
/// The missing-permission line reuses the exact copy the drawing overlay
/// shows today (`OverlayController`), so the app says the same thing the
/// same way everywhere — and never opens a system prompt mid-gesture: the
/// copy points at System Settings instead.
public enum TextRecognitionFeedback: Equatable, Sendable {
    case permissionMissing
    case nothingFound
    case failed

    public var title: String {
        switch self {
        case .permissionMissing:
            "Screen Recording permission needed · System Settings → Privacy"
        case .nothingFound:
            "No text found"
        case .failed:
            "Text recognition failed"
        }
    }
}
