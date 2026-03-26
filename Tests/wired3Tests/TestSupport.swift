import Foundation
import XCTest
import WiredSwift
@testable import wired3Lib

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wired3-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeDatabaseController(tempDir: URL) -> DatabaseController {
    let dbURL = tempDir.appendingPathComponent("wired3.sqlite")
    let controller = DatabaseController(baseURL: dbURL, spec: P7Spec(withPath: nil))
    XCTAssertTrue(controller.initDatabase(), "Database initialization should succeed")
    return controller
}

func makeClient(userID: UInt32) -> Client {
    let socket = P7Socket(hostname: "localhost", port: 0, spec: P7Spec(withPath: nil))
    return Client(userID: userID, socket: socket)
}
