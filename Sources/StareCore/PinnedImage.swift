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
/// receives clicks, drags and scroll. Locked, the whole window ignores mouse
/// events so the user works in the app underneath; the unlock path is the
/// lock toggle's global shortcut, because a click-through window cannot be
/// hovered or clicked by definition.
public enum PinnedImageLockState: Equatable, Sendable {
    case floating
    case locked

    /// Whether the window's surface should answer the pointer right now.
    public var acceptsMouseEvents: Bool {
        self == .floating
    }

    public var toggled: PinnedImageLockState {
        self == .floating ? .locked : .floating
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
}

/// The fixed bindings of the pinned image's own shortcuts (T4/S6). They are
/// deliberately outside the persisted, remappable `HotkeyBindings` map: the
/// four registered actions keep their Settings pane, and this feature decided
/// against a new one. ⌥⇧I pins the latest capture; ⌥⇧L toggles the lock of
/// the pinned image under the pointer. Neither collides with ⌥⇧A, ⌥⇧M, ⌥⇧P,
/// ⌥⇧W, ⌥S, ⇧S, S or the ⌥⇧O reserved for OCR.
public enum PinnedImageHotkeyDefaults {
    public static let pin = HotkeyBinding(key: .i, modifiers: [.option, .shift])
    public static let pinDisplayName = "⌥⇧I"

    public static let lock = HotkeyBinding(key: .l, modifiers: [.option, .shift])
    public static let lockDisplayName = "⌥⇧L"
}
