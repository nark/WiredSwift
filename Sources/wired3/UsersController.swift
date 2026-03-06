//
//  UsersController.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import Fluent
import FluentSQLiteDriver
#if os(Linux)
import CSQLite
#else
import SQLite3
#endif

public class UsersController: TableController, SocketPasswordDelegate {
    //var connectedUsers:[UInt32:User] = [:]
    var lastUserID:UInt32 = 0
    var lastUserIDLock:Lock = Lock()
    
    // MARK: - Public
    public func nextUserID() -> UInt32 {
        self.lastUserID += 1
        
        return self.lastUserID
    }
    
        
    
    
    // MARK: - Database
    public func passwordForUsername(username: String) -> String? {
        if let user = self.user(withUsername: username) {
            return user.password
        }
        
        return nil
    }
    
    
    public func user(withUsername username: String, password: String) -> User? {
        var user:User? = nil

        do {
            user = try User.query(on: databaseController.pool)
                        .with(\.$privileges)
                        .filter(\.$username == username)
                        .filter(\.$password == password)
                        .first()
                        .wait()
            
        } catch {  }
                
        return user
    }
    
    
    public func user(withUsername username: String) -> User? {
        var user:User? = nil
                
        do {
            user = try User.query(on: databaseController.pool)
                        .filter(\.$username == username)
                        .first()
                        .wait()
            
        } catch {  }
        
        return user
    }

    public func userWithPrivileges(withUsername username: String) -> User? {
        do {
            return try User.query(on: databaseController.pool)
                .with(\.$privileges)
                .filter(\.$username == username)
                .first()
                .wait()
        } catch {
            return nil
        }
    }

    public func userWithPrivileges(identity: String) -> User? {
        do {
            return try User.query(on: databaseController.pool)
                .with(\.$privileges)
                .filter(\.$identity == identity)
                .first()
                .wait()
        } catch {
            return nil
        }
    }

