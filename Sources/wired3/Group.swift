//
//  Group.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import GRDB


public class Group: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "groups"

    // GRDB association
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

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decodeIfPresent(Int64.self, forKey: .id)
        name  = try c.decodeIfPresent(String.self, forKey: .name)
        color = try c.decodeIfPresent(String.self, forKey: .color)
    }

    public func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public required init() { }

    public init(name: String) {
        self.name = name
    }
}
