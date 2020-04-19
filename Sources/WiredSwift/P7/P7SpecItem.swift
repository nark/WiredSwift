//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

public class P7SpecItem : NSObject {
    public var spec: P7Spec!
    public var name: String!
    public var id: String!
    public var version: String?
    public var attributes: [String : Any] = [:]
    
    public init(name: String, spec: P7Spec, attributes: [String : Any]) {
        self.spec       = spec
        self.name       = name
        self.id         = attributes["id"] as? String
        self.version    = attributes["version"] as? String
        self.attributes = attributes
    }
    
    public override var description: String {
        return "[\(self.id!)] \(self.name!)"
    }
}
