//
//  GroupPrivilege.swift
//  wired3
//
//  Created by Rafael Warnault on 25/03/2021.
//

import Foundation
import GRDB

public struct GroupPrivilege: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "group_privileges"

    public var id: Int64?
    public var name: String?
    public var value: Bool?
    public var groupId: Int64

    public enum CodingKeys: String, CodingKey {
        case id, name, value
        case groupId = "group_id"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(name: String, value: Bool, groupId: Int64) {
        self.name    = name
        self.value   = value
        self.groupId = groupId
    }
}
