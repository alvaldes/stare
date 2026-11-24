import Foundation

/// Who a capture is named after.
///
/// Contract, up front: `appName` returns nil in, nil out — no frontmost name
/// or no frontmost process identifier means no name — and a frontmost
/// process that is Stare itself (`pid == ownProcessIdentifier`) means nil as
/// well, because the `{app}` token must name what was captured, never the
/// tool: during a capture from the whiteboard, or straight after the overlay
/// opens, Stare can be the frontmost application, and a file named after it
/// is a silent lie. `ownProcessIdentifier` is a parameter (defaulting to
/// this process's identifier) precisely so the own-pid rule is testable with
/// a fixed value instead of a live one.
public enum CaptureAppIdentity {
    /// The name to use for `{app}`, per the contract above, or nil when there
    /// is none. A nil makes the template refuse and fall back to the prefix
    /// name, which is the honest outcome.
    public static func appName(
        frontmostName: String?,
        frontmostProcessIdentifier: Int32?,
        ownProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) -> String? {
        guard let name = frontmostName, let pid = frontmostProcessIdentifier else { return nil }
        return pid == ownProcessIdentifier ? nil : name
    }
}
