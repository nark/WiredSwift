//
//  Privilege.swift
//  Server
//
//  Created by Rafael Warnault on 25/03/2021.
//

import Foundation
import GRDB

class UserPrivilege: Privilege {
    /// The table name
    public override class var databaseTableName: String { "user_privileges" }
    
    static let user = belongsTo(User.self)
    var user: QueryInterfaceRequest<User> {
        request(for: UserPrivilege.user)
    }
    
    public init(name: String, value: Bool, user:User) {
        super.init(name: name, value: value)
        
        self.user_id = user.id
    }
    
    public required init(row: Row) {
        super.init(row: row)
        
        self.user_id = row[Columns.user_id]
    }
    
    /// The values persisted in the database
    public override func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.value] = value
        container[Columns.user_id] = user_id
    }
}
