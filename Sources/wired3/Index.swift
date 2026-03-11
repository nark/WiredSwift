//
//  Index.swift
//  wired3
//
//  Created by Rafael Warnault on 26/03/2021.
//

import Foundation
import GRDB

struct WiredIndex: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "index"

    var id: Int64?
    var name: String
    var virtual_path: String
    var real_path: String
    var alias: Bool

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    init(name: String, virtual_path: String, real_path: String, alias: Bool) {
        self.name         = name
        self.virtual_path = virtual_path
        self.real_path    = real_path
        self.alias        = alias
    }
}
