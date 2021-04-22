//
//  Index.swift
//  wired3
//
//  Created by Rafael Warnault on 26/03/2021.
//

import Foundation
import Fluent
import FluentSQLiteDriver

class Index: Model {
    public static var schema: String = "index"
    
    @ID(key: .id)
    public var id:UUID?
    
    @Field(key: "name")
    public var name:String?
    
    @Field(key: "virtual_path")
    public var virtual_path:String?
    
    @Field(key: "real_path")
    public var real_path:String?
    
    @Field(key: "alias")
    public var alias:Bool?
    
    public required init() { }
    
    public init(name: String, virtual_path: String, real_path: String, alias: Bool) {
        self.name           = name
        self.virtual_path   = virtual_path
        self.real_path      = real_path
        self.alias          = alias

    }
}
