//
//  MigrationController.swift
//  wired3
//
//  Migrates users, groups and bans from a Wired 2.5 SQLite database
//  into an existing Wired 3 (wired3) SQLite database.
//
//  Usage (via CLI):
//    wired3 --migrate-from /path/to/wired25/database.sqlite3 [--overwrite]
//
//  IMPORTANT:
//  • Make a backup of your Wired 3 database before running.
//  • Wired 2.5 stores passwords as SHA1 hashes; Wired 3 uses SHA256+salt.
//    Passwords are copied as-is (password_salt = NULL). Users will need to
//    reset their passwords on first login.

import Foundation
import GRDB
#if os(Linux)
import CSQLite
#else
import SQLite3
#endif

/// Migrates accounts, privileges and bans from a Wired 2.5 SQLite database
/// into an already-initialised Wired 3 GRDB `DatabaseQueue`.
public final class MigrationController {

    // MARK: - Privilege mappings

    /// Wired 2.5 boolean column name → Wired 3 privilege name.
    private static let boolPrivilegeMap: [(src: String, dst: String)] = [
        ("user_get_info",                       "wired.account.user.get_info"),
        ("user_disconnect_users",               "wired.account.user.disconnect_users"),
        ("user_ban_users",                      "wired.account.user.ban_users"),
        ("user_cannot_be_disconnected",         "wired.account.user.cannot_be_disconnected"),
        ("user_cannot_set_nick",                "wired.account.user.cannot_set_nick"),
        ("user_get_users",                      "wired.account.user.get_users"),
        ("chat_kick_users",                     "wired.account.chat.kick_users"),
        ("chat_set_topic",                      "wired.account.chat.set_topic"),
        ("chat_create_chats",                   "wired.account.chat.create_chats"),
        ("message_send_messages",               "wired.account.message.send_messages"),
        ("message_broadcast",                   "wired.account.message.broadcast"),
        ("file_list_files",                     "wired.account.file.list_files"),
        ("file_search_files",                   "wired.account.file.search_files"),
        ("file_get_info",                       "wired.account.file.get_info"),
        ("file_create_links",                   "wired.account.file.create_links"),
        ("file_rename_files",                   "wired.account.file.rename_files"),
        ("file_set_type",                       "wired.account.file.set_type"),
        ("file_set_comment",                    "wired.account.file.set_comment"),
        ("file_set_permissions",                "wired.account.file.set_permissions"),
        ("file_set_executable",                 "wired.account.file.set_executable"),
        ("file_set_label",                      "wired.account.file.set_label"),
        ("file_create_directories",             "wired.account.file.create_directories"),
        ("file_move_files",                     "wired.account.file.move_files"),
        ("file_delete_files",                   "wired.account.file.delete_files"),
        ("file_access_all_dropboxes",           "wired.account.file.access_all_dropboxes"),
        ("account_change_password",             "wired.account.account.change_password"),
        ("account_list_accounts",               "wired.account.account.list_accounts"),
        ("account_read_accounts",               "wired.account.account.read_accounts"),
        ("account_create_users",                "wired.account.account.create_users"),
        ("account_edit_users",                  "wired.account.account.edit_users"),
        ("account_delete_users",                "wired.account.account.delete_users"),
        ("account_create_groups",               "wired.account.account.create_groups"),
        ("account_edit_groups",                 "wired.account.account.edit_groups"),
        ("account_delete_groups",               "wired.account.account.delete_groups"),
        ("account_raise_account_privileges",    "wired.account.account.raise_account_privileges"),
        ("transfer_download_files",             "wired.account.transfer.download_files"),
        ("transfer_upload_files",               "wired.account.transfer.upload_files"),
        ("transfer_upload_anywhere",            "wired.account.transfer.upload_anywhere"),
        ("transfer_upload_directories",         "wired.account.transfer.upload_directories"),
        ("board_read_boards",                   "wired.account.board.read_boards"),
        ("board_add_boards",                    "wired.account.board.add_boards"),
        ("board_move_boards",                   "wired.account.board.move_boards"),
        ("board_rename_boards",                 "wired.account.board.rename_boards"),
        ("board_delete_boards",                 "wired.account.board.delete_boards"),
        ("board_get_board_info",                "wired.account.board.get_board_info"),
        ("board_set_board_info",                "wired.account.board.set_board_info"),
        ("board_add_threads",                   "wired.account.board.add_threads"),
        ("board_move_threads",                  "wired.account.board.move_threads"),
        ("board_add_posts",                     "wired.account.board.add_posts"),
        ("board_edit_own_threads_and_posts",    "wired.account.board.edit_own_threads_and_posts"),
        ("board_edit_all_threads_and_posts",    "wired.account.board.edit_all_threads_and_posts"),
        ("board_delete_own_threads_and_posts",  "wired.account.board.delete_own_threads_and_posts"),
        ("board_delete_all_threads_and_posts",  "wired.account.board.delete_all_threads_and_posts"),
        ("log_view_log",                        "wired.account.log.view_log"),
        ("events_view_events",                  "wired.account.events.view_events"),
        ("settings_get_settings",               "wired.account.settings.get_settings"),
        ("settings_set_settings",               "wired.account.settings.set_settings"),
        ("banlist_get_bans",                    "wired.account.banlist.get_bans"),
        ("banlist_add_bans",                    "wired.account.banlist.add_bans"),
        ("banlist_delete_bans",                 "wired.account.banlist.delete_bans"),
        ("tracker_list_servers",                "wired.account.tracker.list_servers"),
        ("tracker_register_servers",            "wired.account.tracker.register_servers"),
    ]

