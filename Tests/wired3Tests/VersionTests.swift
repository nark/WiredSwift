import XCTest
@testable import wired3Lib

final class VersionTests: XCTestCase {
    func testNumberMatchesMarketingVersion() {
        XCTAssertEqual(WiredServerVersion.number, WiredServerVersion.marketingVersion)
    }

    func testDisplayContainsAllVersionParts() {
        XCTAssertTrue(WiredServerVersion.display.contains(WiredServerVersion.marketingVersion))
        XCTAssertTrue(WiredServerVersion.display.contains(WiredServerVersion.buildNumber))
        XCTAssertTrue(WiredServerVersion.display.contains(WiredServerVersion.commit))
    }
}
