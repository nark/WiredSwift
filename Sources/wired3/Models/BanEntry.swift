//
//  BanEntry.swift
//  wired3
//

import Foundation
import GRDB

/// An IP ban record stored in the `banlist` SQLite table.
///
/// When a client connects, its IP address is matched against the `ipPattern`
/// of each active `BanEntry`. Entries with a past `expirationDate` are treated
/// as expired and should be ignored or purged.
public final class BanEntry: FetchableRecord, PersistableRecord {
    /// The GRDB table name for this model.
    public static let databaseTableName = "banlist"

    /// Auto-assigned database row identifier; `nil` before the first INSERT.
    public var id: Int64?
    /// IP address or subnet pattern used to match incoming connections.
    public var ipPattern: String
    /// Date and time when this ban expires, or `nil` for a permanent ban.
    public var expirationDate: Date?

    enum Columns {
        static let id = Column("id")
        static let ipPattern = Column("ip_pattern")
        static let expirationDate = Column("expiration_date")
    }

    /// Initialises a `BanEntry` from a GRDB database row.
    ///
    /// - Parameter row: The GRDB `Row` containing column values.
    public required init(row: Row) {
        id = row["id"]
        ipPattern = row["ip_pattern"]
        expirationDate = row["expiration_date"]
    }

    /// Creates a `BanEntry` with the given pattern and optional expiration.
    ///
    /// - Parameters:
    ///   - ipPattern: IP address or subnet pattern to ban.
    ///   - expirationDate: When the ban expires, or `nil` for a permanent ban.
    public init(ipPattern: String, expirationDate: Date?) {
        self.ipPattern = ipPattern
        self.expirationDate = expirationDate
    }

    /// Encodes this ban entry's fields into a GRDB `PersistenceContainer`.
    ///
    /// - Parameter container: The container to write column values into.
    /// - Throws: Never; declared `throws` to satisfy the protocol.
    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["ip_pattern"] = ipPattern
        container["expiration_date"] = expirationDate
    }

    /// Called by GRDB after an INSERT; captures the auto-assigned row identifier.
    ///
    /// - Parameter inserted: GRDB insertion result containing the new `rowID`.
    public func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
