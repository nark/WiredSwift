//
//  User.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import GRDB


// PersistableRecord (non-MutablePersistableRecord) fournit des méthodes non-mutating
// adaptées aux classes (reference types). Les structs utilisent MutablePersistableRecord.
public class User: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "users"

    // GRDB association
    public static let privileges = hasMany(UserPrivilege.self)

    public enum State: UInt32 {
        case CONNECTED          = 0
        case GAVE_CLIENT_INFO
        case LOGGED_IN
        case DISCONNECTED
    }

    public var id: Int64?
    public var username: String?
    public var password: String?
    public var passwordSalt: String?
    public var fullName: String?
    public var identity: String?
    public var comment: String?
    public var creationTime: Date?
    public var modificationTime: Date?
    public var loginTime: Date?
    public var editedBy: String?
    public var downloads: Int64?
    public var downloadTransferred: Int64?
    public var uploads: Int64?
    public var uploadTransferred: Int64?
    public var group: String?
    public var groups: String?
    public var color: String?
    public var files: String?

    /// Privileges chargés à la demande (non persisté en DB)
    public var privileges: [UserPrivilege] = []

    public enum CodingKeys: String, CodingKey {
        case id
        case username
        case password
        case passwordSalt = "password_salt"
        case fullName = "full_name"
        case identity
        case comment
        case creationTime = "creation_time"
        case modificationTime = "modification_time"
        case loginTime = "login_time"
        case editedBy = "edited_by"
        case downloads
        case downloadTransferred = "download_transferred"
        case uploads
        case uploadTransferred = "upload_transferred"
        case group
        case groups
        case color
        case files
        // `privileges` intentionnellement absent → non encodé vers la DB
    }

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                  = try c.decodeIfPresent(Int64.self, forKey: .id)
        username            = try c.decodeIfPresent(String.self, forKey: .username)
        password            = try c.decodeIfPresent(String.self, forKey: .password)
        passwordSalt        = try c.decodeIfPresent(String.self, forKey: .passwordSalt)
        fullName            = try c.decodeIfPresent(String.self, forKey: .fullName)
        identity            = try c.decodeIfPresent(String.self, forKey: .identity)
        comment             = try c.decodeIfPresent(String.self, forKey: .comment)
        creationTime        = try c.decodeIfPresent(Date.self, forKey: .creationTime)
        modificationTime    = try c.decodeIfPresent(Date.self, forKey: .modificationTime)
        loginTime           = try c.decodeIfPresent(Date.self, forKey: .loginTime)
        editedBy            = try c.decodeIfPresent(String.self, forKey: .editedBy)
        downloads           = try c.decodeIfPresent(Int64.self, forKey: .downloads)
        downloadTransferred = try c.decodeIfPresent(Int64.self, forKey: .downloadTransferred)
        uploads             = try c.decodeIfPresent(Int64.self, forKey: .uploads)
        uploadTransferred   = try c.decodeIfPresent(Int64.self, forKey: .uploadTransferred)
        group               = try c.decodeIfPresent(String.self, forKey: .group)
        groups              = try c.decodeIfPresent(String.self, forKey: .groups)
        color               = try c.decodeIfPresent(String.self, forKey: .color)
        files               = try c.decodeIfPresent(String.self, forKey: .files)
    }

    public func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    public func hasGroup(string: String) -> Bool {
        if self.group == string { return true }
        if let arr = self.groups?.split(separator: ",")
                        .map({ String($0.replacingOccurrences(of: " ", with: "")) }),
           arr.firstIndex(of: string) != nil {
            return true
        }
        return false
    }

    public func hasPrivilege(name: String) -> Bool {
        // Vérification en mémoire si les privileges sont déjà chargés
        if !privileges.isEmpty {
            return privileges.first(where: { $0.name == name })?.value == true
        }
        // Sinon requête GRDB
        guard let userId = id else { return false }
        return (try? App.databaseController.dbQueue.read { db in
            try UserPrivilege
                .filter(Column("user_id") == userId && Column("name") == name)
                .fetchOne(db)
        })?.value == true
    }

    public func hasPermission(toRead privilege: FilePrivilege) -> Bool {
        if self.hasPrivilege(name: "wired.account.file.access_all_dropboxes") { return true }
        if let mode = privilege.mode {
            if mode.contains(File.FilePermissions.everyoneRead) { return true }
            if let g = privilege.group, g.count > 0,
               mode.contains(File.FilePermissions.groupRead),
               self.hasGroup(string: g) { return true }
            if let o = privilege.owner, o.count > 0,
               mode.contains(File.FilePermissions.ownerRead),
               self.username == o { return true }
        }
        return false
    }

    public func hasPermission(toWrite privilege: FilePrivilege) -> Bool {
        if self.hasPrivilege(name: "wired.account.file.access_all_dropboxes") { return true }
        if let mode = privilege.mode {
            if mode.contains(File.FilePermissions.everyoneWrite) { return true }
            if let g = privilege.group, g.count > 0,
               mode.contains(File.FilePermissions.groupWrite),
               self.hasGroup(string: g) { return true }
            if let o = privilege.owner, o.count > 0,
               mode.contains(File.FilePermissions.ownerWrite),
               self.username == o { return true }
        }
        return false
    }
}