    /// Wired 2.5 integer column name → Wired 3 privilege name (stored as integer value).
    private static let intPrivilegeMap: [(src: String, dst: String)] = [
        ("file_recursive_list_depth_limit",  "wired.account.file.recursive_list_depth_limit"),
        ("transfer_download_speed_limit",    "wired.account.transfer.download_speed_limit"),
        ("transfer_upload_speed_limit",      "wired.account.transfer.upload_speed_limit"),
        ("transfer_download_limit",          "wired.account.transfer.download_limit"),
        ("transfer_upload_limit",            "wired.account.transfer.upload_limit"),
    ]

    // MARK: - Result

    /// Summary counts returned after a completed migration.
    public struct MigrationResult {
        public var groupsMigrated  = 0
        public var groupsSkipped   = 0
        public var usersMigrated   = 0
        public var usersSkipped    = 0
        public var bansMigrated    = 0
        public var bansSkipped     = 0
        public var boardsMigrated  = 0
        public var boardsSkipped   = 0
        public var threadsMigrated = 0
        public var threadsSkipped  = 0
        public var postsMigrated   = 0
        public var postsSkipped    = 0

        public func printSummary() {
            print("")
            print("╔══════════════════════════════════════════════════════════╗")
            print("║         Wired 2.5 → Wired 3  Migration Summary          ║")
            print("╠══════════════════════════════════════════════════════════╣")
            print(String(format: "║  Groups : %3d migrated, %3d skipped                      ║",
                         groupsMigrated, groupsSkipped))
            print(String(format: "║  Users  : %3d migrated, %3d skipped                      ║",
                         usersMigrated, usersSkipped))
            print(String(format: "║  Bans   : %3d migrated, %3d skipped                      ║",
                         bansMigrated, bansSkipped))
            print(String(format: "║  Boards : %3d migrated, %3d skipped                      ║",
                         boardsMigrated, boardsSkipped))
            print(String(format: "║  Threads: %3d migrated, %3d skipped                      ║",
                         threadsMigrated, threadsSkipped))
            print(String(format: "║  Posts  : %3d migrated, %3d skipped                      ║",
                         postsMigrated, postsSkipped))
            print("╠══════════════════════════════════════════════════════════╣")
            print("║  NOTE: Passwords were migrated as SHA1 hashes.          ║")
            print("║  Users must reset their passwords on first login.        ║")
            print("╚══════════════════════════════════════════════════════════╝")
        }
    }

