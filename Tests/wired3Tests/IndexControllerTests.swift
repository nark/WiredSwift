import XCTest
import Foundation
import GRDB
@testable import wired3Lib

final class IndexControllerTests: XCTestCase {
    func testIndexFilesBuildsStatsAndPersistsEntries() throws {
        let workspace = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: workspace) }
        let root = workspace.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbRoot = workspace.appendingPathComponent("db", isDirectory: true)
        try FileManager.default.createDirectory(at: dbRoot, withIntermediateDirectories: true)

        let topFile = root.appendingPathComponent("a.txt")
        try Data([0x41, 0x42, 0x43]).write(to: topFile)

        let subdir = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let nestedFile = subdir.appendingPathComponent("b.bin")
        try Data(repeating: 0x99, count: 5).write(to: nestedFile)

        let hiddenWiredDir = root.appendingPathComponent(".wired", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenWiredDir, withIntermediateDirectories: true)
        try Data(repeating: 0xAA, count: 50).write(to: hiddenWiredDir.appendingPathComponent("ignored.dat"))

        let db = makeDatabaseController(tempDir: dbRoot)
        let files = FilesController(rootPath: root.path)
        let index = IndexController(databaseController: db, filesController: files)

        index.indexFiles()

        XCTAssertTrue(waitUntil(timeout: 2) {
            index.totalFilesCount == 2 && index.totalDirectoriesCount == 1
        })
        XCTAssertEqual(index.totalFilesSize, 8)

        let rowCount = try db.dbQueue.read { db in
            try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "index""#) ?? 0
        }
        XCTAssertEqual(rowCount, 3, "Expected 2 files + 1 directory indexed")
    }

    func testAddAndRemoveIndexForSinglePath() throws {
        let workspace = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: workspace) }
        let root = workspace.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbRoot = workspace.appendingPathComponent("db", isDirectory: true)
        try FileManager.default.createDirectory(at: dbRoot, withIntermediateDirectories: true)

        let fileURL = root.appendingPathComponent("single.txt")
        try Data("hello".utf8).write(to: fileURL)

        let db = makeDatabaseController(tempDir: dbRoot)
        let files = FilesController(rootPath: root.path)
        let index = IndexController(databaseController: db, filesController: files)

        index.addIndex(forPath: fileURL.path)
        XCTAssertTrue(waitUntil(timeout: 2) {
            (try? db.dbQueue.read { db in
                try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "index" WHERE real_path = ?"#, arguments: [fileURL.path]) ?? 0
            }) == 1
        })

        index.removeIndex(forPath: fileURL.path)
        XCTAssertTrue(waitUntil(timeout: 2) {
            (try? db.dbQueue.read { db in
                try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "index" WHERE real_path = ?"#, arguments: [fileURL.path]) ?? 0
            }) == 0
        })
    }

    func testIndexFilesRebuildRemovesStaleRowsAndRefreshesStats() throws {
        let workspace = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: workspace) }
        let root = workspace.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbRoot = workspace.appendingPathComponent("db", isDirectory: true)
        try FileManager.default.createDirectory(at: dbRoot, withIntermediateDirectories: true)

        let original = root.appendingPathComponent("old.txt")
        try Data([0x01, 0x02]).write(to: original)

        let db = makeDatabaseController(tempDir: dbRoot)
        let files = FilesController(rootPath: root.path)
        let index = IndexController(databaseController: db, filesController: files)

        index.indexFiles()
        XCTAssertTrue(waitUntil(timeout: 2) { index.totalFilesCount == 1 && index.totalFilesSize == 2 })

        try FileManager.default.removeItem(at: original)
        let replacement = root.appendingPathComponent("new.txt")
        try Data([0x10, 0x20, 0x30, 0x40]).write(to: replacement)

        index.indexFiles()
        XCTAssertTrue(waitUntil(timeout: 2) { index.totalFilesCount == 1 && index.totalFilesSize == 4 })

        let staleCount = try db.dbQueue.read { db in
            try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "index" WHERE name = ?"#, arguments: ["old.txt"]) ?? 0
        }
        let newCount = try db.dbQueue.read { db in
            try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "index" WHERE name = ?"#, arguments: ["new.txt"]) ?? 0
        }
        XCTAssertEqual(staleCount, 0)
        XCTAssertEqual(newCount, 1)
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(20_000)
        }
        return condition()
    }
}
