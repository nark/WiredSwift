import XCTest
@testable import WiredSwift

final class UrlTests: XCTestCase {

    // MARK: - Full URL

    func testFullUrl() {
        let url = Url(withString: "wired://guest:password@localhost:4871")
        XCTAssertEqual(url.scheme, "wired")
        XCTAssertEqual(url.login, "guest")
        XCTAssertEqual(url.password, "password")
        XCTAssertEqual(url.hostname, "localhost")
        XCTAssertEqual(url.port, 4871)
    }

    // MARK: - Defaults

    func testDefaultPort() {
        let url = Url(withString: "wired://user@localhost")
        XCTAssertEqual(url.port, Wired.wiredPort)
    }

    func testDefaultLogin() {
        let url = Url(withString: "wired://localhost")
        XCTAssertEqual(url.login, "guest")
    }

    func testEmptyPassword() {
        let url = Url(withString: "wired://user@localhost:4871")
        XCTAssertEqual(url.password, "")
    }

    // MARK: - Components

    func testCustomPort() {
        let url = Url(withString: "wired://user@host.example.com:9000")
        XCTAssertEqual(url.port, 9000)
        XCTAssertEqual(url.hostname, "host.example.com")
    }

    func testLoginWithoutPassword() {
        let url = Url(withString: "wired://admin@server.local:4871")
        XCTAssertEqual(url.login, "admin")
        XCTAssertEqual(url.password, "")
    }

    // MARK: - urlString()

    func testUrlString() {
        let url = Url(withString: "wired://user:pass@myserver.com:4871")
        XCTAssertEqual(url.urlString(), "wired://myserver.com:4871")
    }

    func testUrlStringWithCustomPort() {
        let url = Url(withString: "wired://user@myserver.com:9999")
        XCTAssertEqual(url.urlString(), "wired://myserver.com:9999")
    }
}
