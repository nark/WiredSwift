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

    func testBanPatternIPv6ExactAndCIDRMatching() {
        XCTAssertTrue(BanPattern.parse("2001:db8::1")?.matches(ipAddress: "2001:db8::1") == true)
        XCTAssertFalse(BanPattern.parse("2001:db8::1")?.matches(ipAddress: "2001:db8::2") == true)
        XCTAssertTrue(BanPattern.parse("2001:db8::/32")?.matches(ipAddress: "2001:db8:abcd::1") == true)
        XCTAssertFalse(BanPattern.parse("2001:db8::/32")?.matches(ipAddress: "2001:dead::1") == true)
    }

    func testBanPatternRejectsMalformedWildcardAndCIDR() {
        XCTAssertNil(BanPattern.parse("10.*.1.2"))
        XCTAssertNil(BanPattern.parse("10.1.*.2"))
        XCTAssertNil(BanPattern.parse("10.1.2.*.5"))
        XCTAssertNil(BanPattern.parse("10.1.2.0/33"))
        XCTAssertNil(BanPattern.parse("2001:db8::/129"))
        XCTAssertNil(BanPattern.parse("192.168.0.0/255.255.0"))
        XCTAssertNil(BanPattern.parse(""))
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

    func testAddBanTrimsPatternAndMatchesAfterTrim() throws {
        let (controller, _) = try makeController()

        let added = try controller.addBan(ipPattern: "  198.51.100.*  ", expirationDate: nil)
        XCTAssertEqual(added.ipPattern, "198.51.100.*")
        XCTAssertNotNil(try controller.getBan(forIPAddress: "198.51.100.20"))
    }

    func testAddBanRejectsPastExpirationDate() throws {
        let (controller, _) = try makeController()

        XCTAssertThrowsError(
            try controller.addBan(ipPattern: "198.51.100.5", expirationDate: Date(timeIntervalSinceNow: -1))
        ) { error in
            XCTAssertTrue(error is BanListError)
            guard case BanListError.invalidExpirationDate = error else {
                return XCTFail("Expected invalidExpirationDate, got \(error)")
            }
        }
    }

    func testAddBanRejectsInvalidPattern() throws {
        let (controller, _) = try makeController()

        XCTAssertThrowsError(try controller.addBan(ipPattern: "not-an-ip", expirationDate: nil)) { error in
            XCTAssertTrue(error is BanListError)
            guard case BanListError.invalidPattern = error else {
                return XCTFail("Expected invalidPattern, got \(error)")
            }
        }
    }

    func testDeleteBanRejectsEmptyPattern() throws {
        let (controller, _) = try makeController()

        XCTAssertThrowsError(try controller.deleteBan(ipPattern: "   ", expirationDate: nil)) { error in
            XCTAssertTrue(error is BanListError)
            guard case BanListError.invalidPattern = error else {
                return XCTFail("Expected invalidPattern, got \(error)")
            }
        }
    }

    func testDeleteBanNotFoundWhenPatternMissing() throws {
        let (controller, _) = try makeController()

        XCTAssertThrowsError(try controller.deleteBan(ipPattern: "203.0.113.1", expirationDate: nil)) { error in
            XCTAssertTrue(error is BanListError)
            guard case BanListError.notFound = error else {
                return XCTFail("Expected notFound, got \(error)")
            }
        }
    }

    func testDeleteBanNotFoundWhenExpirationDateDoesNotMatch() throws {
        let (controller, _) = try makeController()

        let expiration = Date(timeIntervalSinceNow: 3600)
        _ = try controller.addBan(ipPattern: "198.51.100.7", expirationDate: expiration)

        XCTAssertThrowsError(
            try controller.deleteBan(
                ipPattern: "198.51.100.7",
                expirationDate: Date(timeIntervalSinceReferenceDate: expiration.timeIntervalSinceReferenceDate + 60)
            )
        ) { error in
            XCTAssertTrue(error is BanListError)
            guard case BanListError.notFound = error else {
                return XCTFail("Expected notFound, got \(error)")
            }
        }
    }

    func testListBansReturnsSortedByExpirationThenPattern() throws {
        let (controller, _) = try makeController()

        let later = Date(timeIntervalSinceNow: 7200)
        let sooner = Date(timeIntervalSinceNow: 3600)
        _ = try controller.addBan(ipPattern: "203.0.113.5", expirationDate: later)
        _ = try controller.addBan(ipPattern: "203.0.113.4", expirationDate: sooner)
        _ = try controller.addBan(ipPattern: "203.0.113.3", expirationDate: nil)

        let bans = try controller.listBans()
        XCTAssertEqual(bans.map(\.ipPattern), ["203.0.113.3", "203.0.113.4", "203.0.113.5"])
    }

    func testCleanupExpiredBansReturnsDeletedCount() throws {
        let (controller, databaseController) = try makeController()

        try databaseController.dbQueue.write { db in
            let expiredOne = BanEntry(ipPattern: "203.0.113.10", expirationDate: Date(timeIntervalSinceNow: -120))
            let expiredTwo = BanEntry(ipPattern: "203.0.113.11", expirationDate: Date(timeIntervalSinceNow: -60))
            let active = BanEntry(ipPattern: "203.0.113.12", expirationDate: Date(timeIntervalSinceNow: 3600))
            try expiredOne.insert(db)
            try expiredTwo.insert(db)
            try active.insert(db)
        }

        let deleted = try controller.cleanupExpiredBans()
        XCTAssertEqual(deleted, 2)
        XCTAssertEqual(try controller.listBans().map(\.ipPattern), ["203.0.113.12"])
    }

    private func makeController() throws -> (BanListController, DatabaseController) {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let databaseController = makeDatabaseController(tempDir: tempDir)
        return (BanListController(databaseController: databaseController), databaseController)
    }
}
