//
//  ConnectionsController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let didAddNewConnection = Notification.Name("didAddNewConnection")
    static let didRemoveConnection = Notification.Name("didRemoveConnection")
}

class ConnectionsController {
    public static let shared = ConnectionsController()
    
    var connections:[Connection] = []
    
    private init() {

    }
    
    
    public func addConnection(_ connection: Connection) {
        if connections.index(of: connection) == nil {
            connections.append(connection)
            
            NotificationCenter.default.post(name: .didAddNewConnection, object: connection, userInfo: nil)
        }
    }
    
    
    public func removeConnection(_ connection: Connection) {
        if let i = connections.index(of: connection) {
            connections.remove(at: i)
            
            NotificationCenter.default.post(name: .didRemoveConnection, object: connection, userInfo: nil)
        }
    }
}
