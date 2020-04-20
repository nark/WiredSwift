import XCTest
@testable import WiredSwift

final class WiredSwiftTests: XCTestCase {
    let specURL = URL(string: "https://wired.read-write.fr/wired.xml")!

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
        //let url = Url(withString: "wired://localhost")
        
        let connection = Connection(withSpec: spec, delegate: self)
        connection.clientInfoDelegate = self
        
        XCTAssert(connection.connect(withUrl: url, cipher: .NONE) == true)
    }


    static var allTests = [
        ("testUrl", testUrl),
        ("testConnect", testConnect),
    ]
}



extension WiredSwiftTests: ConnectionDelegate {
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
}


extension WiredSwiftTests: ClientInfoDelegate {
    func clientInfoApplicationName(for connection: Connection) -> String? {
        return "WiredSwiftTests"
    }
    
    func clientInfoApplicationVersion(for connection: Connection) -> String? {
        return "1.0"
    }
    
    func clientInfoApplicationBuild(for connection: Connection) -> String? {
        return "1"
    }
}
