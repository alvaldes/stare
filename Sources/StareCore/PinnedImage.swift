import CoreGraphics
import Foundation

/// The pure decisions behind pinning the captured image (T4/S6): the window's
/// initial size and placement, how scroll resizes it, how opacity steps, the
/// click-through lock state machine, which pinned window a lock toggle
/// reaches, and where the hover controls sit. The AppKit window is thin glue
/// over this file — every determinable behaviour is decided here so it can be
/// tested without a screen.
public enum PinnedImageGeometry {
    /// The largest size a pinned image opens at. A capture is display-sized
    /// pixels; floating it at one point per pixel would cover the screen.
    public static let maxInitialSize = CGSize(width: 560, height: 420)

    /// The width below which shrinking stops: a pinned image that cannot be
    /// read is a pin that was resized away by accident.
    public static let minWidth: CGFloat = 100

    /// Each scroll notch scales the image by this factor.
    public static let resizeStep: Double = 1.1

    /// Opacity steps and limits for ⌥-scroll.
    public static let minimumOpacity: CGFloat = 0.2
    public static let opacityStep: CGFloat = 0.1

    /// The initial window size: the image at its own point size (one pixel
    /// per point) when that fits both the initial cap and `bounds`, otherwise
    /// scaled down to fit inside the cap — which itself never exceeds
    /// `bounds` — aspect preserved, never upscaled.
    public static func initialSize(imageSize: CGSize, bounds: CGSize) -> CGSize {
        let image = CGSize(width: max(imageSize.width, 1), height: max(imageSize.height, 1))
        let cap = CGSize(
            width: min(maxInitialSize.width, bounds.width),
            height: min(maxInitialSize.height, bounds.height)
        )
        let scale = min(1, cap.width / image.width, cap.height / image.height)
        return CGSize(
            width: (image.width * scale).rounded(),
            height: (image.height * scale).rounded()
        )
    }

