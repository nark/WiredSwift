import XCTest
import GRDB
@testable import wired3Lib

final class MigrationControllerTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a minimal Wired 2.5 SQLite database at `url` with the given users.
    private func makeWired25DB(at url: URL, users: [(name: String, password: String)] = []) throws {
        let db = try DatabaseQueue(path: url.path)
        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE users (
                    name TEXT PRIMARY KEY,
                    password TEXT NOT NULL,
                    full_name TEXT, comment TEXT,
                    creation_time TEXT, modification_time TEXT, login_time TEXT,
                    edited_by TEXT,
                    downloads INTEGER DEFAULT 0, download_transferred INTEGER DEFAULT 0,
                    uploads INTEGER DEFAULT 0, upload_transferred INTEGER DEFAULT 0,
                    "group" TEXT, groups TEXT, color TEXT, files TEXT,
                    user_get_info INTEGER DEFAULT 0,
                    account_change_password INTEGER DEFAULT 1
                )
            """)
            try db.execute(sql: """
                CREATE TABLE groups (
                    name TEXT PRIMARY KEY, color TEXT,
                    user_get_info INTEGER DEFAULT 0
                )
            """)
            try db.execute(sql: """
                CREATE TABLE banlist (ip TEXT PRIMARY KEY, expiration_date TEXT)
            """)
            try db.execute(sql: """
                CREATE TABLE boards (board TEXT PRIMARY KEY, owner TEXT, "group" TEXT, mode INTEGER DEFAULT 420)
            """)
            try db.execute(sql: "CREATE TABLE threads (thread TEXT PRIMARY KEY, board TEXT, subject TEXT, text TEXT, post_date TEXT, edit_date TEXT, nick TEXT, login TEXT, icon BLOB)")
            try db.execute(sql: "CREATE TABLE posts   (post   TEXT PRIMARY KEY, thread TEXT, text TEXT, post_date TEXT, edit_date TEXT, nick TEXT, login TEXT, icon BLOB)")

            for user in users {
                try db.execute(
                    sql: "INSERT INTO users (name, password) VALUES (?, ?)",
                    arguments: [user.name, user.password]
                )
            }
        }
    }

    // MARK: - Migration: is_legacy flag

    func testMigratedUserHasIsLegacySet() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let srcURL = tempDir.appendingPathComponent("wired25.sqlite")
        let sha1Hash = String(repeating: "a", count: 40) // fake 40-char SHA1

        try makeWired25DB(at: srcURL, users: [("alice", sha1Hash)])

        let dc = makeDatabaseController(tempDir: tempDir)
        let controller = MigrationController(
            sourcePath: srcURL.path,
            dbQueue: dc.dbQueue,
            overwrite: false
        )
        let result = try controller.run()

        XCTAssertEqual(result.usersMigrated, 1)
        XCTAssertEqual(result.usersSkipped, 0)

        let user = try dc.dbQueue.read { db in
            try User.filter(Column("username") == "alice").fetchOne(db)
        }
        XCTAssertNotNil(user)
        XCTAssertTrue(user!.isLegacy, "Migrated user must have is_legacy = true")
        XCTAssertNil(user!.passwordSalt, "Migrated user must have no salt yet")
    }

    func testMigratedUserSkippedWithoutOverwrite() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let srcURL = tempDir.appendingPathComponent("wired25.sqlite")
        try makeWired25DB(at: srcURL, users: [("bob", String(repeating: "b", count: 40))])

        let dc = makeDatabaseController(tempDir: tempDir)

        // First migration — inserts bob
        let first = MigrationController(sourcePath: srcURL.path, dbQueue: dc.dbQueue, overwrite: false)
        let r1 = try first.run()
        XCTAssertEqual(r1.usersMigrated, 1)

        // Second migration without --overwrite — bob must be skipped
        let second = MigrationController(sourcePath: srcURL.path, dbQueue: dc.dbQueue, overwrite: false)
        let r2 = try second.run()
        XCTAssertEqual(r2.usersMigrated, 0)
        XCTAssertEqual(r2.usersSkipped, 1)
    }

    func testMigratedUserOverwritten() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let srcURL = tempDir.appendingPathComponent("wired25.sqlite")
        let hash1 = String(repeating: "c", count: 40)
        try makeWired25DB(at: srcURL, users: [("carol", hash1)])

        let dc = makeDatabaseController(tempDir: tempDir)

        let first = MigrationController(sourcePath: srcURL.path, dbQueue: dc.dbQueue, overwrite: false)
        _ = try first.run()

        let second = MigrationController(sourcePath: srcURL.path, dbQueue: dc.dbQueue, overwrite: true)
        let r2 = try second.run()
        XCTAssertEqual(r2.usersMigrated, 1)
        XCTAssertEqual(r2.usersSkipped, 0)
    }

    // MARK: - Legacy auth detection

    func testIsLegacyUserReturnsTrueAfterMigration() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let srcURL = tempDir.appendingPathComponent("wired25.sqlite")
        try makeWired25DB(at: srcURL, users: [("dan", String(repeating: "d", count: 40))])

        let dc = makeDatabaseController(tempDir: tempDir)
        let controller = MigrationController(sourcePath: srcURL.path, dbQueue: dc.dbQueue, overwrite: false)
        _ = try controller.run()

        let usersController = UsersController(databaseController: dc)
        XCTAssertTrue(usersController.isLegacyUser(username: "dan"))
    }

    func testIsLegacyUserReturnsFalseForNormalAccount() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let dc = makeDatabaseController(tempDir: tempDir)
        let usersController = UsersController(databaseController: dc)

        // admin account created by initDatabase() is a normal SHA256 account
        XCTAssertFalse(usersController.isLegacyUser(username: "admin"))
    }

    func testIsLegacyFlagClearedAfterPasswordSaved() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let srcURL = tempDir.appendingPathComponent("wired25.sqlite")
        try makeWired25DB(at: srcURL, users: [("eve", String(repeating: "e", count: 40))])

        let dc = makeDatabaseController(tempDir: tempDir)
        _ = try MigrationController(sourcePath: srcURL.path, dbQueue: dc.dbQueue, overwrite: false).run()

        // Simulate password upgrade: set SHA256 password + salt + clear is_legacy
        let user = try dc.dbQueue.read { db in try User.filter(Column("username") == "eve").fetchOne(db)! }
        user.password = "newpassword".sha256()
        user.passwordSalt = "somesalt"
        user.isLegacy = false

        let usersController = UsersController(databaseController: dc)
        XCTAssertTrue(usersController.save(user: user))

        XCTAssertFalse(usersController.isLegacyUser(username: "eve"))
    }

    // MARK: - is_legacy column behaviour

    func testIsLegacyColumnDefaultsToFalseForNewAccounts() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let dc = makeDatabaseController(tempDir: tempDir)
        let usersController = UsersController(databaseController: dc)

        let user = User(username: "frank", password: "password".sha256())
        XCTAssertTrue(usersController.save(user: user))
        XCTAssertFalse(usersController.isLegacyUser(username: "frank"))
    }

    func testIsLegacyColumnReadCorrectlyWhenSetDirectly() throws {
        // Verifies that isLegacyUser() reads the is_legacy column — mirrors what the
        // v12 back-fill UPDATE produces in a database upgraded from an earlier version.
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let dc = makeDatabaseController(tempDir: tempDir)

        try dc.dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO users (username, password, is_legacy) VALUES (?, ?, 1)",
                arguments: ["grace", String(repeating: "g", count: 40)]
            )
        }

        let usersController = UsersController(databaseController: dc)
        XCTAssertTrue(usersController.isLegacyUser(username: "grace"))
    }
}