    public func users(matchingIdentityQuery query: String, limit: Int = 50) -> [User] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        do {
            let listedUsers = try User.query(on: databaseController.pool)
                .all()
                .wait()

            return listedUsers
                .filter { user in
                    let username = (user.username ?? "").lowercased()
                    let fullName = (user.fullName ?? "").lowercased()
                    let identity = (user.identity ?? "").lowercased()
                    return username.contains(normalizedQuery)
                        || fullName.contains(normalizedQuery)
                        || identity.contains(normalizedQuery)
                }
                .prefix(limit)
                .map { $0 }
        } catch {
            return []
        }
    }

    public func isIdentityAvailable(_ identity: String) -> Bool {
        do {
            let existing = try User.query(on: databaseController.pool)
                .filter(\.$identity == identity)
                .first()
                .wait()
            return existing == nil
        } catch {
            return false
        }
    }

    private func normalizedIdentity(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func generatedIdentitySeed(from user: User) -> String {
        let source = (user.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? user.fullName
            : user.username) ?? "user"

        let cleaned = source
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return cleaned.isEmpty ? "user" : cleaned
    }

    public func backfillStableIdentitiesIfNeeded() {
        do {
            let loadedUsers = try User.query(on: databaseController.pool)
                .all()
                .wait()
                .sorted {
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
                        if save(user: user) {
                            updatedUsers += 1
                        }
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

    public func users() -> [User] {
        do {
            return try User.query(on: databaseController.pool)
                .all()
                .wait()
        } catch {
            return []
        }
    }

    public func groups() -> [Group] {
        do {
            return try Group.query(on: databaseController.pool)
                .all()
                .wait()
        } catch {
            return []
        }
    }

    public func group(withName name: String) -> Group? {
        do {
            return try Group.query(on: databaseController.pool)
                .filter(\.$name == name)
                .first()
                .wait()
        } catch {
            return nil
        }
    }

    public func groupWithPrivileges(withName name: String) -> Group? {
        do {
            return try Group.query(on: databaseController.pool)
                .with(\.$privileges)
                .filter(\.$name == name)
                .first()
                .wait()
        } catch {
            return nil
        }
    }

    @discardableResult
    public func save(user: User) -> Bool {
        do {
            try user.save(on: databaseController.pool).wait()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func save(group: Group) -> Bool {
        do {
            try group.save(on: databaseController.pool).wait()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func setUserPrivilege(_ name: String, value: Bool, for user: User) -> Bool {
        guard let userID = user.id else { return false }

        do {
            if let existing = try UserPrivilege.query(on: databaseController.pool)
                .filter(\.$user.$id == userID)
                .filter(\.$name == name)
                .first()
                .wait() {
                existing.value = value
                try existing.save(on: databaseController.pool).wait()
                return true
            }

            let privilege = UserPrivilege(name: name, value: value, user: user)
            try privilege.create(on: databaseController.pool).wait()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func setGroupPrivilege(_ name: String, value: Bool, for group: Group) -> Bool {
        guard let groupID = group.id else { return false }

        do {
            if let existing = try GroupPrivilege.query(on: databaseController.pool)
                .filter(\.$group.$id == groupID)
                .filter(\.$name == name)
                .first()
                .wait() {
                existing.value = value
                try existing.save(on: databaseController.pool).wait()
                return true
            }

            let privilege = GroupPrivilege(name: name, value: value, group: group)
            try privilege.create(on: databaseController.pool).wait()
            return true
        } catch {
            return false
        }
    }

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
            if sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK {
                _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
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
        if sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK {
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
            if sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK {
                if let message = sqlite3_errmsg(db) {
                    WiredSwift.Logger.error("Could not add users.\(column) column: \(String(cString: message))")
                }
            } else {
                WiredSwift.Logger.info("Added users.\(column) column")
            }
        }

        let uniqueIdentityIndex = "CREATE UNIQUE INDEX IF NOT EXISTS \"users_identity_unique\" ON \"users\"(\"identity\");"
        if sqlite3_exec(db, uniqueIdentityIndex, nil, nil, nil) != SQLITE_OK {
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

        if sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK {
            if let message = sqlite3_errmsg(db) {
                WiredSwift.Logger.error("Could not create offline_messages table: \(String(cString: message))")
            }
            return
        }

        let indexStatements = [
            "CREATE INDEX IF NOT EXISTS \"offline_messages_recipient_index\" ON \"offline_messages\"(\"recipient_identity\");",
            "CREATE INDEX IF NOT EXISTS \"offline_messages_expires_index\" ON \"offline_messages\"(\"expires_at\");"
        ]

        for indexStatement in indexStatements {
            if sqlite3_exec(db, indexStatement, nil, nil, nil) != SQLITE_OK {
                if let message = sqlite3_errmsg(db) {
                    WiredSwift.Logger.error("Could not create offline_messages index: \(String(cString: message))")
                }
            }
        }
    }

    private func readSchema(db: OpaquePointer, table: String) -> String? {
        let query = "SELECT sql FROM sqlite_master WHERE type='table' AND name='\(table)' LIMIT 1;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0) else {
            return nil
        }

        return String(cString: cString)
    }
    
    
    // MARK: -
    public override func createTables() {
        
        
        do {
            // create users table
            try self.databaseController.pool
                    .schema("users")
                    .id()
                    .field("username", .string, .required)
                    .field("password", .string, .required)
                    .field("full_name", .string)
                    .field("identity", .string)
                    .field("comment", .string)
                    .field("creation_time", .datetime)
                    .field("modification_time", .datetime)
                    .field("login_time", .datetime)
                    .field("edited_by", .string)
                    .field("downloads", .uint64)
                    .field("download_transferred", .uint64)
                    .field("uploads", .uint64)
                    .field("upload_transferred", .uint64)
                    .field("group", .string)
                    .field("groups", .string)
                    .field("color", .string)
                    .field("files", .string)
                    .field("offline_public_key", .data)
                    .field("offline_key_id", .string)
                    .field("offline_crypto", .string)
                    .unique(on: "username")
                    .unique(on: "identity")
                    .create().wait()
            
            // create groups table
            try self.databaseController.pool
                    .schema("groups")
                    .id()
                    .field("name", .string, .required)
                    .field("color", .string)
                    .unique(on: "name")
                    .create().wait()
            
            // defaults groups
            let guestGroup = Group(name: "guest")
            guestGroup.color = "0"
            try guestGroup.create(on: self.databaseController.pool).wait()
            let adminGroup = Group(name: "admin")
            adminGroup.color = "1"
            try adminGroup.create(on: self.databaseController.pool).wait()
            
            // defaults users
            let admin = User(username: "admin", password: "admin".sha256())
            let guest = User(username: "guest", password: "".sha256())
            admin.color = "1"
            guest.color = "0"
            
            try admin.create(on: self.databaseController.pool).wait()
            try guest.create(on: self.databaseController.pool).wait()
            
            // create privileges tables
            try self.databaseController.pool
                    .schema("user_privileges")
                    .id()
                    .field("name", .string, .required)
                    .field("value", .bool, .required)
                    .field("user_id", .uuid, .required)
                    .unique(on: "name", "user_id")
                    .create().wait()
            
            try self.databaseController.pool
                    .schema("group_privileges")
                    .id()
                    .field("name", .string, .required)
                    .field("value", .bool, .required)
                    .field("group_id", .uuid, .required)
                    .unique(on: "name", "group_id")
                    .create().wait()

            try self.databaseController.pool
                    .schema("offline_messages")
                    .id()
                    .field("sender_identity", .string, .required)
                    .field("recipient_identity", .string, .required)
                    .field("ciphertext", .data, .required)
                    .field("nonce", .data, .required)
                    .field("wrapped_key_recipient", .data, .required)
                    .field("wrapped_key_sender", .data)
                    .field("recipient_key_id", .string)
                    .field("created_at", .datetime, .required)
                    .field("expires_at", .datetime, .required)
                    .field("delivered_at", .datetime)
                    .field("acked_at", .datetime)
                    .create().wait()
            
            // USERS PRIVILEGES
            for field in App.spec.accountPrivileges! {
                guard App.spec.fieldsByName[field]?.type == .bool else { continue }
                let privilege = UserPrivilege(name: field, value: true, user: admin)
                try privilege.create(on: self.databaseController.pool).wait()
            }

            // GROUPS PRIVILEGES
            for field in App.spec.accountPrivileges! {
                guard App.spec.fieldsByName[field]?.type == .bool else { continue }
                let privilege = GroupPrivilege(name: field, value: true, group: adminGroup)
                try privilege.create(on: self.databaseController.pool).wait()
            }
        } catch let error {
            WiredSwift.Logger.error("Cannot create tables")
            WiredSwift.Logger.error("\(error)")
        }
    }
}
