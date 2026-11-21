import AppKit

/// Borderless, transparent window stretched over one display. A plain `NSWindow`
/// subclass rather than `NSPanel`: panels add key-window and floating behaviour
/// that made the overlay a non-interactive layer. Only `canBecomeKey` is
/// overridden, which is all a borderless overlay needs to receive clicks and
/// keys.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// `opaqueBoard` builds the whiteboard layer (T6): same proven key and
    /// click configuration, but an opaque window since the board itself covers
    /// the screen instead of drawing over the desktop.
    init(screen: NSScreen, opaqueBoard: Bool = false) {
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
        isOpaque = opaqueBoard
        backgroundColor = opaqueBoard ? .black : .clear
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
