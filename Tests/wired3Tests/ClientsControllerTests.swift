import XCTest
import WiredSwift
@testable import wired3Lib

final class ClientsControllerTests: XCTestCase {
    func testAddClientStoresClientAndReturnsItByUserID() {
        let controller = ClientsController()
        let client = makeClient(userID: 111)

        controller.addClient(client: client)

        XCTAssertTrue(controller.user(withID: 111) === client)
        XCTAssertEqual(controller.connectedClientsSnapshot().count, 1)
    }

    func testAddClientDoesNotDuplicateSameUserID() {
        let controller = ClientsController()
        let first = makeClient(userID: 5)
        let second = makeClient(userID: 5)

        controller.addClient(client: first)
        controller.addClient(client: second)

        XCTAssertEqual(controller.connectedClientsSnapshot().count, 1)
        XCTAssertTrue(controller.user(withID: 5) === second)
    }

    func testRemoveClientDisconnectsSocketAndRemovesClient() {
        let controller = ClientsController()
        let client = makeClient(userID: 222)
        client.socket.connected = true

        controller.addClient(client: client)
        controller.removeClient(client: client)

        XCTAssertFalse(client.socket.connected)
        XCTAssertNil(controller.user(withID: 222))
        XCTAssertTrue(controller.connectedClientsSnapshot().isEmpty)
    }
}
