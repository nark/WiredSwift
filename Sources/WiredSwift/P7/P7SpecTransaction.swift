//
//  P7SpecTransaction.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 13/05/2021.
//

import Foundation



public class AndOrReply: P7SpecItem {
    public enum AndOr {
        case AND
        case OR
    }

    public var andOr:AndOr!
    public var replies:[P7SpecReply] = []
    public var children:[AndOrReply] = []
    
    public init(name: String, spec: P7Spec, attributes: [String : Any], andOr: AndOr) {
        self.andOr = andOr
        
        super.init(name: name, spec: spec, attributes: attributes)
    }
}




public class P7SpecReply: P7SpecItem {
    public var count:Int!
    public var required:Bool!
    
    public override init(name: String, spec: P7Spec, attributes: [String : Any]) {
        self.count      = (attributes["count"] as? String == "*")       ? -1 : Int(attributes["count"] as! String)
        self.required   = (attributes["required"] as? String == "true") ? true : false

        super.init(name: name, spec: spec, attributes: attributes)
    }
}




public class P7SpecTransaction: P7SpecItem {
    public var andOrReplies: [AndOrReply] = []
    public var replies:[P7SpecReply] = []
    
    public var originator:Originator!
    
    public init(name: String, spec: P7Spec, attributes: [String : Any], originator:Originator) {
        self.originator = originator
        
        super.init(name: name, spec: spec, attributes: attributes)
    }

    public override var description: String {
        return "[\(self.name!)]"
    }
    
    public func verify(candidate: P7Message) -> Bool {
        // single replies
        for r in self.replies {
            if r.name == candidate.name {
                return true
            }
        }
        
        for andOr in andOrReplies {
            // OR replies
            for r in andOr.replies {
                if r.name == candidate.name {
                    return true
                }
            }
            
            // AND replies
            for c in andOr.children {
                for r in c.replies {
                    if r.name == candidate.name {
                        return true
                    }
                }
            }
        }
        
        return false
    }
}
