import XCTest
@testable import WiredSwift

final class WiredSwiftTests: XCTestCase {
    let specURL = URL(string: "httpw://wired.read-write.fr/wired.xml")!

    func testUrl() {
        let url = Url(withString: "wired://guest:password@localhost:4871")
        
        XCTAssert(url.scheme == "wired")
        XCTAssert(url.login == "guest")
        XCTAssert(url.password == "password")
        XCTAssert(url.hostname == "localhost")
        XCTAssert(url.port == 4871)
    }
    
    
    func testConnect() {
        Logger.setMaxLevel(.VERBOSE)
        guard let spec = P7Spec(withUrl: specURL) else {
            XCTFail()
            return
        }
        
        let url = Url(withString: "wired://wired.read-write.fr")
        let connection = Connection(withSpec: spec)
        
        XCTAssert(connection.connect(withUrl: url) == true)
    }


    static var allTests = [
        ("testUrl", testUrl),
        ("testConnect", testConnect),
    ]
}
