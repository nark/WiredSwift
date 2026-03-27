//
//  TableController.swift
//  wired3
//
//  Created by Rafael Warnault on 26/03/2021.
//

import Foundation

/// Base class for all GRDB-backed server controllers.
///
/// Provides a shared reference to `DatabaseController` so that subclasses
/// (`UsersController`, `ChatsController`, `IndexController`, …) can access
/// the database queue without holding a separate reference.
public class TableController {
    /// The shared database controller used by this controller.
    public var databaseController: DatabaseController

    /// Creates a new `TableController` backed by `databaseController`.
    ///
    /// - Parameter databaseController: The shared database controller.
    public init(databaseController: DatabaseController) {
        self.databaseController = databaseController
    }
}
