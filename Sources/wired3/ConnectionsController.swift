//
//  ConnectionsController.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift

class UsersController {
    var connectedUsers:[UInt32:User] = [:]
    var lastUserID:UInt32 = 0
    
    public func nextUserID() -> UInt32 {
        self.lastUserID += 1
        
        return self.lastUserID
    }
    
    
    public func addUser(user:User) {
        self.connectedUsers[user.userID] = user
        
        WiredSwift.Logger.info("Connected users: \(self.connectedUsers)")
    }
    
    
}

