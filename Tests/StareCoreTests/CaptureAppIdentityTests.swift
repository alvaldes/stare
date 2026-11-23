import XCTest
@testable import StareCore

final class CaptureAppIdentityTests: XCTestCase {
    private let own: Int32 = 4242

    /// The case a real user hits first: capturing from Stare's own whiteboard.
    func testStareInFrontNamesNothing() {
        XCTAssertNil(CaptureAppIdentity.appName(
            frontmostName: "Stare", frontmostProcessIdentifier: own, ownProcessIdentifier: own))
    }

    func testAnotherAppInFrontNamesIt() {
        XCTAssertEqual(CaptureAppIdentity.appName(
            frontmostName: "Safari", frontmostProcessIdentifier: 7, ownProcessIdentifier: own), "Safari")
    }

    func testNoFrontmostAppNamesNothing() {
        XCTAssertNil(CaptureAppIdentity.appName(
            frontmostName: nil, frontmostProcessIdentifier: nil, ownProcessIdentifier: own))
        XCTAssertNil(CaptureAppIdentity.appName(
            frontmostName: "Safari", frontmostProcessIdentifier: nil, ownProcessIdentifier: own))
    }
}
