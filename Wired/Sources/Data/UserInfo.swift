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

    private var message: P7Message!
    
    public init(message: P7Message) {
        self.message = message
        
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
    }
}
