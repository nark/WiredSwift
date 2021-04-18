//
//  Privilege.swift
//  Server
//
//  Created by Rafael Warnault on 25/03/2021.
//

import Foundation
import Fluent
import FluentSQLiteDriver

public class UserPrivilege: Model {
    public static var schema: String = "user_privileges"
    
    @ID(key: .id)
    public var id:UUID?
    
    @Field(key: "name")
    public var name:String?
    
    @Field(key: "value")
    public var value:Bool?
    
    @Parent(key: "user_id")
    public var user: User

    public required init() { }
    
    public init(name: String, value: Bool) {
        self.name = name
        self.value = value
    }
    
    public init(name: String, value: Bool, user:User) {
        self.name       = name
        self.value      = value
        self.$user.id   = user.id!
    }
}
