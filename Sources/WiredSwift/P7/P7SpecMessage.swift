//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

public class P7SpecMessage: P7SpecItem {
    public var parameters : [P7SpecField] = []
    
    public override init(name: String, spec: P7Spec, attributes: [String : Any]) {
        super.init(name: name, spec: spec, attributes: attributes)
    }
}
