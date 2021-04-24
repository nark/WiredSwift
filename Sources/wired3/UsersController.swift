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

public class UsersController: TableController, SocketPasswordDelegate {
    //var connectedUsers:[UInt32:User] = [:]
    var lastUserID:UInt32 = 0
    
    // MARK: - Public
    public func nextUserID() -> UInt32 {
        self.lastUserID += 1
        
        return self.lastUserID
    }
    
//
//    public func addUser(user:User) {
//        self.connectedUsers[user.userID] = user
//
//        WiredSwift.Logger.info("Connected users: \(self.connectedUsers)")
//    }
//
//
//    public func removeUser(user:User) {
//        user.socket?.disconnect()
//
//        self.connectedUsers[user.userID] = nil
//
//        WiredSwift.Logger.info("Connected users: \(self.connectedUsers)")
//    }
//
//

    
    
    

    
    
    
    
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
                    .unique(on: "name")
                    .create().wait()
            
            try self.databaseController.pool
                    .schema("group_privileges")
                    .id()
                    .field("name", .string, .required)
                    .field("value", .bool, .required)
                    .field("group_id", .uuid, .required)
                    .unique(on: "name")
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

