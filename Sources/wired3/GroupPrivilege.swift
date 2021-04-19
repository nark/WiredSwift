//
//  GroupPrivilege.swift
//  wired3
//
//  Created by Rafael Warnault on 25/03/2021.
//

import Foundation
import Fluent
import FluentSQLiteDriver

public class GroupPrivilege: Model {
    public static var schema: String = "group_privileges"
    
    @ID(key: .id)
    public var id:UUID?
    
    @Field(key: "name")
    public var name:String?
    
    @Field(key: "value")
    public var value:Bool?
    
    @Parent(key: "group_id")
    var group: Group

    public required init() { }
    
    public init(name: String, value: Bool) {
        self.name = name
        self.value = value
    }
    
    public init(name: String, value: Bool, group:Group) {
        self.name       = name
        self.value      = value
        self.$group.id  = group.id!
    }
}
