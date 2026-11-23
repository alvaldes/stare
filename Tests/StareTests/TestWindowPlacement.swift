import AppKit

extension NSWindow {
    /// Keeps a test's window on the primary display's visible frame before it
    /// is ordered front.
    ///
    /// A borderless window ordered front lands where the system puts it — the
    /// screen with the pointer — so a test run can flash windows on whatever
    /// monitor the human happens to be reading. Every render test in this
    /// target parks its window here first; the peer branch's capture tests have
    /// their own `PrimaryScreenTestWindow` helper for the same reason, and the
    /// two should collapse into one when that branch lands.
    func confineToPrimaryScreen() {
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        var frame = frame
        frame.origin = CGPoint(x: visible.minX + 40, y: visible.minY + 40)
        setFrame(frame, display: false)
    }
}
