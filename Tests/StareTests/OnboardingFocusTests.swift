import AppKit
import XCTest
@testable import Stare

/// S5 of the Setup Guide redesign asks for a visible focus and Return as the
/// primary action. The guide takes the primary's focus explicitly, after its
/// first layout (`OnboardingView`, "give the primary action focus after
/// layout"), and re-asserts it when a window becomes key — so the rule that
/// decides *which* key-window change counts is pinned here.
///
/// Every window the app owns posts `NSWindow.didBecomeKeyNotification`. Settings
/// or the capture editor becoming key says nothing about the guide, and moving
/// the guide's focus from another window's event would be a defect.
@MainActor
final class OnboardingFocusTests: XCTestCase {
    func testOnlyTheGuideWindowReassertsFocus() {
        let guide = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let other = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(
            OnboardingView.shouldReassertFocus(
                for: Notification(name: NSWindow.didBecomeKeyNotification, object: guide),
                guideWindow: guide
            ),
            "the guide's own window becoming key re-arms its primary action"
        )
        XCTAssertFalse(
            OnboardingView.shouldReassertFocus(
                for: Notification(name: NSWindow.didBecomeKeyNotification, object: other),
                guideWindow: guide
            ),
            "a sibling window becoming key must not move the guide's focus"
        )
        XCTAssertFalse(
            OnboardingView.shouldReassertFocus(
                for: Notification(name: NSWindow.didBecomeKeyNotification, object: nil),
                guideWindow: guide
            ),
            "a notification with no window names nothing to re-arm"
        )
        XCTAssertFalse(
            OnboardingView.shouldReassertFocus(
                for: Notification(name: NSWindow.didBecomeKeyNotification, object: guide),
                guideWindow: nil
            ),
            "before the guide knows its window there is nothing to match"
        )
    }
}
