//
//  TableController.swift
//  wired3
//
//  Created by Rafael Warnault on 26/03/2021.
//

import Foundation

protocol TableControllerDelegate {
    func createTables()
}

public class TableController : TableControllerDelegate {
    public var databaseController:DatabaseController
    
    public init(databaseController:DatabaseController) {
        self.databaseController = databaseController
    }
    
    public func createTables() {
        fatalError("Method `createTables` is not implemented here")
    }
}
