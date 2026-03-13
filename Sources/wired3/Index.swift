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
    // Tracks which rebuild cycle created this entry.
    // Allows atomic swap of the full index without a "no data" window:
    // a rebuild inserts new rows under a new generation, then deletes old ones.
    var generation_id: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    init(name: String, virtual_path: String, real_path: String, alias: Bool, generation_id: Int64 = 0) {
        self.name          = name
        self.virtual_path  = virtual_path
        self.real_path     = real_path
        self.alias         = alias
        self.generation_id = generation_id
    }
}
