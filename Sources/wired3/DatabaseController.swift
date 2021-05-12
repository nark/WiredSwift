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
    public init?(baseURL: URL, spec: P7Spec, eventLoopGroup:EventLoopGroup) {
        self.eventLoopGroup = eventLoopGroup
        self.baseURL = baseURL
        self.spec = spec
    }
    
    
    
    // MARK: - Private
    public func initDatabase() -> Bool {
        threadPool = .init(numberOfThreads: 5)
        threadPool.start()
        
        let exixts = FileManager.default.fileExists(atPath: baseURL.path)
        
        dbs = Databases(threadPool: threadPool, on: eventLoopGroup)
        dbs.use(.sqlite(.file(self.baseURL.path)), as: .sqlite)
        
        if let p = dbs.database(logger: .init(label: "fr.read-write.wired3"), on: dbs.eventLoopGroup.next()) {
            self.pool = p
        }
                        
        if !exixts {
            if let d = self.delegate {
                d.createTables()
            }
        }
        
        return true
    }
}
