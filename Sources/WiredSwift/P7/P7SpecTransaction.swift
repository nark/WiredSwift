//
//  P7SpecTransaction.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 13/05/2021.
//

import Foundation

public class P7SpecTransaction: P7SpecItem {    
    public override init(name: String, spec: P7Spec, attributes: [String : Any]) {
        super.init(name: name, spec: spec, attributes: attributes)
    }
}
