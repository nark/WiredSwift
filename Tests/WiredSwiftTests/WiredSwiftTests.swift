import XCTest
@testable import WiredSwift

final class WiredSwiftTests: XCTestCase {
    let specURL = URL(string: "https://wired.read-write.fr/wired.xml")!
    let serverURL = Url(withString: "wired://wired.read-write.fr")
    //let serverURL = Url(withString: "wired://localhost")
    
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

        let connection = Connection(withSpec: spec, delegate: self)
        connection.clientInfoDelegate = self

        XCTAssert(connection.connect(withUrl: serverURL) == true)
    }
    
    
    func testBlockConnect() {
        Logger.setMaxLevel(.VERBOSE)
        
        guard let spec = P7Spec(withUrl: specURL) else {
            XCTFail()
            return
        }
        
        let connection = BlockConnection(withSpec: spec, delegate: self)
        
        if connection.connect(withUrl: serverURL) {
            let message = P7Message(withName: "wired.board.get_boards", spec: spec)
            
            connection.send(message: message, progressBlock: { (response) in
                Logger.info("progressBlock: \(response.name!)")
                
                if response.name == "wired.board.board_list", let board = response.string(forField: "wired.board.board") {
                    
                    let message2 = P7Message(withName: "wired.board.get_threads", spec: spec)
                    message2.addParameter(field: "wired.board.board", value: board)
                    
                    connection.send(message: message2, progressBlock: { (response2) in
                        if let subject = response2.string(forField: "wired.board.subject") {
                            Logger.info("\(board) > \(subject)")
                        }
                    }) { (response2) in
                        Logger.info("boards and thread loaded")
                    }
                }
            }) { (response) in
                if let r = response {
                    Logger.info("completionBlock: \(r.name!)")
                }
            }            
        }
        
        // run this test at least 1 minute
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .minute, value: 1, to: Date())
        RunLoop.main.run(until: date!)
    }
    

    func testUploadFile() {
        guard let spec = P7Spec(withUrl: specURL) else {
            XCTFail()
            return
        }

        let connection = Connection(withSpec: spec, delegate: self)
        connection.clientInfoDelegate = self
        connection.interactive = false

        // create a secondary connection
        if (connection.connect(withUrl: serverURL) == false) {

        }
    }


    static var allTests = [
        ("testUrl", testUrl),
        ("testConnect", testConnect),
        ("testUploadFile", testUploadFile),
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
