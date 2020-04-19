//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

public class P7SpecField: P7SpecItem {
    public var type: P7SpecType!
    public var required: Bool = false
    
    public override init(name: String, spec: P7Spec, attributes: [String : Any]) {
        super.init(name: name, spec: spec, attributes: attributes)
        
        if let typeName = attributes["type"] as? String {
            self.type = P7SpecType.specType(forString: typeName)
        }
    }
    
    public func hasExplicitLength() -> Bool {
        return type == .string || type == .data || type == .list
    }
}
