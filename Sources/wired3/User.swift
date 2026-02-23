//
//  User.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import Fluent
import FluentSQLiteDriver



public class User: Model {    
    public static var schema: String = "users"
    
    public enum State:UInt32 {
        case CONNECTED          = 0
        case GAVE_CLIENT_INFO
        case LOGGED_IN
        case DISCONNECTED
    }
    
    @ID(key: .id)
    public var id:UUID?

    @Field(key: "username")
    public var username:String?
    
    @Field(key: "password")
    public var password:String?

    @OptionalField(key: "full_name")
    public var fullName: String?

    @OptionalField(key: "identity")
    public var identity: String?

    @OptionalField(key: "comment")
    public var comment: String?

    @OptionalField(key: "creation_time")
    public var creationTime: Date?

    @OptionalField(key: "modification_time")
    public var modificationTime: Date?

    @OptionalField(key: "login_time")
    public var loginTime: Date?

    @OptionalField(key: "edited_by")
    public var editedBy: String?

    @OptionalField(key: "downloads")
    public var downloads: Int64?

    @OptionalField(key: "download_transferred")
    public var downloadTransferred: Int64?

    @OptionalField(key: "uploads")
    public var uploads: Int64?

    @OptionalField(key: "upload_transferred")
    public var uploadTransferred: Int64?

    @OptionalField(key: "group")
    public var group: String?

    @OptionalField(key: "groups")
    public var groups: String?

    @OptionalField(key: "color")
    public var color: String?

    @OptionalField(key: "files")
    public var files: String?
    
    @Children(for: \.$user)
    public var privileges: [UserPrivilege]
        
    required public init() { }
    
    public init(username: String, password: String) {
        self.username = username
        self.password = password
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
        var success:Bool = false
        
        do {
            if let up = try $privileges.query(on: App.databaseController.pool).filter(\.$name == name).first().wait() {
                success = up.value == true ? true : false
            }
        } catch {  }

        return success
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
}
