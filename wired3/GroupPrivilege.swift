//
//  Privilege.swift
//  Server
//
//  Created by Rafael Warnault on 25/03/2021.
//

import Foundation
import GRDB

class GroupPrivilege: Privilege {
    /// The table name
    public override class var databaseTableName: String { "group_privileges" }
    
    static let group = belongsTo(Group.self)
    var group: QueryInterfaceRequest<Group> {
        request(for: GroupPrivilege.group)
    }
    
    public init(name: String, value: Bool, group:Group) {
        super.init(name: name, value: value)

        self.group_id = group.id
    }
    
    public required init(row: Row) {
        super.init(row: row)
        
        self.group_id = row[Columns.group_id]
    }
    
    /// The values persisted in the database
    public override func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.value] = value
        container[Columns.group_id] = group_id
    }
}
