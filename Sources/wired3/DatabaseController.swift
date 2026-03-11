//
//  DatabaseController.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import GRDB
#if os(Linux)
import CSQLite
#else
import SQLite3
#endif

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public class DatabaseController {
    let baseURL: URL
    private(set) var dbQueue: DatabaseQueue!

    public init(baseURL: URL, spec: P7Spec) {
        self.baseURL = baseURL
    }

    @discardableResult
    public func initDatabase() -> Bool {
        do {
            var config = Configuration()
            config.label = "wired3"
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
            }
            dbQueue = try DatabaseQueue(path: baseURL.path, configuration: config)

            var migrator = DatabaseMigrator()
            WiredMigrations.register(into: &migrator)
            try migrator.migrate(dbQueue)

            Logger.info("Database opened at \(baseURL.path)")
            return true
        } catch {
            Logger.error("Cannot open database: \(error)")
            return false
        }
    }
}
