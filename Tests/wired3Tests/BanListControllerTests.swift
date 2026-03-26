import XCTest
@testable import wired3Lib

final class BanListControllerTests: XCTestCase {
    func testBanPatternParseAndMatchVariants() {
        XCTAssertTrue(BanPattern.parse("192.168.1.10")?.matches(ipAddress: "192.168.1.10") == true)
        XCTAssertTrue(BanPattern.parse("10.0.*")?.matches(ipAddress: "10.0.99.7") == true)
        XCTAssertTrue(BanPattern.parse("172.16.0.0/12")?.matches(ipAddress: "172.20.1.1") == true)
        XCTAssertTrue(BanPattern.parse("192.168.0.0/255.255.0.0")?.matches(ipAddress: "192.168.42.1") == true)
        XCTAssertNil(BanPattern.parse("999.999.999.999"))
    }

    func testAddGetAndDeleteBan() throws {
        let (controller, _) = try makeController()

        let added = try controller.addBan(ipPattern: "203.0.113.*", expirationDate: nil)
        XCTAssertEqual(added.ipPattern, "203.0.113.*")
        XCTAssertNotNil(try controller.getBan(forIPAddress: "203.0.113.42"))

        try controller.deleteBan(ipPattern: "203.0.113.*", expirationDate: nil)
        XCTAssertNil(try controller.getBan(forIPAddress: "203.0.113.42"))
    }

    func testAddBanRejectsDuplicatePattern() throws {
        let (controller, _) = try makeController()
        _ = try controller.addBan(ipPattern: "198.51.100.0/24", expirationDate: nil)

        XCTAssertThrowsError(try controller.addBan(ipPattern: "198.51.100.0/24", expirationDate: nil)) { error in
            guard case BanListError.alreadyExists = error else {
                XCTFail("Expected BanListError.alreadyExists, got \(error)")
                return
            }
        }
    }

    func testExpiredBansAreCleanedUpDuringLookup() throws {
        let (controller, databaseController) = try makeController()

        try databaseController.dbQueue.write { db in
            let expired = BanEntry(ipPattern: "203.0.114.1", expirationDate: Date(timeIntervalSinceNow: -30))
            try expired.insert(db)
        }

        XCTAssertNil(try controller.getBan(forIPAddress: "203.0.114.1"))
        XCTAssertEqual(try controller.listBans().count, 0)
    }

    private func makeController() throws -> (BanListController, DatabaseController) {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let databaseController = makeDatabaseController(tempDir: tempDir)
        return (BanListController(databaseController: databaseController), databaseController)
    }
}