    /// The initial origin: centred inside `bounds`, clamped so the whole
    /// window stays there even when the bounds are smaller than the window.
    public static func initialOrigin(size: CGSize, in bounds: CGRect) -> CGPoint {
        var x = bounds.midX - size.width / 2
        var y = bounds.midY - size.height / 2
        x = max(bounds.minX, min(x, bounds.maxX - size.width))
        y = max(bounds.minY, min(y, bounds.maxY - size.height))
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    /// One resize step: the width grows or shrinks by the step factor per
    /// unit of `steps`, the height follows the frame's own aspect, both are
    /// clamped to the screen (`bounds`) and the minimum width, and the window
    /// stays centred on where it was, clamped inside the screen. Steps are
    /// signed: positive grows.
    public static func resizedFrame(_ frame: CGRect, steps: CGFloat, in bounds: CGRect) -> CGRect {
        guard frame.width > 0, frame.height > 0, bounds.width > 0, bounds.height > 0 else {
            return frame
        }
        var width = frame.width * CGFloat(pow(resizeStep, Double(steps)))
        width = max(minWidth, min(width, bounds.width))
        var height = width * frame.height / frame.width
        if height > bounds.height {
            // A tall image fits the screen height first; the width follows the
            // aspect and still respects the floor.
            height = bounds.height
            width = max(min(minWidth, bounds.width), height * frame.width / frame.height)
        }
        let centerX = max(
            bounds.minX + width / 2,
            min(frame.midX, bounds.maxX - width / 2)
        )
        let centerY = max(
            bounds.minY + height / 2,
            min(frame.midY, bounds.maxY - height / 2)
        )
        return CGRect(
            x: (centerX - width / 2).rounded(),
            y: (centerY - height / 2).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }

    /// One opacity step in `direction` (positive brighter), clamped between
    /// the floor and fully opaque, always a clean tenth.
    public static func steppedOpacity(_ current: CGFloat, direction: CGFloat) -> CGFloat {
        let sign = direction >= 0 ? 1.0 : -1.0
        let stepped = current + sign * opacityStep
        return (max(minimumOpacity, min(1, stepped)) * 100).rounded() / 100
    }
}

/// The click-through lock of one pinned image (T4/S6). Floating, the image
/// receives clicks, drags and scroll. Locked, the surface passes every
/// mouse event through to the app underneath **except** the close and lock
/// controls, which keep answering — the lock must be escapable with the
/// pointer, so it never covers the ✕ or the 🔒. The same toggle unlocks.
public enum PinnedImageLockState: Equatable, Sendable {
    case floating
    case locked

    public var toggled: PinnedImageLockState {
        self == .floating ? .locked : .floating
    }

    /// Whether a mouse point must reach the window's surface (T4 closing
    /// fix): floating, every point does. Locked, only the two controls do —
    /// the lock never covers its own way out, so a click-through image can
    /// always be unlocked and closed with the pointer, and every other point
    /// falls through to the app underneath. The caller (the view's hit test)
    /// turns a false answer into click passthrough; `bounds` is the view's
    /// own top-down space, the one `PinnedImageControls.rect` speaks.
    public func acceptsMouseEvents(at point: CGPoint, in bounds: CGRect) -> Bool {
        switch self {
        case .floating:
            return true
        case .locked:
            return PinnedImageControls.rects(in: bounds).contains { $0.contains(point) }
        }
    }
}

/// Which pinned window the lock toggle reaches: pinned windows share one
/// window level, so the frontmost one is the most recently pinned, and the
/// toggle hits the frontmost window whose frame contains the pointer.
public enum PinnedImageFocus {
    /// The index in `frames` of the topmost window under the point — the last
    /// entry whose frame contains it, because later entries were pinned in
    /// front — or nil when the point is over none of them and nothing may
    /// change.
    public static func topmostIndex(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        for index in stride(from: frames.count - 1, through: 0, by: -1) where frames[index].contains(point) {
            return index
        }
        return nil
    }
}

/// Where the pinned image's hover controls sit, in top-down view coordinates
/// (the pinned view is flipped): a close control and a lock control in one
/// row across the top-right corner. Also used for hit-testing in the view's
/// mouse-down, so the visible button and the clickable area are one truth.
public enum PinnedImageControls {
    public enum Kind: String, CaseIterable {
        case close
        case lock
    }

    /// The round control's side and its inset from the corner.
    public static let controlSize: CGFloat = 16
    public static let cornerInset: CGFloat = 5

    /// The rect of `kind` inside `bounds`: close is the rightmost control,
    /// lock sits to its left, both on the same row near the top.
    public static func rect(for kind: Kind, in bounds: CGRect) -> CGRect {
        let rowY = cornerInset
        let slot = controlSize + cornerInset
        switch kind {
        case .close:
            return CGRect(
                x: bounds.maxX - cornerInset - controlSize,
                y: rowY,
                width: controlSize,
                height: controlSize
            )
        case .lock:
            return CGRect(
                x: bounds.maxX - cornerInset - slot - controlSize,
                y: rowY,
                width: controlSize,
                height: controlSize
            )
        }
    }

    /// Both controls' rects, the complete clickable area of the surface. The
    /// locked state's hit test admits exactly these and nothing else.
    public static func rects(in bounds: CGRect) -> [CGRect] {
        Kind.allCases.map { rect(for: $0, in: bounds) }
    }
}

/// The fixed bindings of the pinned image's own shortcuts (T4/S6). They are
/// deliberately outside the persisted, remappable `HotkeyBindings` map: the
/// four registered actions keep their Settings pane, and this feature decided
/// against a new one. ⌥⇧I pins/dismisses per `PinnedImagePinRule`; ⌥⇧L
/// toggles the lock of the pinned image under the pointer. Neither collides
/// with ⌥⇧A, ⌥⇧M, ⌥⇧P, ⌥⇧W, ⌥S, ⇧S, S or the ⌥⇧O reserved for OCR.
public enum PinnedImageHotkeyDefaults {
    public static let pin = HotkeyBinding(key: .i, modifiers: [.option, .shift])
    public static let pinDisplayName = "⌥⇧I"

    public static let lock = HotkeyBinding(key: .l, modifiers: [.option, .shift])
    public static let lockDisplayName = "⌥⇧L"
}

/// What ⌥⇧I does on a press (T4 closing fix): a keyboard user pressing the
/// same key twice must never hold a stack they cannot take down. The rule
/// is one key, one pin lifecycle — the first press pins the session's
/// latest capture, the next press takes the frontmost pinned image down,
/// exactly the open/close pairing every other surface key of this app has
/// (⌥⇧A opens, Esc closes; ⌥⇧P toggles). Deliberately keeping two pins is
/// still one click away, on the capture card's pin button.
public enum PinnedImagePinAction: Equatable, Sendable {
    case pin
    case dismissTopmost
    case nothingToPin
}

public enum PinnedImagePinRule {
    /// The keyboard decision: pins on screen win (dismiss the frontmost,
    /// locked or not — the keyboard reaches a click-through window where the
    /// pointer cannot); a clear screen pins the latest capture; nothing
    /// captured yet is a reportable no-op instead of a silent one.
    public static func keyboardPin(hasPinnedImages: Bool, hasCaptures: Bool) -> PinnedImagePinAction {
        if hasPinnedImages { return .dismissTopmost }
        return hasCaptures ? .pin : .nothingToPin
    }
}

/// What a pinned-image shortcut says when it cannot act (T4 closing fix):
/// the same one-line pill vocabulary the capture and OCR paths already use.
/// Nothing here opens a window — the coordinator reports, the app layer
/// decides where the pill shows.
public enum PinnedImageFeedback: Equatable, Sendable {
    case noPinnedImageUnderPointer
    case nothingCapturedYet

    public var title: String {
        switch self {
        case .noPinnedImageUnderPointer:
            "No pinned image under the pointer"
        case .nothingCapturedYet:
            "Nothing captured yet"
        }
    }
}
