//
//  User.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import GRDB



public class User: Record {
    public enum State:UInt32 {
        case CONNECTED          = 0
        case GAVE_CLIENT_INFO
        case LOGGED_IN
        case DISCONNECTED
    }
    
    public var userID:UInt32!
    public var id:Int64?
    public var username:String?
    public var password:String?
    public var socket:P7Socket?
    public var state:State = .DISCONNECTED
    public var ip:String?
    public var host:String?
    public var nick:String?
    public var status:String?
    public var group:String?
    public var groups:String?
    public var icon:Data?
    
    public var transfer:Transfer?
    
    static let privileges = hasMany(UserPrivilege.self)
    var privileges: QueryInterfaceRequest<UserPrivilege> {
        request(for: User.privileges)
    }
    
    
    public init(username: String, password: String) {
        self.username = username
        self.password = password
        
        super.init()
    }
    

    /// Creates a record from a database row
    public required init(row: Row) {
        self.id = row[Columns.id]
        self.username = row[Columns.username]
        self.password = row[Columns.password]
        
        super.init(row: row)
    }
    
    
    public func hasGroup(string:String) -> Bool {
        if self.group == string {
            return true
        }
        
        if let groupsArray = self.groups?.split(separator: ",").map({ String($0.replacingOccurrences(of: " ", with: "")) }) {
            if (groupsArray.firstIndex(of: string) != nil) {
                return true
            }
        }
        
        return false
    }
    

    
    public func hasPrivilege(name:String) -> Bool {
        var success:Bool? = false
        
        do {
            try App.databaseController.pool.read { db in
                let sql = "SELECT * FROM user_privileges WHERE user_id = ? AND name = ? AND value = 1"
                if let p = try UserPrivilege.fetchOne(db, sql: sql, arguments: [self.id, name]) {
                    success = p.value
                }
            }
        } catch {  }
        
        return success ?? false
    }
    
    
    public func hasPermission(toRead privilege:FilePrivilege) -> Bool {
        // user can read all dropboxes (bypass)
        if self.hasPrivilege(name: "wired.account.file.access_all_dropboxes") {
            return true
        }
        
        if let mode = privilege.mode {
            // everyone can read this privilege
            if mode.contains(File.FilePermissions.everyoneRead) {
                return true
            }
            
            // user can read has group
            if let group = privilege.group, group.count > 0, mode.contains(File.FilePermissions.groupRead) {
                if self.hasGroup(string: group) {
                    return true
                }
            }
            
            // user can read
            if let owner = privilege.owner, owner.count > 0, mode.contains(File.FilePermissions.ownerRead) {
                if self.username == owner {
                    return true
                }
            }
        }
       
        return false
    }

    
     public func hasPermission(toWrite privilege:FilePrivilege) -> Bool {
         // user can read all dropboxes (bypass)
         if self.hasPrivilege(name: "wired.account.file.access_all_dropboxes") {
             return true
         }
         
         if let mode = privilege.mode {
             // everyone can read this privilege
             if mode.contains(File.FilePermissions.everyoneWrite) {
                 return true
             }
             
             // user can read has group
             if let group = privilege.group, group.count > 0, mode.contains(File.FilePermissions.groupWrite) {
                 if self.hasGroup(string: group) {
                     return true
                 }
             }
             
             // user can read
             if let owner = privilege.owner, owner.count > 0, mode.contains(File.FilePermissions.ownerWrite) {
                 if self.username == owner {
                     return true
                 }
             }
         }
        
         return false
    }
    
    
    // MARK: - Record
    /// The table name
    public override class var databaseTableName: String { "users" }

    /// The table columns
    enum Columns: String, ColumnExpression {
        case id, username, password
    }

    /// The values persisted in the database
    public override func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.username] = username
        container[Columns.password] = password
    }

    // Update auto-incremented id upon successful insertion
    public override func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }
}
