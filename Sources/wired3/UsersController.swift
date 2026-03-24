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

public class UsersController: TableController, SocketPasswordDelegate {
    var lastUserID: UInt32 = 0
    var lastUserIDLock: NSLock = NSLock()

    // MARK: - Public
    public func nextUserID() -> UInt32 {
        lastUserIDLock.lock()
        defer { lastUserIDLock.unlock() }
        self.lastUserID += 1
        return self.lastUserID
    }


    // MARK: - Database (SocketPasswordDelegate)
    public func passwordForUsername(username: String) -> String? {
        user(withUsername: username)?.password
    }

    public func passwordSaltForUsername(username: String) -> String? {
        user(withUsername: username)?.passwordSalt
    }


    // MARK: - Fetch
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

    public func user(withUsername username: String) -> User? {
        try? databaseController.dbQueue.read { db in
            try User.filter(Column("username") == username).fetchOne(db)
        }
    }

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

    public func isIdentityAvailable(_ identity: String) -> Bool {
        let existing = try? databaseController.dbQueue.read { db in
            try User.filter(Column("identity") == identity).fetchOne(db)
        }
        return existing == nil
    }

    public func users() -> [User] {
        (try? databaseController.dbQueue.read { db in try User.fetchAll(db) }) ?? []
    }

    public func groups() -> [Group] {
        (try? databaseController.dbQueue.read { db in try Group.fetchAll(db) }) ?? []
    }

    public func group(withName name: String) -> Group? {
        try? databaseController.dbQueue.read { db in
            try Group.filter(Column("name") == name).fetchOne(db)
        }
    }

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
    @discardableResult
    public func save(user: User) -> Bool {
        do {
            try databaseController.dbQueue.write { db in try user.save(db) }
            return true
        } catch { return false }
    }

    @discardableResult
    public func save(group: Group) -> Bool {
        do {
            try databaseController.dbQueue.write { db in try group.save(db) }
            return true
        } catch { return false }
    }

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
    }

    /// For existing installations, grant `wired.account.board.add_reactions` (true) to every
    /// user and group that already has `wired.account.board.add_posts`, so that accounts
    /// created before this feature was introduced can immediately use reactions without manual
    /// configuration. Accounts that did not have add_posts keep the privilege absent (false).
    private func migrateAddReactionsPrivilegeIfNeeded(db: OpaquePointer) {
        let reactionPrivilege = "wired.account.board.add_reactions"
        let postPrivilege     = "wired.account.board.add_posts"

        let tables: [(table: String, ownerColumn: String)] = [
            ("user_privileges",  "user_id"),
            ("group_privileges", "group_id")
        ]

        for entry in tables {
            // Only insert where add_posts = true and add_reactions does not yet exist.
            let sql = """
            INSERT OR IGNORE INTO "\(entry.table)" (id, name, value, \(entry.ownerColumn))
            SELECT lower(hex(randomblob(16))), '\(reactionPrivilege)', 1, \(entry.ownerColumn)
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

    private func migratePrivilegesTableIfNeeded(db: OpaquePointer,
                                                table: String,
                                                ownerColumn: String,
                                                constraintName: String) {
        guard let schema = readSchema(db: db, table: table) else { return }
        guard schema.contains("UNIQUE (\"name\")"), !schema.contains("UNIQUE (\"name\",") else { return }

        let migratedTable = "\(table)_migrated"
        let statements = [
            "BEGIN TRANSACTION;",
            "CREATE TABLE IF NOT EXISTS \"\(migratedTable)\" (\"id\" UUID PRIMARY KEY, \"name\" TEXT NOT NULL, \"value\" INTEGER NOT NULL, \"\(ownerColumn)\" UUID NOT NULL, CONSTRAINT \"\(constraintName)\" UNIQUE (\"name\", \"\(ownerColumn)\"));",
            "INSERT OR IGNORE INTO \"\(migratedTable)\" (\"id\", \"name\", \"value\", \"\(ownerColumn)\") SELECT \"id\", \"name\", \"value\", \"\(ownerColumn)\" FROM \"\(table)\";",
            "DROP TABLE \"\(table)\";",
            "ALTER TABLE \"\(migratedTable)\" RENAME TO \"\(table)\";",
            "COMMIT;"
        ]

        for statement in statements {
            if sqliteExec(db: db, statement) != SQLITE_OK {
                _ = sqliteExec(db: db, "ROLLBACK;")
                if let message = sqlite3_errmsg(db) {
                    WiredSwift.Logger.error("Could not migrate \(table): \(String(cString: message))")
                }
                return
            }
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
            ("identity",          "ALTER TABLE \"users\" ADD COLUMN \"identity\" TEXT;"),
            ("offline_public_key", "ALTER TABLE \"users\" ADD COLUMN \"offline_public_key\" BLOB;"),
            ("offline_key_id",    "ALTER TABLE \"users\" ADD COLUMN \"offline_key_id\" TEXT;"),
            ("offline_crypto",    "ALTER TABLE \"users\" ADD COLUMN \"offline_crypto\" TEXT;")
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
        ] {
            if sqliteExec(db: db, idx) != SQLITE_OK {
                if let message = sqlite3_errmsg(db) {
                    WiredSwift.Logger.error("Could not create offline_messages index: \(String(cString: message))")
                }
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
