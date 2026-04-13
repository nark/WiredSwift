import XCTest
import WiredSwift
@testable import wired3Lib

final class TrackerControllerTests: XCTestCase {
    func testTrackedServersPersistAcrossControllerRestart() throws {
        let tempDir = try makeTemporaryDirectory()
        let databaseController = makeDatabaseController(tempDir: tempDir)

        let controller1 = TrackerController(databaseController: databaseController)
        defer { controller1.stop() }

        let client = makeClient(userID: 1)
        client.ip = "203.0.113.10"

        let message = makeRegisterMessage()
        _ = try controller1.registerServer(client: client, message: message, allowedCategories: ["public"])

        let controller2 = TrackerController(databaseController: databaseController)
        defer { controller2.stop() }

        let servers = controller2.activeServersSnapshot()
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers.first?.sourceIP, "203.0.113.10")
        XCTAssertEqual(servers.first?.category, "public")
        XCTAssertEqual(servers.first?.name, "Tracked Server")
    }

    func testPurgingExpiredTrackedServersAlsoRemovesPersistence() throws {
        let tempDir = try makeTemporaryDirectory()
        let databaseController = makeDatabaseController(tempDir: tempDir)

        let controller = TrackerController(databaseController: databaseController)
        defer { controller.stop() }

        let client = makeClient(userID: 1)
        client.ip = "203.0.113.10"

        let registeredAt = Date(timeIntervalSince1970: 1_000)
        _ = try controller.registerServer(
            client: client,
            message: makeRegisterMessage(),
            allowedCategories: ["public"],
            now: registeredAt
        )

        controller.purgeExpiredServers(now: registeredAt.addingTimeInterval(TrackerController.entryExpirationInterval + 5))

        XCTAssertEqual(controller.activeServersSnapshot().count, 0)

        let persistedCount = try databaseController.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracked_servers") ?? 0
        }
        XCTAssertEqual(persistedCount, 0)
    }

    private func makeRegisterMessage() -> P7Message {
        let spec = P7Spec(withPath: nil)
        let message = P7Message(withName: "wired.tracker.send_register", spec: spec)
        message.addParameter(field: "wired.tracker.tracker", value: false)
        message.addParameter(field: "wired.tracker.category", value: "public")
        message.addParameter(field: "wired.tracker.port", value: UInt32(4871))
        message.addParameter(field: "wired.tracker.users", value: UInt32(3))
        message.addParameter(field: "wired.info.name", value: "Tracked Server")
        message.addParameter(field: "wired.info.description", value: "Persist me")
        message.addParameter(field: "wired.info.files.count", value: UInt64(12))
        message.addParameter(field: "wired.info.files.size", value: UInt64(34))
        return message
    }
}
