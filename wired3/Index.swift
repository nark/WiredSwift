//
//  FileIndex.swift
//  Server
//
//  Created by Rafael Warnault on 26/03/2021.
//

import Foundation
import GRDB

class Index: Record {
    public var id:Int64?
    public var name:String?
    public var virtual_path:String?
    public var real_path:String?
    public var alias:Bool?
    
    
    public init(name: String, virtual_path: String, real_path: String, alias: Bool) {
        self.name           = name
        self.virtual_path   = virtual_path
        self.real_path      = real_path
        self.alias          = alias
        
        super.init()
    }
    
    required init(row: Row) {
        self.id             = row[Columns.id]
        self.name           = row[Columns.name]
        self.virtual_path   = row[Columns.virtual_path]
        self.real_path      = row[Columns.real_path]
        self.alias          = row[Columns.alias]
        
        super.init(row: row)
    }
    
    /// The table name
    public override class var databaseTableName: String { "index" }

    /// The table columns
    enum Columns: String, ColumnExpression {
        case id, name, virtual_path, real_path, alias
    }

    /// The values persisted in the database
    public override func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.virtual_path] = virtual_path
        container[Columns.real_path] = real_path
        container[Columns.alias] = alias
    }

    // Update auto-incremented id upon successful insertion
    public override func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }
}
