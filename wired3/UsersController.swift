//
//  ConnectionsController.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift

public class UsersController: TableController, SocketPasswordDelegate {
    var connectedUsers:[UInt32:User] = [:]
    var lastUserID:UInt32 = 0
    
    // MARK: - Public
    public func nextUserID() -> UInt32 {
        self.lastUserID += 1
        
        return self.lastUserID
    }
    
    
    public func addUser(user:User) {
        self.connectedUsers[user.userID] = user
        
        WiredSwift.Logger.info("Connected users: \(self.connectedUsers)")
    }
    
    
    public func removeUser(user:User) {
        user.socket?.disconnect()
        
        self.connectedUsers[user.userID] = nil
        
        WiredSwift.Logger.info("Connected users: \(self.connectedUsers)")
    }
    
    
    
    public func broadcast(message:P7Message) {
        DispatchQueue.global(qos: .default).async {
            for (_, user) in self.connectedUsers {
                _ = user.socket?.write(message)
            }
        }
    }
    
    
    
    
    // MARK: -
    public func reply(user: User, reply:P7Message, message:P7Message) {
        if let t = message.uint32(forField: "wired.transaction") {
            reply.addParameter(field: "wired.transaction", value: t)
        }
        _ = user.socket?.write(reply)
    }
    
    
    public func replyError(user: User, error:String, message:P7Message) {
        let reply = P7Message(withName: "wired.error", spec: user.socket!.spec)
        
        reply.addParameter(field: "wired.error.string", value: "Login failed")
        
        print("error \(error)")
        if let errorEnumValue = message.spec.errorsByName[error] {
            print("errorEnumValue \(errorEnumValue.name)")
            reply.addParameter(field: "wired.error", value: UInt32(errorEnumValue.id))
        }
        
        
        self.reply(user: user, reply: reply, message: message)
    }
    
    public func replyOK(user: User, message:P7Message) {
        let reply = P7Message(withName: "wired.okay", spec: user.socket!.spec)
        
        self.reply(user: user, reply: reply, message: message)
    }
    
    
    
    
    // MARK: - Database
    public func passwordForUsername(username: String) -> String? {
        if let user = self.user(withUsername: username) {
            return user.password
        }
        
        return nil
    }
    
    
    public func user(withUsername username: String) -> User? {
        var user:User? = nil
        
        do {
            try databaseController.pool.read { db in
                if let u = try User.fetchOne(db, sql: "SELECT * FROM users WHERE username = ?", arguments: [username]) {
                    user = u
                }
            }
        } catch {  }
        
        return user
    }
    
    
    // MARK: -
    public override func createTables() {
        do {
            try self.databaseController.pool.write { db in
                // USERS
                try db.create(table: "users") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("username", .text).notNull()
                    t.column("password", .text).notNull()
                    t.column("full_name", .text)
                    t.column("comment", .text)
                    t.column("creation_time", .datetime)
                    t.column("modification_time", .datetime)
                    t.column("login_time", .datetime)
                    t.column("edited_by", .text)
                    t.column("downloads", .integer).notNull().defaults(to: 0)
                    t.column("download_transferred", .integer).notNull().defaults(to: 0)
                    t.column("uploads", .integer).notNull().defaults(to: 0)
                    t.column("upload_transferred", .integer).notNull().defaults(to: 0)
                    t.column("group", .text)
                    t.column("groups", .text)
                    t.column("color", .text)
                    t.column("files", .text)
                }
                
                
                // GROUPS
                try db.create(table: "groups") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("name", .text).notNull()
                }
                
                let guestGroup = Group(name: "guest")
                try guestGroup.insert(db)
                
                let adminGroup = Group(name: "admin")
                try adminGroup.insert(db)

            
                let guest = User(username: "guest", password: "".sha256())
                try guest.insert(db)
                
                let admin = User(username: "admin", password: "admin".sha256())
                try admin.insert(db)
                                
                // PRIVILEGES
                try db.create(table: "user_privileges") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("user_id", .integer).notNull()
                    t.column("name", .text).notNull()
                    t.column("value", .boolean).notNull()
                }
                
                try db.create(table: "group_privileges") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("group_id", .integer).notNull()
                    t.column("name", .text).notNull()
                    t.column("value", .boolean).notNull()
                }

                // USERS PRIVILEGES
                for field in App.spec.accountPrivileges! {
                    let privilege = UserPrivilege(name: field, value: true, user: admin)
                    try privilege.insert(db)
                }

                // GROUPS PRIVILEGES
                for field in App.spec.accountPrivileges! {
                    let privilege = GroupPrivilege(name: field, value: true, group: adminGroup)
                    try privilege.insert(db)
                }
            }
        } catch let error {
            Logger.error("Cannot create tables")
            Logger.error("\(error)")
        }
    }
}

