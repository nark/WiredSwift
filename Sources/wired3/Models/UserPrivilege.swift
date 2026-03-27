//
//  UserPrivilege.swift
//  wired3
//
//  Created by Rafael Warnault on 25/03/2021.
//

import Foundation
import GRDB

/// A single `wired.account.*` privilege entry for a user, stored in `user_privileges`.
///
/// Each row records one named privilege flag and its boolean value for a specific
/// user. Conforms to GRDB's `MutablePersistableRecord` (struct semantics) so the
/// auto-generated row ID is written back into the value after insertion.
public struct UserPrivilege: Codable, FetchableRecord, MutablePersistableRecord {
    /// The GRDB table name for this model.
    public static let databaseTableName = "user_privileges"

    /// Auto-assigned database row identifier; `nil` before the first INSERT.
    public var id: Int64?
    /// The privilege name (e.g. `"wired.account.chat.set_topic"`).
    public var name: String?
    /// Whether the privilege is granted (`true`) or denied (`false`).
    public var value: Bool?
    /// Foreign-key reference to the owning `User.id`.
    public var userId: Int64

    public enum CodingKeys: String, CodingKey {
        case id, name, value
        case userId = "user_id"
    }

    /// Called by GRDB after an INSERT; writes the auto-assigned row ID back into `id`.
    ///
    /// - Parameter inserted: GRDB insertion result containing the new `rowID`.
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Creates a `UserPrivilege` with all required fields.
    ///
    /// - Parameters:
    ///   - name: The privilege name string (e.g. `"wired.account.board.read_boards"`).
    ///   - value: `true` to grant the privilege, `false` to deny it.
    ///   - userId: The `id` of the `User` this privilege belongs to.
    public init(name: String, value: Bool, userId: Int64) {
        self.name   = name
        self.value  = value
        self.userId = userId
    }
}
