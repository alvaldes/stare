import AppKit

/// Borderless, transparent window stretched over one display. A plain `NSWindow`
/// subclass rather than `NSPanel`: panels add key-window and floating behaviour
/// that made the overlay a non-interactive layer. Only `canBecomeKey` is
/// overridden, which is all a borderless overlay needs to receive clicks and
/// keys.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        // Matches the palette's behaviour, which is the configuration that
        // provably receives clicks. Space changes re-order the window instead of
        // joining every Space.
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false

        setFrame(screen.frame, display: false)
    }
}
