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

/// Owns the GRDB `DatabaseQueue` and runs all registered schema migrations.
///
/// Every controller that needs database access receives a reference to the single
/// shared `DatabaseController` instance that `AppController` creates at startup.
public class DatabaseController {
    let baseURL: URL
    public private(set) var dbQueue: DatabaseQueue!

    /// Creates a new `DatabaseController` for the database at `baseURL`.
    ///
    /// - Parameters:
    ///   - baseURL: File URL of the SQLite database file.
    ///   - spec: The P7 protocol specification (reserved for future use).
    public init(baseURL: URL, spec: P7Spec) {
        self.baseURL = baseURL
    }

    /// Open the SQLite database and run all pending GRDB migrations.
    ///
    /// Enables WAL journal mode, foreign-key enforcement, and NORMAL synchronous
    /// writes for a good balance of durability and performance.
    ///
    /// - Returns: `true` if the database was opened and migrated successfully,
    ///   `false` otherwise (error is logged).
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

            // Checkpoint and truncate the WAL from any previous run before we start.
            // On a fresh server start there are no active readers, so TRUNCATE is safe.
            // This prevents accumulated stale FTS5 shadow-table writes in the WAL from
            // causing SQLITE_IOERR on the first write transaction after a crash.
            try dbQueue.write { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }

            Logger.info("Database opened at \(baseURL.path)")
            return true
        } catch {
            Logger.error("Cannot open database: \(error)")
            return false
        }
    }

    public var snapshotURL: URL {
        baseURL.appendingPathExtension("bak")
    }

    public func createSnapshot(at destinationURL: URL? = nil) throws {
        let destinationURL = destinationURL ?? snapshotURL
        let directoryURL = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let tmpURL = destinationURL.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.removeItem(at: destinationURL)

        let destination = try DatabaseQueue(path: tmpURL.path)
        try dbQueue.backup(to: destination)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tmpURL, to: destinationURL)
    }
}
