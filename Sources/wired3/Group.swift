//
//  Group.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import GRDB

/// A named permission group stored in the `groups` SQLite table.
///
/// Groups aggregate privileges that are inherited by any `User` whose `group`
/// or `groups` field references the group name. Conforms to GRDB's
/// `FetchableRecord` and `PersistableRecord`.
public class Group: Codable, FetchableRecord, PersistableRecord {
    /// The GRDB table name for this model.
    public static let databaseTableName = "groups"

    // GRDB association
    /// GRDB has-many association to the group's fine-grained privilege records.
    public static let privileges = hasMany(GroupPrivilege.self)

    public var id: Int64?
    public var name: String?
    public var color: String?

    /// Privileges chargés à la demande (non persisté en DB)
    public var privileges: [GroupPrivilege] = []

    public enum CodingKeys: String, CodingKey {
        case id, name, color
        // `privileges` intentionnellement absent
    }

    /// Decodes a `Group` from a GRDB row or any `Decoder` implementation.
    ///
    /// - Parameter decoder: The decoder supplying column values.
    /// - Throws: `DecodingError` if a required field cannot be decoded.
    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decodeIfPresent(Int64.self, forKey: .id)
        name  = try c.decodeIfPresent(String.self, forKey: .name)
        color = try c.decodeIfPresent(String.self, forKey: .color)
    }

    /// Called by GRDB after an INSERT; captures the auto-assigned row identifier.
    ///
    /// - Parameter inserted: GRDB insertion result containing the new `rowID`.
    public func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Creates an empty `Group` with all properties at their default values.
    public required init() { }

    /// Creates a `Group` with the given name.
    ///
    /// - Parameter name: The unique group name.
    public init(name: String) {
        self.name = name
    }
}
