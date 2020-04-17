//
//  UserInfo.swift
//  Wired 3
//
//  Created by Rafael Warnault on 20/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation


public class UserInfo {
    public var userID: UInt32!
    public var idle: Bool!
    
    public var nick: String!
    public var status: String!
    public var icon: Data!
    public var color: UInt32!
    
    private var message: P7Message!
    
    public init(message: P7Message) {
        self.message = message
        
        self.update(withMessage: message)
    }
    
    public func update(withMessage message: P7Message) {
        if let v = message.uint32(forField: "wired.user.id") {
            self.userID = v
        }
        
        if let v = message.bool(forField: "wired.user.idle") {
            self.idle = v
        }
        
        if let v = message.string(forField: "wired.user.nick") {
            self.nick = v
        }
        
        if let v = message.string(forField: "wired.user.status") {
            self.status = v
        }
        
        if let v = message.data(forField: "wired.user.icon") {
            self.icon = v
        }
        
        if let v = message.enumeration(forField: "wired.account.color") {
            self.color = v
        }
    }
}
