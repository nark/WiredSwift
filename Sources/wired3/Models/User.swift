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
/// A Wired server account stored in the `users` SQLite table.
///
/// Conforms to GRDB's `FetchableRecord` and `PersistableRecord` so instances can
/// be read from and written to the database directly. The `privileges` array is
/// loaded on demand and is never persisted to the database.
public class User: Codable, FetchableRecord, PersistableRecord {
    /// The GRDB table name for this model.
    public static let databaseTableName = "users"

    // GRDB association
    /// GRDB has-many association to the user's fine-grained privilege records.
    public static let privileges = hasMany(UserPrivilege.self)

    /// Authentication and session lifecycle state for a user account record.
    public enum State: UInt32 {
        /// Initial TCP connection established; no credentials exchanged yet.
        case CONNECTED          = 0
        /// Client has sent its application info (`wired.client_info`).
        case GAVE_CLIENT_INFO
        /// User has successfully authenticated and is fully logged in.
        case LOGGED_IN
        /// Connection has been closed or the user has logged out.
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

    /// Decodes a `User` from a GRDB row or any `Decoder` implementation.
    ///
    /// - Parameter decoder: The decoder supplying column values.
    /// - Throws: `DecodingError` if a required field cannot be decoded.
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

    /// Called by GRDB after an INSERT; captures the auto-assigned row identifier.
    ///
    /// - Parameter inserted: GRDB insertion result containing the new `rowID`.
    public func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Creates a minimal `User` with the credentials required for login.
    ///
    /// - Parameters:
    ///   - username: The account login name.
    ///   - password: The hashed password string.
    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /// Returns whether this user belongs to the named group.
    ///
    /// Checks both the primary `group` field and the comma-separated `groups`
    /// field.
    ///
    /// - Parameter string: The group name to test membership for.
    /// - Returns: `true` if the user is a member of the specified group.
    public func hasGroup(string: String) -> Bool {
        if self.group == string { return true }
        if let arr = self.groups?.split(separator: ",")
                        .map({ String($0.replacingOccurrences(of: " ", with: "")) }),
           arr.contains(string) {
            return true
        }
        return false
    }

    /// Returns whether this user holds the named `wired.account.*` privilege.
    ///
    /// If privileges have already been loaded into memory the check is performed
    /// in-process; otherwise a GRDB read query is issued.
    ///
    /// - Parameter name: The privilege name (e.g. `"wired.account.file.access_all_dropboxes"`).
    /// - Returns: `true` if the privilege exists and its value is `true`.
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

    /// Returns whether this user has read access to a file governed by the given privilege.
    ///
    /// Access is granted when any of the following is true:
    /// - The user holds `wired.account.file.access_all_dropboxes`.
    /// - The file's everyone-read bit is set.
    /// - The file's group-read bit is set and the user belongs to the file's group.
    /// - The file's owner-read bit is set and the user is the file's owner.
    ///
    /// - Parameter privilege: The `FilePrivilege` record describing the file's ownership and mode bits.
    /// - Returns: `true` if the user may read the file.
    public func hasPermission(toRead privilege: FilePrivilege, allowBypass: Bool = true) -> Bool {
        if allowBypass && self.hasPrivilege(name: "wired.account.file.access_all_dropboxes") { return true }
        if let mode = privilege.mode {
            if mode.contains(File.FilePermissions.everyoneRead) { return true }
            if let g = privilege.group, !g.isEmpty,
               mode.contains(File.FilePermissions.groupRead),
               self.hasGroup(string: g) { return true }
            if let o = privilege.owner, !o.isEmpty,
               mode.contains(File.FilePermissions.ownerRead),
               self.username == o { return true }
        }
        return false
    }

    /// Returns whether this user has write access to a file governed by the given privilege.
    ///
    /// Access is granted when any of the following is true:
    /// - The user holds `wired.account.file.access_all_dropboxes`.
    /// - The file's everyone-write bit is set.
    /// - The file's group-write bit is set and the user belongs to the file's group.
    /// - The file's owner-write bit is set and the user is the file's owner.
    ///
    /// - Parameter privilege: The `FilePrivilege` record describing the file's ownership and mode bits.
    /// - Returns: `true` if the user may write to the file.
    public func hasPermission(toWrite privilege: FilePrivilege, allowBypass: Bool = true) -> Bool {
        if allowBypass && self.hasPrivilege(name: "wired.account.file.access_all_dropboxes") { return true }
        if let mode = privilege.mode {
            if mode.contains(File.FilePermissions.everyoneWrite) { return true }
            if let g = privilege.group, !g.isEmpty,
               mode.contains(File.FilePermissions.groupWrite),
               self.hasGroup(string: g) { return true }
            if let o = privilege.owner, !o.isEmpty,
               mode.contains(File.FilePermissions.ownerWrite),
               self.username == o { return true }
        }
        return false
    }
}
