import XCTest
import WiredSwift
@testable import wired3Lib

final class EventsControllerTests: XCTestCase {
    func testFirstEventDateIsNilWhenEmptyThenReturnsOldest() throws {
        let controller = try makeController()
        XCTAssertNil(try controller.firstEventDate())

        _ = try controller.addEvent(.userLoggedIn, parameters: [], nick: "a", login: "alice", ip: "127.0.0.1")
        usleep(2_000)
        let second = try controller.addEvent(.messageSent, parameters: ["hello"], nick: "b", login: "bob", ip: "127.0.0.2")

        let firstDate = try XCTUnwrap(try controller.firstEventDate())
        XCTAssertLessThanOrEqual(firstDate, second.time)
    }

    func testListEventsWithoutFromTimeUsesLastEventCountDescending() throws {
        let controller = try makeController()

        _ = try controller.addEvent(.userLoggedIn, parameters: ["one"], nick: "a", login: "alice", ip: "127.0.0.1")
        usleep(2_000)
        let newest = try controller.addEvent(.userLoggedOut, parameters: ["two"], nick: "b", login: "bob", ip: "127.0.0.2")

        let none = try controller.listEvents(from: nil, numberOfDays: 0, lastEventCount: 0)
        XCTAssertTrue(none.isEmpty)

        let lastOne = try controller.listEvents(from: nil, numberOfDays: 0, lastEventCount: 1)
        XCTAssertEqual(lastOne.count, 1)
        XCTAssertEqual(lastOne.first?.id, newest.id)
    }

    func testListEventsFromTimeWithDayWindowFiltersRange() throws {
        let controller = try makeController()
        let now = Date()
        let twoDaysAgo = now.addingTimeInterval(-2 * 24 * 3600)
        let oneDayAgo = now.addingTimeInterval(-1 * 24 * 3600)

        _ = try controller.addEvent(.fileMoved, parameters: ["old"], nick: "old", login: "old", ip: "127.0.0.1")
        try controller.deleteEvents(from: nil, to: nil)

        let db = try makeDatabaseControllerForDirectInsert()
        defer { _ = db }
        // Re-create controller bound to the same DB used for controlled inserts.
        let directController = EventsController(databaseController: db)
        try insertEvent(code: WiredServerEvent.fileMoved.rawValue, time: twoDaysAgo, nick: "n1", login: "u1", ip: "127.0.0.1", db: db)
        try insertEvent(code: WiredServerEvent.fileDeleted.rawValue, time: oneDayAgo, nick: "n2", login: "u2", ip: "127.0.0.2", db: db)
        try insertEvent(code: WiredServerEvent.fileCreatedDirectory.rawValue, time: now, nick: "n3", login: "u3", ip: "127.0.0.3", db: db)

        let fromOneDayAgo = try directController.listEvents(from: oneDayAgo, numberOfDays: 0, lastEventCount: 0)
        XCTAssertEqual(fromOneDayAgo.count, 2)

        let oneDayWindow = try directController.listEvents(from: twoDaysAgo, numberOfDays: 1, lastEventCount: 0)
        XCTAssertEqual(oneDayWindow.count, 2)
    }

    func testDeleteEventsSupportsOptionalBounds() throws {
        let db = try makeDatabaseControllerForDirectInsert()
        let controller = EventsController(databaseController: db)
        let base = Date()

        try insertEvent(code: WiredServerEvent.userLoggedIn.rawValue, time: base.addingTimeInterval(-300), nick: "a", login: "a", ip: "127.0.0.1", db: db)
        try insertEvent(code: WiredServerEvent.userLoggedOut.rawValue, time: base.addingTimeInterval(-200), nick: "b", login: "b", ip: "127.0.0.2", db: db)
        try insertEvent(code: WiredServerEvent.messageSent.rawValue, time: base.addingTimeInterval(-100), nick: "c", login: "c", ip: "127.0.0.3", db: db)

        try controller.deleteEvents(from: base.addingTimeInterval(-250), to: base.addingTimeInterval(-150))
        var remaining = try controller.listEvents(from: nil, numberOfDays: 0, lastEventCount: 10)
        XCTAssertEqual(remaining.count, 2)

        try controller.deleteEvents(from: nil, to: base.addingTimeInterval(-250))
        remaining = try controller.listEvents(from: nil, numberOfDays: 0, lastEventCount: 10)
        XCTAssertEqual(remaining.count, 1)

        try controller.deleteEvents(from: base.addingTimeInterval(-150), to: nil)
        remaining = try controller.listEvents(from: nil, numberOfDays: 0, lastEventCount: 10)
        XCTAssertTrue(remaining.isEmpty)
    }

    private func makeController() throws -> EventsController {
        let db = try makeDatabaseControllerForDirectInsert()
        return EventsController(databaseController: db)
    }

    private func makeDatabaseControllerForDirectInsert() throws -> DatabaseController {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        return makeDatabaseController(tempDir: tempDir)
    }

    private func insertEvent(
        code: UInt32,
        time: Date,
        nick: String,
        login: String,
        ip: String,
        db: DatabaseController
    ) throws {
        try db.dbQueue.write { database in
            var entry = EventEntry(
                eventCode: code,
                parameters: [],
                time: time,
                nick: nick,
                login: login,
                ip: ip
            )
            try entry.insert(database)
        }
    }
}
