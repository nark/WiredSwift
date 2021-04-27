//
//  IndexController.swift
//  wired3
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
        DispatchQueue.global(qos: .default).async {
            do {
                // we clean the index first
                try Index.query(on: self.databaseController.pool).delete(force: true).wait()

                let url = URL.init(fileURLWithPath: self.filesController.rootPath)

                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let fileURL as URL in enumerator {
                        self.indexPath(path: fileURL.path, db: self.databaseController.pool)
                    }
                }
            } catch let error {
                WiredSwift.Logger.error("Cannot index files \(error)")
            }
        }
    }
    
    
    
    public func addIndex(forPath realPath: String) {
        self.indexPath(path: realPath, db: self.databaseController.pool)
    }
    
    
    public func removeIndex(forPath realPath: String) {
        var isDir:ObjCBool = false
        
        do {
            if let index = try Index.query(on: self.databaseController.pool)
                                    .filter(\.$real_path == realPath)
                                    .first()
                                    .wait()
            {
                let fileExist = FileManager.default.fileExists(atPath: realPath, isDirectory: &isDir)

                self.totalFilesSize -= WiredSwift.File.size(path: realPath)

                if isDir.boolValue {
                    self.totalDisrectoriesCount -= 1
                } else if fileExist {
                    self.totalFilesCount -= 1
                }
            }
        } catch let error {
            WiredSwift.Logger.error("Cannot remove index for file at \(realPath): \(error)")
        }
    }
    
    
    public func search(string: String, user: User, message: P7Message) {
        // TODO: implement
    }
    
    
    
    
    // MARK: -
    private func indexPath(path: String, db:Database) {
        let filename = path.lastPathComponent
        let virtualPath = filesController.virtual(path: path)
        var isDir:ObjCBool = false

        do {
            try Index(name: filename, virtual_path: virtualPath, real_path: path, alias: false).create(on: db).wait()

            let fileExist = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)

            self.totalFilesSize += WiredSwift.File.size(path: path)

            if isDir.boolValue {
                self.totalDisrectoriesCount += 1
            } else if fileExist {
                self.totalFilesCount += 1
            }
        } catch let error {
            WiredSwift.Logger.error("Cannot index file at \(path): \(error)")
        }
    }
    
    
    
    // MARK: -
    public override func createTables() {
        do {
            try self.databaseController.pool
            .schema("index")
            .id()
            .field("name", .string, .required)
            .field("virtual_path", .string, .required)
            .field("real_path", .string, .required)
            .field("alias", .string, .required)
            .create().wait()

        } catch let error {
            WiredSwift.Logger.error("Cannot create tables \(error)")
        }
    }
}
