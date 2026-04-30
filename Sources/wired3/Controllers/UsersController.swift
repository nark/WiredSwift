//
//  UsersController.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import GRDB
#if os(Linux)
import CSQLite
#else
import SQLite3
#endif

/// Manages user and group accounts, authentication, and privilege lookups.
///
/// Implements `SocketPasswordDelegate` so that the P7 socket layer can retrieve
/// the stored SHA-256 password hash and per-user salt during key-exchange without
/// coupling to the database directly.
public class UsersController: TableController, SocketPasswordDelegate {
    var lastUserID: UInt32 = 0
    var lastUserIDLock: NSLock = NSLock()

    // MARK: - Public

    /// Returns the next available user session ID in a thread-safe manner.
    ///
    /// - Returns: A monotonically increasing `UInt32` session identifier.
    public func nextUserID() -> UInt32 {
        lastUserIDLock.lock()
        defer { lastUserIDLock.unlock() }
        self.lastUserID += 1
        return self.lastUserID
    }

    // MARK: - Database (SocketPasswordDelegate)

    /// Returns the stored SHA-256 password hash for `username`, or `nil` if the user does not exist.
    ///
    /// - Parameter username: The account login name.
    /// - Returns: The stored SHA-256 hash, or `nil`.
    public func passwordForUsername(username: String) -> String? {
        user(withUsername: username)?.password
    }

    /// Returns the per-user stored salt for `username`, or `nil` if not yet assigned.
    ///
    /// - Parameter username: The account login name.
    /// - Returns: The hex-encoded salt string, or `nil`.
    public func passwordSaltForUsername(username: String) -> String? {
        user(withUsername: username)?.passwordSalt
    }

    public func isLegacyUser(username: String) -> Bool {
        user(withUsername: username)?.isLegacy ?? false
    }

    // MARK: - Fetch

    /// Authenticates a user by verifying the supplied SHA-256 password hash.
    ///
    /// On the first successful login for an account that lacks a stored salt, a new
    /// per-user salt is generated and persisted (lazy P7 v1.2 migration).
    /// Privileges are loaded eagerly and attached to the returned `User`.
    ///
    /// - Parameters:
    ///   - username: The account login name.
    ///   - password: The client-supplied SHA-256 hash of the plaintext password.
    /// - Returns: The authenticated `User` with privileges loaded, or `nil` if
    ///   authentication fails.
    public func user(withUsername username: String, password: String) -> User? {
        guard let user = user(withUsername: username) else { return nil }

        // user.password = SHA-256(plaintext); password parameter = SHA-256(plaintext) from client.
        guard user.password == password else { return nil }

        // Lazy migration: assign a per-user stored_salt on first successful login if not set.
        // The salt is used by the P7 v1.2 key exchange to derive the base hash, preventing
        // stored-hash-in-transit exposure. user.password (SHA-256 of plaintext) is never changed.
        if user.passwordSalt == nil || user.passwordSalt!.isEmpty {
            let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                     + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            user.passwordSalt = salt
            save(user: user)
            Logger.info("Assigned stored_salt for '\(username)' (P7 v1.2 lazy migration)")
        }

        // Load privileges
        if let userId = user.id {
            user.privileges = (try? databaseController.dbQueue.read { db in
                try UserPrivilege.filter(Column("user_id") == userId).fetchAll(db)
            }) ?? []
        }

        return user
    }

    /// Fetches a user by login name without loading privileges.
    ///
    /// - Parameter username: The account login name.
    /// - Returns: The matching `User`, or `nil` if not found.
    public func user(withUsername username: String) -> User? {
        try? databaseController.dbQueue.read { db in
            try User.filter(Column("username") == username).fetchOne(db)
        }
    }

    /// Returns `true` if a registered account with the given login name exists.
    public func userExists(withUsername username: String) -> Bool {
        (try? databaseController.dbQueue.read { db in
            try User.filter(Column("username") == username).fetchCount(db) > 0
        }) ?? false
    }

