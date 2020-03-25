//
//  Url.swift
//  Wired 3
//
//  Created by Rafael Warnault on 18/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation

public class Url: NSObject {
    public var base: String     = ""
    public var scheme: String   = Wired.wiredScheme
    public var login: String    = "guest"
    public var password: String = ""
    public var hostname: String = ""
    public var port: Int        = Wired.wiredPort
    
    
    public init(withString baseString: String) {
        super.init()
        
        self.base = baseString
        
        self.decompose()
    }
    
    
    public func urlString() -> String {
        return "wired://\(self.hostname):\(self.port)"
    }
    
    
    private func decompose() {
        if let u = URL(string: self.base) {
            self.hostname   = u.host!
            self.port       = u.port ?? Wired.wiredPort
            self.login      = u.user ?? "guest"
            self.password   = u.password ?? ""
            self.scheme     = u.scheme!
        } else {
            Logger.error("ERROR: Invalid URL")
        }
    }
}
