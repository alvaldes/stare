import AppKit
import XCTest

// MARK: - Leave-as-found hooks for the process's live AppKit state

/// The leave-as-found hooks the hooked classes share (round four, the
/// cross-test contamination follow-ups in `odd/tasks/round-four.md`): the
/// xctest runner spins no AppKit state away between classes, so a `.set()`
/// cursor, an activation, a Dock-presence policy flip and a standing key
/// window all outlive the class that made them. `TextSelectionWindowTests`
/// shares this process and reads exactly that state — its baseline reads
/// `NSCursor.current` and its keyings read `NSApp.keyWindow` — so each
/// hooked class captures here in `setUp` and restores in `tearDown`: one
/// implementation of the invariant, in the same family as
/// `PrimaryScreenTestWindow`'s screen placement.
@MainActor
enum LeaveAsFound {
    /// What the process looked like before the class ran.
    struct State {
        let cursor: NSCursor?
        let isActive: Bool
        let policy: NSApplication.ActivationPolicy
    }

    /// Called in `setUp`. This may create the shared application itself: the
    /// hooks run outside the class's test bodies, so they cannot read the
    /// nil-before-init `NSApp` global (the crash the first hook run felt),
    /// but `NSApplication.shared` always answers.
    static func capture() -> State {
        let app = NSApplication.shared
        return State(
            cursor: NSCursor.current,
            isActive: app.isActive,
            policy: app.activationPolicy())
    }

    /// Called in `tearDown`. The order keeps each hook from undoing the next:
    /// the policy first (a flip can deactivate the app as a side effect),
    /// then the active flag the way `NSApp` gives it up, then the key window
    /// — resigning is the same exit the window's own close and order-out
    /// path takes — and the cursor last so nothing in between re-asserts
    /// one. Restoration is only ever `set()`: no cursor stack push/pop that
    /// the product code does not participate in.
    static func restore(_ found: State) {
        let app = NSApplication.shared
        if app.activationPolicy() != found.policy {
            app.setActivationPolicy(found.policy)
        }
        if app.isActive != found.isActive, app.isActive {
            app.deactivate()
        }
        app.keyWindow?.resignKey()
        found.cursor?.set()
    }
}

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
