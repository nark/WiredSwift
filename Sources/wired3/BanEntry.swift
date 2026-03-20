//
//  BanEntry.swift
//  wired3
//

import Foundation
import GRDB

public final class BanEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "banlist"

    public var id: Int64?
    public var ipPattern: String
    public var expirationDate: Date?

    enum Columns {
        static let id = Column("id")
        static let ipPattern = Column("ip_pattern")
        static let expirationDate = Column("expiration_date")
    }

    public required init(row: Row) {
        id = row["id"]
        ipPattern = row["ip_pattern"]
        expirationDate = row["expiration_date"]
    }

    public init(ipPattern: String, expirationDate: Date?) {
        self.ipPattern = ipPattern
        self.expirationDate = expirationDate
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["ip_pattern"] = ipPattern
        container["expiration_date"] = expirationDate
    }

    public func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
