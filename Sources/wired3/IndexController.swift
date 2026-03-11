//
//  IndexController.swift
//  wired3
//
//  Created by Rafael Warnault on 26/03/2021.
//

import Foundation
import WiredSwift
import GRDB

class IndexController: TableController {
    let filesController: FilesController

    public var totalFilesSize: UInt64         = 0
    public var totalFilesCount: UInt64        = 0
    public var totalDisrectoriesCount: UInt64 = 0
    public var lock: Lock                     = Lock()

    public init(databaseController: DatabaseController, filesController: FilesController) {
        self.filesController = filesController
        super.init(databaseController: databaseController)
    }


    // MARK: -
    public func indexFiles() {
        DispatchQueue.global(qos: .default).async {
            do {
                // Vider l'index
                try self.databaseController.dbQueue.write { db in
                    try WiredIndex.deleteAll(db)
                }

                let url = URL(fileURLWithPath: self.filesController.rootPath)
                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let fileURL as URL in enumerator {
                        self.indexPath(path: fileURL.path)
                    }
                }
            } catch {
                WiredSwift.Logger.error("Cannot index files \(error)")
            }
        }
    }

    public func addIndex(forPath realPath: String) {
        indexPath(path: realPath)
    }

    public func removeIndex(forPath realPath: String) {
        var isDir: ObjCBool = false
        do {
            if let _ = try databaseController.dbQueue.read({ db in
                try WiredIndex.filter(Column("real_path") == realPath).fetchOne(db)
            }) {
                let fileExist = FileManager.default.fileExists(atPath: realPath, isDirectory: &isDir)
                self.lock.exclusivelyWrite {
                    self.totalFilesSize -= WiredSwift.File.size(path: realPath)
                    if isDir.boolValue {
                        self.totalDisrectoriesCount -= 1
                    } else if fileExist {
                        self.totalFilesCount -= 1
                    }
                }
                try databaseController.dbQueue.write { db in
                    try WiredIndex.filter(Column("real_path") == realPath).deleteAll(db)
                }
            }
        } catch {
            WiredSwift.Logger.error("Cannot remove index for file at \(realPath): \(error)")
        }
    }

    public func search(string: String, user: User, message: P7Message) {
        // TODO: implement
    }


    // MARK: -
    private func indexPath(path: String) {
        let filename    = path.lastPathComponent
        let virtualPath = filesController.virtual(path: path)
        var isDir: ObjCBool = false

        do {
            var entry = WiredIndex(name: filename,
                                   virtual_path: virtualPath,
                                   real_path: path,
                                   alias: false)
            try databaseController.dbQueue.write { db in try entry.insert(db) }

            let fileExist = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            self.lock.exclusivelyWrite {
                self.totalFilesSize += WiredSwift.File.size(path: path)
                if isDir.boolValue {
                    self.totalDisrectoriesCount += 1
                } else if fileExist {
                    self.totalFilesCount += 1
                }
            }
        } catch {
            WiredSwift.Logger.error("Cannot index file at \(path): \(error)")
        }
    }
}
