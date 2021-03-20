//
//  ConnectionsController.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift

class ConnectionsController {
    var connectedUsers:[UInt32:User] = [:]
    var lastUserID:UInt32 = 0
    
    func nextUserID() -> UInt32 {
        self.lastUserID += 1
        
        return self.lastUserID
    }
}

