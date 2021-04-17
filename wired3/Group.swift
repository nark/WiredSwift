//
//  User.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import GRDB



public class Group: Record {
    public var id:Int64?
    public var name:String?

    static let privileges = hasMany(GroupPrivilege.self)
    var privileges: QueryInterfaceRequest<GroupPrivilege> {
        request(for: Group.privileges)
    }
    
    
    public init(name: String) {
        self.name = name
        
        super.init()
    }
    

    /// Creates a record from a database row
    public required init(row: Row) {
        self.id = row[Columns.id]
        self.name = row[Columns.name]
        
        super.init(row: row)
    }


    /// The table name
    public override class var databaseTableName: String { "groups" }

    /// The table columns
    enum Columns: String, ColumnExpression {
        case id, name
    }

    /// The values persisted in the database
    public override func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.name] = name
    }

    // Update auto-incremented id upon successful insertion
    public override func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }
}
