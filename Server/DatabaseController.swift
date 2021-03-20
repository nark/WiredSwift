//
//  DatabaseController.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import GRDB

class DatabaseController {
    // MARK: -
    var pool:DatabasePool!
    let baseURL: URL
    
    
    // MARK: - Initialization
    public init?(baseURL: URL) {
        self.baseURL = baseURL
        
        if !self.initDatabase() {
            return nil
        }
    }
    
    
    
    // MARK: - Public
    public func passwordForUsername(username: String) -> String? {
        var password:String? = nil
        
        do {
            try self.pool.read { db in
                if let row = try Row.fetchOne(db, sql: "SELECT * FROM users WHERE name = ?", arguments: [username]) {
                    password = row["password"]
                }
            }
        } catch {  }
        
        return password
    }
    
    
    
    // MARK: - Private
    private func initDatabase() -> Bool {
        do {
            self.pool = try DatabasePool(path: baseURL.path)
        } catch {
            Logger.error("Cannot open database file")
            return false
        }
        
        self.createTables()
        
        return true
    }

    
    private func createTables() {
        do {
            try self.pool.write { db in
                try db.execute(sql: """
                    CREATE TABLE users (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name TEXT NOT NULL,
                        password TEXT NOT NULL)
                    """)
                
                try db.execute(
                    sql: "INSERT INTO users (name, password) VALUES (?, ?)",
                    arguments: ["guest", "".sha1()])
                
                try db.execute(
                    sql: "INSERT INTO users (name, password) VALUES (?, ?)",
                    arguments: ["admin", "admin".sha1()])
            }
        } catch { }
    }
}
