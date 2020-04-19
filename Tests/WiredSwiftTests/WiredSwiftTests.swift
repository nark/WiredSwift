import XCTest
@testable import WiredSwift

final class WiredSwiftTests: XCTestCase {
    let specPath = Bundle(for: WiredSwiftTests.self).path(forResource: "wired", ofType: "xml")

    func testUrl() {
        print("specPath : \(specPath)")
        let spec = P7Spec(withPath: specPath)
        let url = Url(withString: "wired://guest:password@localhost:4871")
        
        XCTAssert(url.scheme == "wired")
        XCTAssert(url.login == "guest")
        XCTAssert(url.password == "password")
        XCTAssert(url.hostname == "localhost")
        XCTAssert(url.port == 4871)
    }
    
    
    func testConnect() {
        Logger.setMaxLevel(.VERBOSE)
        print("specPath : \(specPath)")
        let spec = P7Spec(withPath: specPath)
        let url = Url(withString: "wired://localhost")
        let connection = Connection(withSpec: spec)
        
        XCTAssert(connection.connect(withUrl: url) == true)
    }


    static var allTests = [
        ("testUrl", testUrl),
        ("testConnect", testConnect),
    ]
}