    // MARK: - Properties

    private let sourcePath: String
    private let dbQueue: DatabaseQueue
    private let overwrite: Bool

    // MARK: - Init

    /// Creates a new `MigrationController`.
    ///
    /// - Parameters:
    ///   - sourcePath: Filesystem path to the Wired 2.5 `database.sqlite3` file.
    ///   - dbQueue: The already-opened Wired 3 `DatabaseQueue`.
    ///   - overwrite: When `true`, existing records in Wired 3 are overwritten.
    public init(sourcePath: String, dbQueue: DatabaseQueue, overwrite: Bool = false) {
        self.sourcePath = sourcePath
        self.dbQueue    = dbQueue
        self.overwrite  = overwrite
    }

    // MARK: - Public API

    /// Runs the full migration and returns a result summary.
    ///
    /// Opens the Wired 2.5 source database read-only, then inside a single
    /// Wired 3 write transaction migrates groups (with privileges), users
    /// (with privileges) and bans. The source database is never modified.
    ///
    /// - Throws: Any SQLite or file-system error encountered during the migration.
    /// - Returns: A `MigrationResult` with counts of migrated and skipped records.
    public func run() throws -> MigrationResult {
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw MigrationError.sourceNotFound(sourcePath)
        }

        print("")
        print("╔══════════════════════════════════════════════════════════╗")
        print("║         Wired 2.5 → Wired 3  database migration         ║")
        print("╚══════════════════════════════════════════════════════════╝")
        print("  Source : \(sourcePath)")

        // Open Wired 2.5 source DB read-only via the raw SQLite3 C API.
        // We use the C API directly so that GRDB's WAL / migration machinery
        // does not interfere with the source database.
        var srcDB: OpaquePointer?
        let rc = sqlite3_open_v2(sourcePath, &srcDB, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK, let srcDB else {
            throw MigrationError.cannotOpenSource(sourcePath)
        }
        defer { sqlite3_close(srcDB) }

        printSourceSummary(srcDB)

        var result = MigrationResult()

        // All Wired 3 writes happen inside a single GRDB transaction so that
        // the target database is either fully updated or left untouched.
        try dbQueue.write { db in
            try migrateGroups(from: srcDB, into: db, result: &result)
            try migrateUsers(from: srcDB, into: db, result: &result)
            try migrateBans(from: srcDB, into: db, result: &result)
            try migrateBoards(from: srcDB, into: db, result: &result)
            try migrateThreads(from: srcDB, into: db, result: &result)
            try migratePosts(from: srcDB, into: db, result: &result)
        }

        return result
    }

    // MARK: - Migration steps

    private func migrateGroups(
        from srcDB: OpaquePointer,
        into db: Database,
        result: inout MigrationResult
    ) throws {
        print("\n── Groups ───────────────────────────────────────────────")
        let rows = try queryAll(srcDB, sql: "SELECT name, color FROM groups")
        print("  Found \(rows.count) group(s) in Wired 2.5")

        for row in rows {
            guard let name = row["name"] else { continue }
            let color: String? = row["color"]

            let existingID = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM groups WHERE name = ?",
                arguments: [name]
            )

            let groupID: Int64
            if let existingID {
                guard overwrite else {
                    print("  SKIP  group '\(name)' (already exists)")
                    result.groupsSkipped += 1
                    continue
                }
                try db.execute(
                    sql: "UPDATE groups SET color = ? WHERE name = ?",
                    arguments: [color, name]
                )
                groupID = existingID
                print("  UPD   group '\(name)'")
            } else {
                try db.execute(
                    sql: "INSERT INTO groups (name, color) VALUES (?, ?)",
                    arguments: [name, color]
                )
                groupID = db.lastInsertedRowID
                print("  ADD   group '\(name)'")
            }

            // Fetch the full source row to access all privilege columns.
            let srcRows = try queryAll(srcDB, sql: "SELECT * FROM groups WHERE name = ?", args: [name])
            try migratePrivileges(
                srcRow: srcRows.first ?? [:],
                into: db,
                target: .group(id: groupID)
            )
            result.groupsMigrated += 1
        }

