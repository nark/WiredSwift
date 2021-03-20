import XCTest
@testable import WiredSwift

final class WiredSwiftTests: XCTestCase {
    let specURL = URL(string: "https://wired.read-write.fr/wired.xml")!
    //let serverURL = Url(withString: "wired://wired.read-write.fr")
    let serverURL = Url(withString: "wired://127.0.0.1")
    
    func testUrl() {
        let url = Url(withString: "wired://guest:password@localhost:4871")

        XCTAssert(url.scheme == "wired")
        XCTAssert(url.login == "guest")
        XCTAssert(url.password == "password")
        XCTAssert(url.hostname == "localhost")
        XCTAssert(url.port == 4871)
    }
    
    
    func testChecksum() {
        print("12345678901".sha1())
        print("12345678901".sha256())
        print("12345678901".sha512())
    }


    func testConnect() {
        Logger.setMaxLevel(.VERBOSE)

        guard let spec = P7Spec(withUrl: specURL) else {
            XCTFail()
            return
        }

        let connection = Connection(withSpec: spec, delegate: self)
        connection.clientInfoDelegate = self

        XCTAssert(connection.connect(withUrl: serverURL, cipher: .RSA_AES_256_SHA256, checksum: .SHA256) == true)
    }
    
    
    
    func testReconnect() {
        Logger.setMaxLevel(.VERBOSE)

        guard let spec = P7Spec(withUrl: specURL) else {
            XCTFail()
            return
        }

        let connection = Connection(withSpec: spec, delegate: self)
        connection.clientInfoDelegate = self
        
        if connection.connect(withUrl: serverURL) {
            sleep(1)
            
            connection.disconnect()
            
            sleep(1)
            
            _ = connection.reconnect()
            
            XCTAssert(connection.joinChat(chatID: 1) == true)
        }
    }
    
    
    func testBlockConnect() {
        Logger.setMaxLevel(.VERBOSE)
        
        guard let spec = P7Spec(withUrl: specURL) else {
            XCTFail()
            return
        }
        
        let connection = BlockConnection(withSpec: spec, delegate: self)
        
        if connection.connect(withUrl: serverURL) {
            var totalBoards = 0
            var loadedBoardThreads = 0
            let message = P7Message(withName: "wired.board.get_boards", spec: spec)
            
            connection.send(message: message, progressBlock: { (response) in
                Logger.info("progressBlock: \(response.name!)")
                
                if response.name == "wired.board.board_list", let board = response.string(forField: "wired.board.board") {
                    totalBoards += 1
                    
                    let message2 = P7Message(withName: "wired.board.get_threads", spec: spec)
                    message2.addParameter(field: "wired.board.board", value: board)
                    
                    connection.send(message: message2, progressBlock: { (response2) in
                        if let subject = response2.string(forField: "wired.board.subject") {
                            Logger.info("\(board) > \(subject)")
                        }
                    }) { (response2) in
                        if response2?.name == "wired.board.thread_list.done" {
                            loadedBoardThreads += 1
                            
                            Logger.info("totalBoards: \(totalBoards)")
                            Logger.info("loadedBoardThreads: \(loadedBoardThreads)")
                            
                            if loadedBoardThreads == totalBoards {
                                Logger.info("LOAD FINISHED")
                            }
                        }
                    }
                }
            }) { (response) in
                if let r = response {
                    //Logger.info("completionBlock: \(r.name!)")
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
    
    
    func testServer() {
        guard let spec = P7Spec(withUrl: specURL) else {
            XCTFail()
            return
        }
        
        let server = Server(port: 4871, spec: spec)
        server.listen()
    }


    static var allTests = [
        ("testUrl", testUrl),
        ("testConnect", testConnect),
        ("testUploadFile", testUploadFile),
        ("testServer", testServer),
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
