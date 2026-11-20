import AppKit

/// Borderless, transparent, non-activating panel stretched over one display.
/// It floats above full-screen apps and joins every Space, so drawing works
/// over anything without the app ever becoming active.
final class OverlayPanel: NSPanel {
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
        // Same collection behaviour as the palette, which is the configuration
        // proven to receive clicks. `.canJoinAllSpaces` made the window a
        // non-interactive ghost outside the Space it was ordered in.
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

        setFrame(screen.frame, display: false)
    }
}
