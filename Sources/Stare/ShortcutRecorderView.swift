import AppKit
import SwiftUI
import StareCore

// The single-keystroke recorder shared by the Tools and Shortcuts panes
// (T8/T9/S6): clicking "Record" arms a capture, the next keystroke is
// delivered to the pane, and esc cancels. The capture runs through a real
// first-responder view, so what is recorded is what the system delivers —
// including the modifier flags for global hotkeys.

/// Human-readable form of a binding: fixed modifier order ⌃⌥⇧⌘ plus the key,
/// so ⌥⇧A reads exactly like the menu bar and the intro hint.
extension HotkeyBinding {
    var displayTitle: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + String(key.character).uppercased()
    }
}

/// An invisible first-responder view that forwards exactly one keystroke to
/// `onCapture` (or `onCancel` for esc). `includesModifiers` distinguishes the
/// two recorders: global hotkeys capture the held modifiers, tool shortcuts
/// capture the bare key only.
final class KeyCaptureView: NSView {
    var includesModifiers = true
    var onCapture: ((HotkeyBinding?) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // esc
            onCancel?()
            return
        }
        let characters = event.charactersIgnoringModifiers ?? ""
        guard let character = characters.first, let key = VirtualKey(character: character) else {
            onCapture?(nil)
            return
        }
        var modifiers: HotkeyModifiers = []
        if includesModifiers {
            let flags = event.modifierFlags
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.command) { modifiers.insert(.command) }
        }
        onCapture?(HotkeyBinding(key: key, modifiers: modifiers))
    }

    override func draw(_ dirtyRect: NSRect) {}
}

/// SwiftUI wrapper that owns the capture lifecycle: while `active`, the view
/// becomes the window's first responder (next runloop turn — the window is
/// often still settling when the flag flips) and swallows one key event.
struct KeyCaptureField: NSViewRepresentable {
    /// Global hotkeys record the held modifiers; tool keys ignore them.
    let includesModifiers: Bool
    let active: Bool
    let onCapture: (HotkeyBinding?) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onCapture = { onCapture($0) }
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: KeyCaptureView, context: Context) {
        view.includesModifiers = includesModifiers
        view.onCapture = { onCapture($0) }
        view.onCancel = onCancel
        guard active else {
            if view.window?.firstResponder === view {
                view.window?.makeFirstResponder(nil)
            }
            return
        }
        DispatchQueue.main.async {
            guard view.window?.firstResponder !== view else { return }
            view.window?.makeFirstResponder(view)
        }
    }
}
