//
//  Privilege.swift
//  Server
//
//  Created by Rafael Warnault on 25/03/2021.
//

import Foundation
import GRDB

class Privilege: Record {
    public var id:Int64?
    public var name:String?
    public var value:Bool?
    public var user_id:Int64?
    public var group_id:Int64?
    
    public init(name: String, value: Bool) {
        self.name = name
        self.value = value
        
        super.init()
    }
    
    public required init(row: Row) {
        self.id = row[Columns.id]
        self.name = row[Columns.name]
        self.value = row[Columns.value]
        
        super.init(row: row)
    }
    

    /// The table columns
    enum Columns: String, ColumnExpression {
        case id, name, value, user_id, group_id
    }

    /// The values persisted in the database
    public override func encode(to container: inout PersistenceContainer) {

    }

    // Update auto-incremented id upon successful insertion
    public override func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }
}
