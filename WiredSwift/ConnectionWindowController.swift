//
//  ConnectionWindowController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class ConnectionWindowController: NSWindowController {
    public var connection: Connection!
    
    override func windowDidLoad() {
        super.windowDidLoad()
    
        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    }
    
    
    override func close() {
        if self.connection != nil {
            ConnectionsController.shared.removeConnection(self.connection)
            self.connection.disconnect()
        }
    
        super.close()
    }

}
