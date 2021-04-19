//
//  Group.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import Fluent
import FluentSQLiteDriver


public class Group: Model {
    public static var schema: String = "groups"
    
    @ID(key: .id)
    public var id:UUID?
    
    @Field(key: "groupID")
    public var groupID:UInt32!
    
    @Field(key: "name")
    public var name:String?

    @Children(for: \.$group)
    public var privileges: [GroupPrivilege]
    
    public required init() { }
    
    public init(name: String) {
        self.name = name
    }
}
