import Foundation

/// Who a capture is named after.
///
/// The `{app}` token must name what was captured, never Stare itself: during a
/// capture from the whiteboard, or straight after the overlay opens, Stare can
/// be the frontmost application, and a file named after the tool is a silent
/// lie. The rule is one comparison, so it lives here — pure, and pinned — rather
/// than inline at the call site where nothing can test it.
public enum CaptureAppIdentity {
    /// The name to use for `{app}`, or nil when the frontmost application is us
    /// (or when there is none). A nil makes the template refuse and fall back to
    /// the prefix name, which is the honest outcome.
    public static func appName(
        frontmostName: String?,
        frontmostProcessIdentifier: Int32?,
        ownProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) -> String? {
        guard let name = frontmostName, let pid = frontmostProcessIdentifier else { return nil }
        return pid == ownProcessIdentifier ? nil : name
    }
}