    /// Fetches a user by login name and eagerly loads their privilege set.
    ///
    /// - Parameter username: The account login name.
    /// - Returns: The matching `User` with privileges populated, or `nil` if not found.
    public func userWithPrivileges(withUsername username: String) -> User? {
        try? databaseController.dbQueue.read { db in
            if let user = try User.filter(Column("username") == username).fetchOne(db) {
                user.privileges = try UserPrivilege
                    .filter(Column("user_id") == user.id!)
                    .fetchAll(db)
                return user
            }
            return nil
        }
    }

    /// Fetches a user by their stable identity token and eagerly loads their privilege set.
    ///
    /// - Parameter identity: The user's unique identity string.
    /// - Returns: The matching `User` with privileges populated, or `nil` if not found.
    public func userWithPrivileges(identity: String) -> User? {
        try? databaseController.dbQueue.read { db in
            if let user = try User.filter(Column("identity") == identity).fetchOne(db) {
                user.privileges = try UserPrivilege
                    .filter(Column("user_id") == user.id!)
                    .fetchAll(db)
                return user
            }
            return nil
        }
    }

    /// Returns users whose username, full name, or identity contains `query` (case-insensitive).
    ///
    /// - Parameters:
    ///   - query: The search string.
    ///   - limit: Maximum number of results to return (default 50).
    /// - Returns: Matching users, up to `limit` entries.
    public func users(matchingIdentityQuery query: String, limit: Int = 50) -> [User] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }
        let all = (try? databaseController.dbQueue.read { db in try User.fetchAll(db) }) ?? []
        return all.filter {
            let u = ($0.username ?? "").lowercased()
            let f = ($0.fullName ?? "").lowercased()
            let i = ($0.identity ?? "").lowercased()
            return u.contains(normalized) || f.contains(normalized) || i.contains(normalized)
        }.prefix(limit).map { $0 }
    }

    /// Returns `true` if no existing user has the given `identity` token.
    ///
    /// - Parameter identity: The candidate identity string.
    /// - Returns: `true` if the identity is not yet taken.
    public func isIdentityAvailable(_ identity: String) -> Bool {
        let existing = try? databaseController.dbQueue.read { db in
            try User.filter(Column("identity") == identity).fetchOne(db)
        }
        return existing == nil
    }

    /// Returns all user accounts (without privileges loaded).
    ///
    /// - Returns: Every `User` row in the database.
    public func users() -> [User] {
        (try? databaseController.dbQueue.read { db in try User.fetchAll(db) }) ?? []
    }

    /// Returns all groups (without privileges loaded).
    ///
    /// - Returns: Every `Group` row in the database.
    public func groups() -> [Group] {
        (try? databaseController.dbQueue.read { db in try Group.fetchAll(db) }) ?? []
    }

    /// Fetches a group by name without loading privileges.
    ///
    /// - Parameter name: The group name.
    /// - Returns: The matching `Group`, or `nil` if not found.
    public func group(withName name: String) -> Group? {
        try? databaseController.dbQueue.read { db in
            try Group.filter(Column("name") == name).fetchOne(db)
        }
    }

    /// Fetches a group by name and eagerly loads its privilege set.
    ///
    /// - Parameter name: The group name.
    /// - Returns: The matching `Group` with privileges populated, or `nil` if not found.
    public func groupWithPrivileges(withName name: String) -> Group? {
        try? databaseController.dbQueue.read { db in
            if let group = try Group.filter(Column("name") == name).fetchOne(db) {
                group.privileges = try GroupPrivilege
                    .filter(Column("group_id") == group.id!)
                    .fetchAll(db)
                return group
            }
            return nil
        }
    }

    // MARK: - Write

    /// Persists a `User` record (insert or update).
    ///
    /// - Parameter user: The user to save.
    /// - Returns: `true` on success, `false` if the write fails.
    @discardableResult
    public func save(user: User) -> Bool {
        do {
            try databaseController.dbQueue.write { db in try user.save(db) }
            return true
        } catch { return false }
    }

    /// Persists a `Group` record (insert or update).
    ///
    /// - Parameter group: The group to save.
    /// - Returns: `true` on success, `false` if the write fails.
    @discardableResult
    public func save(group: Group) -> Bool {
        do {
            try databaseController.dbQueue.write { db in try group.save(db) }
            return true
        } catch { return false }
    }

    /// Deletes a user and all their associated privilege rows in a single transaction.
    ///
    /// - Parameter user: The user to delete.
    /// - Returns: `true` on success, `false` if the delete fails or the user has no ID.
    @discardableResult
    public func delete(user: User) -> Bool {
        guard let userID = user.id else { return false }

        do {
            try databaseController.dbQueue.write { db in
                try UserPrivilege
                    .filter(Column("user_id") == userID)
                    .deleteAll(db)
                try user.delete(db)
            }
            return true
        } catch {
            return false
        }
    }

    /// Deletes a group and all its associated privilege rows in a single transaction.
    ///
    /// - Parameter group: The group to delete.
    /// - Returns: `true` on success, `false` if the delete fails or the group has no ID.
    @discardableResult
    public func delete(group: Group) -> Bool {
        guard let groupID = group.id else { return false }

        do {
            try databaseController.dbQueue.write { db in
                try GroupPrivilege
                    .filter(Column("group_id") == groupID)
                    .deleteAll(db)
                try group.delete(db)
            }
            return true
        } catch {
            return false
        }
    }

    /// Upserts a single privilege flag for a user.
    ///
    /// - Parameters:
    ///   - name: The privilege field name (e.g. `"wired.account.chat.create_chats"`).
    ///   - value: The desired boolean value.
    ///   - user: The target user.
    /// - Returns: `true` on success, `false` if the user has no ID or the write fails.
    @discardableResult
    public func setUserPrivilege(_ name: String, value: Bool, for user: User) -> Bool {
        guard let userID = user.id else { return false }
        do {
            try databaseController.dbQueue.write { db in
                if var existing = try UserPrivilege
                    .filter(Column("user_id") == userID && Column("name") == name)
                    .fetchOne(db) {
                    existing.value = value
                    try existing.update(db)
                } else {
                    var priv = UserPrivilege(name: name, value: value, userId: userID)
                    try priv.insert(db)
                }
            }
            return true
        } catch { return false }
    }

    /// Upserts a single privilege flag for a group.
    ///
    /// - Parameters:
    ///   - name: The privilege field name.
    ///   - value: The desired boolean value.
    ///   - group: The target group.
    /// - Returns: `true` on success, `false` if the group has no ID or the write fails.
    @discardableResult
    public func setGroupPrivilege(_ name: String, value: Bool, for group: Group) -> Bool {
        guard let groupID = group.id else { return false }
        do {
            try databaseController.dbQueue.write { db in
                if var existing = try GroupPrivilege
                    .filter(Column("group_id") == groupID && Column("name") == name)
                    .fetchOne(db) {
                    existing.value = value
                    try existing.update(db)
                } else {
                    var priv = GroupPrivilege(name: name, value: value, groupId: groupID)
                    try priv.insert(db)
                }
            }
            return true
        } catch { return false }
    }

    // MARK: - Seeding (appelé une seule fois à la première exécution)

    /// Seeds the default `admin` and `guest` users and groups on a fresh database.
    ///
    /// A random 16-character password is generated for the `admin` account and printed
    /// to the log at INFO level. This method is a no-op if any users already exist.
    public func seedDefaultDataIfNeeded() {
        do {
            let userCount = try databaseController.dbQueue.read { db in
                try User.fetchCount(db)
            }
            guard userCount == 0 else { return }

            try databaseController.dbQueue.write { db in
                // Groupes par défaut
                let guestGroup = Group(name: "guest"); guestGroup.color = "0"
                try guestGroup.insert(db)
                let adminGroup = Group(name: "admin"); adminGroup.color = "1"
                try adminGroup.insert(db)

                // Utilisateurs par défaut
                // SECURITY (FINDING_A_005): Generate random password instead of hardcoded 'admin'
                let generatedPassword = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
                // user.password = SHA-256(plaintext) — P7 key exchange proof layer.
                // passwordSalt = per-user salt sent to client during P7 v1.2 key exchange
                // so the ECDSA proof is derived from SHA-256(salt || SHA-256(plain)).
                let admin = User(username: "admin", password: String(generatedPassword).sha256())
                admin.passwordSalt = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                                   + UUID().uuidString.replacingOccurrences(of: "-", with: "")
                WiredSwift.Logger.info("=== INITIAL ADMIN PASSWORD: \(generatedPassword) === (change it immediately)")
                admin.color = "1"
                try admin.insert(db)

                let guest = User(username: "guest", password: "".sha256())
                guest.passwordSalt = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                                   + UUID().uuidString.replacingOccurrences(of: "-", with: "")
                guest.color = "0"
                try guest.insert(db)

                guard let adminId = admin.id, let adminGroupId = adminGroup.id else { return }

                // Privileges utilisateur (admin = tout à true)
                for field in App.spec.accountPrivileges ?? [] {
                    guard App.spec.fieldsByName[field]?.type == .bool else { continue }
                    var priv = UserPrivilege(name: field, value: true, userId: adminId)
                    try priv.insert(db)
                }

                // Privileges groupe (admin = tout à true)
                for field in App.spec.accountPrivileges ?? [] {
                    guard App.spec.fieldsByName[field]?.type == .bool else { continue }
                    var priv = GroupPrivilege(name: field, value: true, groupId: adminGroupId)
                    try priv.insert(db)
                }
            }
        } catch {
            WiredSwift.Logger.error("Cannot seed default data: \(error)")
        }
    }

    // MARK: - Legacy schema migrations (raw SQLite, conservées pour bases Fluent existantes)

    /// Runs raw-SQLite migrations for databases created by earlier Fluent-based server versions.
    ///
    /// Handles the privilege unique-constraint migration, the `groups.color` column addition,
    /// the offline-messaging columns on `users`, the `offline_messages` table creation, and
    /// the `wired.account.board.add_reactions` privilege backfill. All operations are
    /// idempotent — each is a no-op if the schema is already up to date.
    public func migrateLegacyPrivilegesSchemaIfNeeded() {
        var db: OpaquePointer?
        guard sqlite3_open(databaseController.baseURL.path, &db) == SQLITE_OK, let db else {
            WiredSwift.Logger.warning("Cannot open database for privileges migration")
            return
        }
        defer { sqlite3_close(db) }

        migratePrivilegesTableIfNeeded(db: db,
                                       table: "user_privileges",
                                       ownerColumn: "user_id",
                                       constraintName: "uq:user_privileges.name.user_id")

        migratePrivilegesTableIfNeeded(db: db,
                                       table: "group_privileges",
                                       ownerColumn: "group_id",
                                       constraintName: "uq:group_privileges.name.group_id")

        migrateGroupsColorColumnIfNeeded(db: db)
        migrateUsersOfflineMessagingColumnsIfNeeded(db: db)
        migrateOfflineMessagesTableIfNeeded(db: db)
        migrateAddReactionsPrivilegeIfNeeded(db: db)
        migrateFileMetadataPrivilegesIfNeeded(db: db)
        migrateSendOfflineMessagesPrivilegeIfNeeded(db: db)
        migrateListOfflineUsersPrivilegeIfNeeded(db: db)
    }

    /// For existing installations, grant `wired.account.board.add_reactions` (true) to every
    /// user and group that already has `wired.account.board.add_posts`, so that accounts
    /// created before this feature was introduced can immediately use reactions without manual
    /// configuration. Accounts that did not have add_posts keep the privilege absent (false).
    private func migrateAddReactionsPrivilegeIfNeeded(db: OpaquePointer) {
        let reactionPrivilege = "wired.account.board.add_reactions"
        let postPrivilege     = "wired.account.board.add_posts"

        let tables: [(table: String, ownerColumn: String)] = [
            ("user_privileges", "user_id"),
            ("group_privileges", "group_id")
        ]

        for entry in tables {
            // Only insert where add_posts = true and add_reactions does not yet exist.
            // Do NOT specify the id column — it is INTEGER PRIMARY KEY AUTOINCREMENT (Int64).
            let sql = """
            INSERT OR IGNORE INTO "\(entry.table)" (name, value, \(entry.ownerColumn))
            SELECT '\(reactionPrivilege)', 1, \(entry.ownerColumn)
            FROM "\(entry.table)"
            WHERE name = '\(postPrivilege)' AND value = 1
              AND \(entry.ownerColumn) NOT IN (
                  SELECT \(entry.ownerColumn) FROM "\(entry.table)" WHERE name = '\(reactionPrivilege)'
              );
            """
            if sqliteExec(db: db, sql) != SQLITE_OK {
                if let msg = sqlite3_errmsg(db) {
                    WiredSwift.Logger.error("migrateAddReactionsPrivilege (\(entry.table)): \(String(cString: msg))")
                }
            } else {
                WiredSwift.Logger.info("Migrated \(reactionPrivilege) for \(entry.table)")
            }
        }
    }

    /// For existing installations, grant `wired.account.file.set_comment` and
    /// `wired.account.file.set_label` to every user/group that already has
    /// `wired.account.file.set_type = true`. This keeps long-lived databases
    /// usable after restoring the legacy Wired 2.0 file metadata feature.
    private func migrateFileMetadataPrivilegesIfNeeded(db: OpaquePointer) {
        let sourcePrivilege = "wired.account.file.set_type"
        let targetPrivileges = [
            "wired.account.file.set_comment",
            "wired.account.file.set_label"
        ]

        let tables: [(table: String, ownerColumn: String)] = [
            ("user_privileges", "user_id"),
            ("group_privileges", "group_id")
        ]

        for targetPrivilege in targetPrivileges {
            for entry in tables {
                let sql = """
                INSERT OR IGNORE INTO "\(entry.table)" (name, value, \(entry.ownerColumn))
                SELECT '\(targetPrivilege)', 1, \(entry.ownerColumn)
                FROM "\(entry.table)"
                WHERE name = '\(sourcePrivilege)' AND value = 1
                  AND \(entry.ownerColumn) NOT IN (
                      SELECT \(entry.ownerColumn) FROM "\(entry.table)" WHERE name = '\(targetPrivilege)'
                  );
                """
                if sqliteExec(db: db, sql) != SQLITE_OK {
                    if let msg = sqlite3_errmsg(db) {
                        WiredSwift.Logger.error("migrateFileMetadataPrivileges (\(targetPrivilege), \(entry.table)): \(String(cString: msg))")
                    }
                } else {
                    WiredSwift.Logger.info("Migrated \(targetPrivilege) for \(entry.table)")
                }
            }
        }
    }

    /// For existing installations, grant `wired.account.user.list_offline_users` to every
    /// user and group that already has `wired.account.message.send_offline_messages = true`.
    private func migrateListOfflineUsersPrivilegeIfNeeded(db: OpaquePointer) {
        let targetPrivilege = "wired.account.user.list_offline_users"
        let sourcePrivilege = "wired.account.message.send_offline_messages"

        let tables: [(table: String, ownerColumn: String)] = [
            ("user_privileges", "user_id"),
            ("group_privileges", "group_id")
        ]

        for entry in tables {
            let sql = """
            INSERT OR IGNORE INTO "\(entry.table)" (name, value, \(entry.ownerColumn))
            SELECT '\(targetPrivilege)', 1, \(entry.ownerColumn)
            FROM "\(entry.table)"
            WHERE name = '\(sourcePrivilege)' AND value = 1
              AND \(entry.ownerColumn) NOT IN (
                  SELECT \(entry.ownerColumn) FROM "\(entry.table)" WHERE name = '\(targetPrivilege)'
              );
            """
            if sqliteExec(db: db, sql) != SQLITE_OK {
                if let msg = sqlite3_errmsg(db) {
                    WiredSwift.Logger.error("migrateListOfflineUsersPrivilege (\(entry.table)): \(String(cString: msg))")
                }
            } else {
                WiredSwift.Logger.info("Migrated \(targetPrivilege) for \(entry.table)")
            }
        }
    }

    /// For existing installations, grant `wired.account.message.send_offline_messages` to every
    /// user and group that already has `wired.account.message.send_messages = true`.
    private func migrateSendOfflineMessagesPrivilegeIfNeeded(db: OpaquePointer) {
        let targetPrivilege = "wired.account.message.send_offline_messages"
        let sourcePrivilege = "wired.account.message.send_messages"

        let tables: [(table: String, ownerColumn: String)] = [
            ("user_privileges", "user_id"),
            ("group_privileges", "group_id")
        ]

        for entry in tables {
            let sql = """
            INSERT OR IGNORE INTO "\(entry.table)" (name, value, \(entry.ownerColumn))
            SELECT '\(targetPrivilege)', 1, \(entry.ownerColumn)
            FROM "\(entry.table)"
            WHERE name = '\(sourcePrivilege)' AND value = 1
              AND \(entry.ownerColumn) NOT IN (
                  SELECT \(entry.ownerColumn) FROM "\(entry.table)" WHERE name = '\(targetPrivilege)'
              );
            """
            if sqliteExec(db: db, sql) != SQLITE_OK {
                if let msg = sqlite3_errmsg(db) {
                    WiredSwift.Logger.error("migrateSendOfflineMessagesPrivilege (\(entry.table)): \(String(cString: msg))")
                }
            } else {
                WiredSwift.Logger.info("Migrated \(targetPrivilege) for \(entry.table)")
            }
        }
    }

    private func migratePrivilegesTableIfNeeded(db: OpaquePointer,
                                                table: String,
                                                ownerColumn: String,
                                                constraintName: String) {
        guard let schema = readSchema(db: db, table: table) else { return }
        guard schema.contains("UNIQUE (\"name\")"), !schema.contains("UNIQUE (\"name\",") else { return }

        let migratedTable = "\(table)_migrated"
        let statements = [
            "BEGIN TRANSACTION;",
            // swiftlint:disable:next line_length
            "CREATE TABLE IF NOT EXISTS \"\(migratedTable)\" (\"id\" UUID PRIMARY KEY, \"name\" TEXT NOT NULL, \"value\" INTEGER NOT NULL, \"\(ownerColumn)\" UUID NOT NULL, CONSTRAINT \"\(constraintName)\" UNIQUE (\"name\", \"\(ownerColumn)\"));",
            "INSERT OR IGNORE INTO \"\(migratedTable)\" (\"id\", \"name\", \"value\", \"\(ownerColumn)\") SELECT \"id\", \"name\", \"value\", \"\(ownerColumn)\" FROM \"\(table)\";",
            "DROP TABLE \"\(table)\";",
            "ALTER TABLE \"\(migratedTable)\" RENAME TO \"\(table)\";",
            "COMMIT;"
        ]

        for statement in statements where sqliteExec(db: db, statement) != SQLITE_OK {
            _ = sqliteExec(db: db, "ROLLBACK;")
            if let message = sqlite3_errmsg(db) {
                WiredSwift.Logger.error("Could not migrate \(table): \(String(cString: message))")
            }
            return
        }
        WiredSwift.Logger.info("Migrated \(table) to per-account unique privileges")
    }

    private func migrateGroupsColorColumnIfNeeded(db: OpaquePointer) {
        guard let schema = readSchema(db: db, table: "groups") else { return }
        guard !schema.contains("\"color\"") else { return }
        let statement = "ALTER TABLE \"groups\" ADD COLUMN \"color\" TEXT;"
        if sqliteExec(db: db, statement) != SQLITE_OK {
            if let message = sqlite3_errmsg(db) {
                WiredSwift.Logger.error("Could not add groups.color column: \(String(cString: message))")
            }
            return
        }
        WiredSwift.Logger.info("Added groups.color column")
    }

    private func migrateUsersOfflineMessagingColumnsIfNeeded(db: OpaquePointer) {
        guard let schema = readSchema(db: db, table: "users") else { return }
        let columnStatements: [(column: String, statement: String)] = [
            ("identity", "ALTER TABLE \"users\" ADD COLUMN \"identity\" TEXT;"),
            ("offline_public_key", "ALTER TABLE \"users\" ADD COLUMN \"offline_public_key\" BLOB;"),
            ("offline_key_id", "ALTER TABLE \"users\" ADD COLUMN \"offline_key_id\" TEXT;"),
            ("offline_crypto", "ALTER TABLE \"users\" ADD COLUMN \"offline_crypto\" TEXT;")
        ]
        for (column, statement) in columnStatements where !schema.contains("\"\(column)\"") {
            if sqliteExec(db: db, statement) != SQLITE_OK {
                if let message = sqlite3_errmsg(db) {
                    WiredSwift.Logger.error("Could not add users.\(column) column: \(String(cString: message))")
                }
            } else {
                WiredSwift.Logger.info("Added users.\(column) column")
            }
        }
        let uniqueIndex = "CREATE UNIQUE INDEX IF NOT EXISTS \"users_identity_unique\" ON \"users\"(\"identity\");"
        if sqliteExec(db: db, uniqueIndex) != SQLITE_OK {
            if let message = sqlite3_errmsg(db) {
                WiredSwift.Logger.error("Could not create users.identity unique index: \(String(cString: message))")
            }
        }
    }

    private func migrateOfflineMessagesTableIfNeeded(db: OpaquePointer) {
        let statement = """
        CREATE TABLE IF NOT EXISTS "offline_messages" (
          "id" UUID PRIMARY KEY,
          "sender_identity" TEXT NOT NULL,
          "recipient_identity" TEXT NOT NULL,
          "ciphertext" BLOB NOT NULL,
          "nonce" BLOB NOT NULL,
          "wrapped_key_recipient" BLOB NOT NULL,
          "wrapped_key_sender" BLOB,
          "recipient_key_id" TEXT,
          "created_at" DATETIME NOT NULL,
          "expires_at" DATETIME NOT NULL,
          "delivered_at" DATETIME,
          "acked_at" DATETIME
        );
        """
        if sqliteExec(db: db, statement) != SQLITE_OK {
            if let message = sqlite3_errmsg(db) {
                WiredSwift.Logger.error("Could not create offline_messages table: \(String(cString: message))")
            }
            return
        }
        for idx in [
            "CREATE INDEX IF NOT EXISTS \"offline_messages_recipient_index\" ON \"offline_messages\"(\"recipient_identity\");",
            "CREATE INDEX IF NOT EXISTS \"offline_messages_expires_index\" ON \"offline_messages\"(\"expires_at\");"
        ] where sqliteExec(db: db, idx) != SQLITE_OK {
            if let message = sqlite3_errmsg(db) {
                WiredSwift.Logger.error("Could not create offline_messages index: \(String(cString: message))")
            }
        }

        // SECURITY (FINDING_C_010): per-recipient limit to prevent storage DoS
        let triggerSQL = """
            CREATE TRIGGER IF NOT EXISTS offline_messages_per_recipient_limit
            BEFORE INSERT ON offline_messages
            BEGIN
                SELECT RAISE(ABORT, 'per-recipient offline message limit exceeded')
                WHERE (SELECT COUNT(*) FROM offline_messages
                       WHERE recipient_identity = NEW.recipient_identity) >= 100;
            END;
        """
        if sqliteExec(db: db, triggerSQL) != SQLITE_OK {
            if let message = sqlite3_errmsg(db) {
                WiredSwift.Logger.error("Could not create offline_messages limit trigger: \(String(cString: message))")
            }
        }
    }

    // SECURITY (FINDING_A_010/C_011/F_008): whitelist allowed table names to prevent SQL injection
    private static let allowedSchemaTableNames: Set<String> = [
        "user_privileges", "group_privileges", "groups", "users", "offline_messages"
    ]

    private func readSchema(db: OpaquePointer, table: String) -> String? {
        guard Self.allowedSchemaTableNames.contains(table) else {
            WiredSwift.Logger.error("readSchema called with disallowed table name: \(table)")
            return nil
        }
        let query = "SELECT sql FROM sqlite_master WHERE type='table' AND name='\(table)' LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlitePrepare(db: db, query: query, statement: &statement) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: cString)
    }

    private func sqliteExec(db: OpaquePointer, _ statement: String) -> Int32 {
        let callback: sqlite3_callback? = nil
        let context: UnsafeMutableRawPointer? = nil
        let errorMessage: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? = nil
        return sqlite3_exec(db, statement, callback, context, errorMessage)
    }

    private func sqlitePrepare(db: OpaquePointer, query: String, statement: inout OpaquePointer?) -> Int32 {
        let tail: UnsafeMutablePointer<UnsafePointer<CChar>?>? = nil
        return sqlite3_prepare_v2(db, query, -1, &statement, tail)
    }

    // MARK: - Identity backfill

    /// Assigns a stable identity token to every user that does not already have one.
    ///
    /// The token is derived from the user's full name or username, lowercased and
    /// reduced to alphanumeric segments joined by hyphens. Duplicate candidates are
    /// disambiguated with a numeric suffix. This method is a no-op if every user
    /// already has a non-empty identity.
    public func backfillStableIdentitiesIfNeeded() {
        do {
            let loadedUsers = try databaseController.dbQueue.read { db in
                try User.fetchAll(db)
            }.sorted {
                ($0.username ?? "").localizedCaseInsensitiveCompare($1.username ?? "") == .orderedAscending
            }

            var usedIdentities: Set<String> = []
            var updatedUsers = 0

            for user in loadedUsers {
                let currentIdentity = normalizedIdentity(user.identity ?? "")
                if !currentIdentity.isEmpty, !usedIdentities.contains(currentIdentity) {
                    usedIdentities.insert(currentIdentity)
                    if user.identity != currentIdentity {
                        user.identity = currentIdentity
                        if save(user: user) { updatedUsers += 1 }
                    }
                    continue
                }
                let base = generatedIdentitySeed(from: user)
                var candidate = base
                var suffix = 2
                while usedIdentities.contains(candidate) {
                    candidate = "\(base)-\(suffix)"
                    suffix += 1
                }
                user.identity = candidate
                if save(user: user) {
                    usedIdentities.insert(candidate)
                    updatedUsers += 1
                }
            }
            if updatedUsers > 0 {
                WiredSwift.Logger.info("Backfilled \(updatedUsers) user identities")
            }
        } catch {
            WiredSwift.Logger.error("Could not backfill user identities: \(error.localizedDescription)")
        }
    }

    private func normalizedIdentity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func generatedIdentitySeed(from user: User) -> String {
        let source = (user.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? user.fullName : user.username) ?? "user"
        let cleaned = source.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? "user" : cleaned
    }
}
