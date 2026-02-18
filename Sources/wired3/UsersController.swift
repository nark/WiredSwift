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
import SQLite3

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
                    .unique(on: "username")
                    .create().wait()
            
            // create groups table
            try self.databaseController.pool
                    .schema("groups")
                    .id()
                    .field("name", .string, .required)
                    .unique(on: "name")
                    .create().wait()
            
            // defaults groups
            try Group(name: "guest").create(on: self.databaseController.pool).wait()
            let adminGroup = Group(name: "admin")
            try adminGroup.create(on: self.databaseController.pool).wait()
            
            // defaults users
            let admin = User(username: "admin", password: "admin".sha256())
            let guest = User(username: "guest", password: "".sha256())
            
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
            
            // USERS PRIVILEGES
            for field in App.spec.accountPrivileges! {
                let privilege = UserPrivilege(name: field, value: true, user: admin)
                try privilege.create(on: self.databaseController.pool).wait()
            }

            // GROUPS PRIVILEGES
            for field in App.spec.accountPrivileges! {
                let privilege = GroupPrivilege(name: field, value: true, group: adminGroup)
                try privilege.create(on: self.databaseController.pool).wait()
            }
        } catch let error {
            WiredSwift.Logger.error("Cannot create tables")
            WiredSwift.Logger.error("\(error)")
        }
    }
}
