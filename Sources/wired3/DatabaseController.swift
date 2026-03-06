//
//  DatabaseController.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import Fluent
import FluentSQLiteDriver
#if os(Linux)
import CSQLite
#else
import SQLite3
#endif

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public protocol DatabaseControllerDelegate {
    func createTables()
}

public class DatabaseController {
    var delegate:DatabaseControllerDelegate?
    
    // MARK: -
    var threadPool: NIOThreadPool!
    var eventLoopGroup: EventLoopGroup!
    var dbs: Databases!
    var pool: Database!
    
    let baseURL: URL
    let spec:P7Spec
    
    
    // MARK: - Initialization
    public init?(baseURL: URL, spec: P7Spec) {
        self.baseURL = baseURL
        self.spec = spec
    }
    
    
    
    // MARK: - Private
    public func initDatabase() -> Bool {
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 5)
        threadPool = .init(numberOfThreads: 5)
        threadPool.start()
        
        let exists = FileManager.default.fileExists(atPath: baseURL.path)
        
        dbs = Databases(threadPool: threadPool, on: eventLoopGroup)
        dbs.use(.sqlite(.file(self.baseURL.path)), as: .sqlite)
        
        if let p = dbs.database(logger: .init(label: "fr.read-write.wired3"), on: dbs.eventLoopGroup.next()) {
            self.pool = p
        }

        let shouldBootstrap = !exists || !databaseHasCoreTables(path: baseURL.path)
        if shouldBootstrap {
            if let d = self.delegate {
                d.createTables()
            }
        }
        
        return true
    }

    private func databaseHasCoreTables(path: String) -> Bool {
        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let db else {
            sqlite3_close(db)
            return false
        }
        defer { sqlite3_close(db) }

        let requiredTables = ["users", "groups", "chats", "index"]
        for tableName in requiredTables {
            var statement: OpaquePointer?
            let query = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;"

            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else {
                sqlite3_finalize(statement)
                return false
            }

            sqlite3_bind_text(statement, 1, tableName, -1, SQLITE_TRANSIENT)
            let step = sqlite3_step(statement)
            sqlite3_finalize(statement)

            if step != SQLITE_ROW {
                return false
            }
        }

        return true
    }
}