        print("  → \(result.groupsMigrated) migrated, \(result.groupsSkipped) skipped")
    }

    private func migrateUsers(
        from srcDB: OpaquePointer,
        into db: Database,
        result: inout MigrationResult
    ) throws {
        print("\n── Users ────────────────────────────────────────────────")
        let rows = try queryAll(srcDB, sql: "SELECT * FROM users")
        print("  Found \(rows.count) user(s) in Wired 2.5")

        for row in rows {
            // Wired 2.5 uses "name" as the primary key / login column.
            guard let username = row["name"] else { continue }

            let existingID = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM users WHERE username = ?",
                arguments: [username]
            )

            let userID: Int64
            if let existingID {
                guard overwrite else {
                    print("  SKIP  user '\(username)' (already exists)")
                    result.usersSkipped += 1
                    continue
                }
                // password_salt is set to NULL and is_legacy to 1 because the migrated
                // hash is SHA1, not a Wired 3 SHA256 hash. The server will treat it as a
                // legacy credential and the user must set a new password on first login.
                try db.execute(sql: """
                    UPDATE users SET
                        password=?, full_name=?, comment=?,
                        creation_time=?, modification_time=?, login_time=?,
                        edited_by=?, downloads=?, download_transferred=?,
                        uploads=?, upload_transferred=?,
                        "group"=?, groups=?, color=?, files=?,
                        password_salt=NULL, is_legacy=1
                    WHERE username=?
                    """,
                    arguments: [
                        row["password"], row["full_name"], row["comment"],
                        row["creation_time"], row["modification_time"], row["login_time"],
                        row["edited_by"],
                        row["downloads"].flatMap { Int64($0) } ?? 0,
                        row["download_transferred"].flatMap { Int64($0) } ?? 0,
                        row["uploads"].flatMap { Int64($0) } ?? 0,
                        row["upload_transferred"].flatMap { Int64($0) } ?? 0,
                        row["group"], row["groups"], row["color"], row["files"],
                        username
                    ]
                )
                try db.execute(sql: "DELETE FROM user_privileges WHERE user_id = ?", arguments: [existingID])
                userID = existingID
                print("  UPD   user '\(username)'")
            } else {
                try db.execute(sql: """
                    INSERT INTO users (
                        username, password, password_salt, is_legacy,
                        full_name, comment,
                        creation_time, modification_time, login_time,
                        edited_by, downloads, download_transferred,
                        uploads, upload_transferred,
                        "group", groups, color, files
                    ) VALUES (?,?,NULL,1,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    """,
                    arguments: [
                        username, row["password"],
                        row["full_name"], row["comment"],
                        row["creation_time"], row["modification_time"], row["login_time"],
                        row["edited_by"],
                        row["downloads"].flatMap { Int64($0) } ?? 0,
                        row["download_transferred"].flatMap { Int64($0) } ?? 0,
                        row["uploads"].flatMap { Int64($0) } ?? 0,
                        row["upload_transferred"].flatMap { Int64($0) } ?? 0,
                        row["group"], row["groups"], row["color"], row["files"]
                    ]
                )
                userID = db.lastInsertedRowID
                print("  ADD   user '\(username)'")
            }

            try migratePrivileges(
                srcRow: row,
                into: db,
                target: .user(id: userID)
            )
            result.usersMigrated += 1
        }

        print("  → \(result.usersMigrated) migrated, \(result.usersSkipped) skipped")
    }

    private func migrateBans(
        from srcDB: OpaquePointer,
        into db: Database,
        result: inout MigrationResult
    ) throws {
        print("\n── Bans ─────────────────────────────────────────────────")
        let rows = try queryAll(srcDB, sql: "SELECT ip, expiration_date FROM banlist")
        print("  Found \(rows.count) ban(s) in Wired 2.5")

        for row in rows {
            guard let ipPattern = row["ip"] else { continue }
            let expirationDate: String? = row["expiration_date"]

            let existingID = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM banlist WHERE ip_pattern = ?",
                arguments: [ipPattern]
            )

            if let existingID {
                guard overwrite else {
                    print("  SKIP  ban '\(ipPattern)'")
                    result.bansSkipped += 1
                    continue
                }
                try db.execute(
                    sql: "UPDATE banlist SET expiration_date = ? WHERE id = ?",
                    arguments: [expirationDate, existingID]
                )
            } else {
                try db.execute(
                    sql: "INSERT INTO banlist (ip_pattern, expiration_date) VALUES (?, ?)",
                    arguments: [ipPattern, expirationDate]
                )
            }
            print("  ADD   ban '\(ipPattern)'  expires=\(expirationDate ?? "never")")
            result.bansMigrated += 1
        }

        print("  → \(result.bansMigrated) migrated, \(result.bansSkipped) skipped")
    }

    // MARK: - Boards / Threads / Posts

    private func migrateBoards(
        from srcDB: OpaquePointer,
        into db: Database,
        result: inout MigrationResult
    ) throws {
        print("\n── Boards ───────────────────────────────────────────────")
        // Note: the column is named `group` (reserved keyword) in Wired 2.5.
        let rows = try queryAll(srcDB, sql: "SELECT board, owner, `group`, mode FROM boards")
        print("  Found \(rows.count) board(s) in Wired 2.5")

        for row in rows {
            guard let path = row["board"] else { continue }
            let owner     = row["owner"] ?? ""
            let groupName = row["group"] ?? ""
            let mode      = Int(row["mode"] ?? "0") ?? 0

            // Decompose Unix permission bits into the 6 Wired 3 boolean columns.
            let ownerRead    = (mode & 0o400) != 0 ? 1 : 0
            let ownerWrite   = (mode & 0o200) != 0 ? 1 : 0
            let groupRead    = (mode & 0o040) != 0 ? 1 : 0
            let groupWrite   = (mode & 0o020) != 0 ? 1 : 0
            let everyoneRead  = (mode & 0o004) != 0 ? 1 : 0
            let everyoneWrite = (mode & 0o002) != 0 ? 1 : 0

            let exists = try String.fetchOne(
                db, sql: "SELECT path FROM boards WHERE path = ?", arguments: [path]
            ) != nil

            if exists {
                guard overwrite else {
                    print("  SKIP  board '\(path)' (already exists)")
                    result.boardsSkipped += 1
                    continue
                }
                try db.execute(sql: """
                    UPDATE boards SET owner=?, group_name=?,
                        owner_read=?, owner_write=?,
                        group_read=?, group_write=?,
                        everyone_read=?, everyone_write=?
                    WHERE path=?
                    """,
                    arguments: [owner, groupName,
                                ownerRead, ownerWrite, groupRead, groupWrite,
                                everyoneRead, everyoneWrite, path]
                )
                print("  UPD   board '\(path)'")
            } else {
                try db.execute(sql: """
                    INSERT INTO boards
                        (path, owner, group_name,
                         owner_read, owner_write,
                         group_read, group_write,
                         everyone_read, everyone_write)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [path, owner, groupName,
                                ownerRead, ownerWrite, groupRead, groupWrite,
                                everyoneRead, everyoneWrite]
                )
                print("  ADD   board '\(path)'")
            }
            result.boardsMigrated += 1
        }
        print("  → \(result.boardsMigrated) migrated, \(result.boardsSkipped) skipped")
    }

    private func migrateThreads(
        from srcDB: OpaquePointer,
        into db: Database,
        result: inout MigrationResult
    ) throws {
        print("\n── Threads ──────────────────────────────────────────────")
        // Exclude icon (BLOB) and ip — handled separately or dropped.
        let rows = try queryAll(srcDB,
            sql: "SELECT thread, board, subject, text, post_date, edit_date, nick, login FROM threads")
        print("  Found \(rows.count) thread(s) in Wired 2.5")

        for row in rows {
            guard let uuid = row["thread"], let boardPath = row["board"] else { continue }

            let exists = try String.fetchOne(
                db, sql: "SELECT uuid FROM board_threads WHERE uuid = ?", arguments: [uuid]
            ) != nil

            if exists {
                guard overwrite else {
                    print("  SKIP  thread '\(uuid)'")
                    result.threadsSkipped += 1
                    continue
                }
                try db.execute(sql: "DELETE FROM board_threads WHERE uuid = ?", arguments: [uuid])
            }

            let icon: Data? = queryBlobColumn(
                srcDB, sql: "SELECT icon FROM threads WHERE thread = ?", args: [uuid])
            let postDate = epochFrom(row["post_date"]) ?? 0.0
            let editDate: Double? = epochFrom(row["edit_date"])

            try db.execute(sql: """
                INSERT INTO board_threads
                    (uuid, board_path, subject, text, nick, login, post_date, edit_date, icon)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [uuid, boardPath,
                            row["subject"] ?? "", row["text"] ?? "",
                            row["nick"] ?? "", row["login"] ?? "",
                            postDate, editDate, icon]
            )
            print("  ADD   thread '\(uuid)' board='\(boardPath)'")
            result.threadsMigrated += 1
        }
        print("  → \(result.threadsMigrated) migrated, \(result.threadsSkipped) skipped")
    }

    private func migratePosts(
        from srcDB: OpaquePointer,
        into db: Database,
        result: inout MigrationResult
    ) throws {
        print("\n── Posts ─────────────────────────────────────────────────")
        let rows = try queryAll(srcDB,
            sql: "SELECT post, thread, text, post_date, edit_date, nick, login FROM posts")
        print("  Found \(rows.count) post(s) in Wired 2.5")

        for row in rows {
            guard let uuid = row["post"], let threadUUID = row["thread"] else { continue }

            let exists = try String.fetchOne(
                db, sql: "SELECT uuid FROM board_posts WHERE uuid = ?", arguments: [uuid]
            ) != nil

            if exists {
                guard overwrite else {
                    print("  SKIP  post '\(uuid)'")
                    result.postsSkipped += 1
                    continue
                }
                try db.execute(sql: "DELETE FROM board_posts WHERE uuid = ?", arguments: [uuid])
            }

            let icon: Data? = queryBlobColumn(
                srcDB, sql: "SELECT icon FROM posts WHERE post = ?", args: [uuid])
            let postDate = epochFrom(row["post_date"]) ?? 0.0
            let editDate: Double? = epochFrom(row["edit_date"])

            try db.execute(sql: """
                INSERT INTO board_posts
                    (uuid, thread_uuid, text, nick, login, post_date, edit_date, icon)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [uuid, threadUUID,
                            row["text"] ?? "",
                            row["nick"] ?? "", row["login"] ?? "",
                            postDate, editDate, icon]
            )
            print("  ADD   post '\(uuid)'")
            result.postsMigrated += 1
        }
        print("  → \(result.postsMigrated) migrated, \(result.postsSkipped) skipped")
    }

    // MARK: - Privilege helper

    /// Validated target for privilege rows — eliminates raw string interpolation of
    /// table/column names by restricting callers to an exhaustive closed enum.
    private enum PrivilegeTarget {
        case user(id: Int64)
        case group(id: Int64)

        var tableName: String {
            switch self {
            case .user:  return "user_privileges"
            case .group: return "group_privileges"
            }
        }
        var fkColumnName: String {
            switch self {
            case .user:  return "user_id"
            case .group: return "group_id"
            }
        }
        var id: Int64 {
            switch self {
            case .user(let id), .group(let id): return id
            }
        }
    }

    /// Inserts privilege rows for a single user or group.
    ///
    /// Table and column names are taken from a closed `PrivilegeTarget` enum, not from
    /// caller-supplied strings, to prevent accidental injection of untrusted identifiers.
    private func migratePrivileges(
        srcRow: [String: String],
        into db: Database,
        target: PrivilegeTarget
    ) throws {
        for (srcCol, dstName) in MigrationController.boolPrivilegeMap {
            guard let raw = srcRow[srcCol] else { continue }
            let value = (Int(raw) ?? 0) != 0
            try db.execute(
                sql: "INSERT OR REPLACE INTO \(target.tableName) (name, value, \(target.fkColumnName)) VALUES (?,?,?)",
                arguments: [dstName, value, target.id]
            )
        }
        for (srcCol, dstName) in MigrationController.intPrivilegeMap {
            guard let raw = srcRow[srcCol] else { continue }
            let value = Int64(raw) ?? 0
            try db.execute(
                sql: "INSERT OR REPLACE INTO \(target.tableName) (name, value, \(target.fkColumnName)) VALUES (?,?,?)",
                arguments: [dstName, value, target.id]
            )
        }
    }

    // MARK: - Raw SQLite helpers

    /// Executes a SELECT on the Wired 2.5 source database using the raw SQLite3
    /// C API and returns all rows as `[columnName: value]` dictionaries.
    ///
    /// NULL columns are omitted from the dictionary (not stored as nil-valued
    /// keys) so that consumers can use a simple `guard let x = row["col"]` check.
    private func queryAll(
        _ db: OpaquePointer,
        sql: String,
        args: [String] = []
    ) throws -> [[String: String]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MigrationError.sqliteError("prepare failed: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }

        for (i, arg) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (arg as NSString).utf8String, -1, nil)
        }

        let columnCount = sqlite3_column_count(stmt)
        var columnNames = [String]()
        for i in 0..<columnCount {
            columnNames.append(String(cString: sqlite3_column_name(stmt, i)))
        }

        var rows = [[String: String]]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row = [String: String]()
            for i in 0..<columnCount {
                guard sqlite3_column_type(stmt, i) != SQLITE_NULL else { continue }
                if let cStr = sqlite3_column_text(stmt, i) {
                    row[columnNames[Int(i)]] = String(cString: cStr)
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Executes a single-row, single-column SELECT on the source database and
    /// returns the result as `Data` (for BLOB columns).  Returns `nil` when the
    /// column is NULL or the query produces no rows.
    private func queryBlobColumn(
        _ db: OpaquePointer,
        sql: String,
        args: [String] = []
    ) -> Data? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }

        for (i, arg) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (arg as NSString).utf8String, -1, nil)
        }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              sqlite3_column_type(stmt, 0) != SQLITE_NULL,
              let ptr = sqlite3_column_blob(stmt, 0) else { return nil }

        let byteCount = Int(sqlite3_column_bytes(stmt, 0))
        return Data(bytes: ptr, count: byteCount)
    }

    /// Converts a Wired 2.5 date string ("yyyy-MM-dd HH:mm:ss", UTC) to a
    /// Unix-epoch `Double` suitable for Wired 3's REAL date columns.
    private func epochFrom(_ string: String?) -> Double? {
        guard let string else { return nil }
        return MigrationController.wiredDateFormatter.date(from: string)?.timeIntervalSince1970
    }

    private static let wiredDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Diagnostics

    private func printSourceSummary(_ srcDB: OpaquePointer) {
        print("\n── Source database summary ───────────────────────────────")
        for table in ["users", "groups", "banlist", "boards", "threads", "posts"] {
            if let rows = try? queryAll(srcDB, sql: "SELECT COUNT(*) AS n FROM \(table)"),
               let first = rows.first,
               let n = Int(first["n"] ?? "") {
                let padded = table.padding(toLength: 12, withPad: " ", startingAt: 0)
                print("  \(padded) \(n) row(s)")
            }
        }
    }
}

// MARK: - Error type

/// Errors that can be thrown by `MigrationController`.
public enum MigrationError: Error, CustomStringConvertible {
    case sourceNotFound(String)
    case cannotOpenSource(String)
    case sqliteError(String)

    public var description: String {
        switch self {
        case .sourceNotFound(let p):   return "Source database not found: \(p)"
        case .cannotOpenSource(let p): return "Cannot open source database: \(p)"
        case .sqliteError(let msg):    return "SQLite error: \(msg)"
        }
    }
}
