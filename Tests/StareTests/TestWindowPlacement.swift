import AppKit

extension NSWindow {
    /// Keeps a test's window on the primary display's visible frame before it
    /// is ordered front.
    ///
    /// A borderless window ordered front lands where the system puts it — the
    /// screen with the pointer — so a test run can flash windows on whatever
    /// monitor the human happens to be reading. The arithmetic lives in
    /// `PrimaryScreenTestWindow` so there is exactly one implementation of the
    /// invariant; this method is the size-preserving spelling of it.
    func confineToPrimaryScreen() {
        guard let frame = PrimaryScreenTestWindow.frame(for: frame.size) else { return }
        setFrame(frame, display: false)
    }
}
