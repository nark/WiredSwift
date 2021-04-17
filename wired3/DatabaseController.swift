//
//  DatabaseController.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import GRDB

public protocol DatabaseControllerDelegate {
    func createTables()
}

public class DatabaseController {
    var delegate:DatabaseControllerDelegate?
    
    // MARK: -
    var pool:DatabasePool!
    let baseURL: URL
    let spec:P7Spec
    
    
    // MARK: - Initialization
    public init?(baseURL: URL, spec: P7Spec) {
        self.baseURL = baseURL
        self.spec = spec
    }
    
    
    
    // MARK: - Private
    public func initDatabase() -> Bool {
        let exixts = FileManager.default.fileExists(atPath: baseURL.path)
        
        do {
            self.pool = try DatabasePool(path: baseURL.path)
        } catch {
            Logger.error("Cannot open database file \(error)")
            return false
        }
                        
        if !exixts {
            if let d = self.delegate {
                d.createTables()
            }
        }
        
        return true
    }
}
