//
//  IndexController.swift
//  Server
//
//  Created by Rafael Warnault on 26/03/2021.
//

import Foundation
import WiredSwift
import Fluent
import FluentSQLiteDriver

class IndexController: TableController {
    let filesController:FilesController
    
    public var totalFilesSize:UInt64            = 0
    public var totalFilesCount:UInt64           = 0
    public var totalDisrectoriesCount:UInt64    = 0
    
    public init(databaseController: DatabaseController, filesController: FilesController) {
        self.filesController = filesController
        
        super.init(databaseController: databaseController)
    }
    
    
    // MARK: -
    public func indexFiles() {
//        DispatchQueue.global(qos: .default).async {
//            do {
//                try self.databaseController.pool.write { db in
//                    // we clean the index first
//                    try db.execute(sql: "DELETE FROM `index`")
//
//                    let url = URL.init(fileURLWithPath: self.filesController.rootPath)
//
//                    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
//                        for case let fileURL as URL in enumerator {
//                            self.indexPath(path: fileURL.path, db: db)
//                        }
//                    }
//                }
//            } catch let error {
//                Logger.error("\(error)")
//            }
//        }
    }
    
    
    
    public func add(path: String) {
//        do {
//            try self.databaseController.pool.write { db in
//                self.indexPath(path: path, db: db)
//            }
//        } catch let error {
//            Logger.error("Cannot add file at \(path): \(error)")
//        }
    }
    
    
    public func remove(path: String) {
//        do {
//            try self.databaseController.pool.write { db in
//
//            }
//        } catch let error {
//            Logger.error("Cannot remove file at \(path): \(error)")
//        }
    }
    
    
    public func search(string: String, user: User, message: P7Message) {
//        do {
//            try self.databaseController.pool.write { db in
//
//            }
//        } catch let error {
//            Logger.error("Cannot search \(string): \(error)")
//        }
    }
    
    
    
    
    // MARK: -
    private func indexPath(path: String, db:Database) {
//        let filename = path.lastPathComponent
//        let virtualPath = filesController.virtual(path: path)
//        var isDir:ObjCBool = false
//
//        do {
//            try Index(name: filename, virtual_path: virtualPath, real_path: path, alias: false).insert(db)
//
//            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
//
//            self.totalFilesSize += WiredSwift.File.size(path: path)
//
//            if isDir.boolValue {
//                self.totalDisrectoriesCount += 1
//            } else {
//                self.totalFilesCount += 1
//            }
//        } catch let error {
//            Logger.error("Cannot index file \(path)")
//            Logger.error("\(error)")
//        }
    }
    
    
    
    // MARK: -
    public override func createTables() {
//        do {
//            try self.databaseController.pool.write { db in
//                try db.create(table: "index") { t in
//                    t.autoIncrementedPrimaryKey("id")
//                    t.column("name", .text).notNull()
//                    t.column("virtual_path", .text).notNull()
//                    t.column("real_path", .text).notNull()
//                    t.column("alias", .boolean).notNull()
//                }
//            }
//        } catch let error {
//            Logger.error("Cannot create tables")
//            Logger.error("\(error)")
//        }
    }
}
