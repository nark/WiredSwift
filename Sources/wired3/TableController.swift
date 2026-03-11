//
//  TableController.swift
//  wired3
//
//  Created by Rafael Warnault on 26/03/2021.
//

import Foundation

public class TableController {
    public var databaseController: DatabaseController

    public init(databaseController: DatabaseController) {
        self.databaseController = databaseController
    }
}
