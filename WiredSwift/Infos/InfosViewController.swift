//
//  InfoViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class InfosViewController: ConnectionViewController, ConnectionDelegate {
    
    @IBOutlet weak var bannerImage: NSImageView!
    @IBOutlet weak var serverName: NSTextField!

    @IBOutlet weak var protocolLabel: NSTextField!
    @IBOutlet weak var cipherLabel: NSTextField!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? Connection {
                self.connection = c
                                
                c.delegates.append(self)
                
                self.updateView()
            }
        }
    }
    
    
    private func updateView() {
        if self.connection != nil {
            self.serverName.stringValue = self.connection.serverInfo.serverName
            
            self.protocolLabel.stringValue = "\(self.connection.serverInfo.applicationName!) \(self.connection.serverInfo.applicationVersion!)"
            self.cipherLabel.stringValue = "\(P7Socket.CipherType.pretty(self.connection.socket.cipherType))"
            
            let image = NSImage(data: self.connection.serverInfo.serverBanner)
            self.bannerImage.image = image
        }
    }
    
    
    
    // MARK: Connection Delegate -
    
    func connectionDidConnect(connection: Connection) {
        
    }
    
    func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    func connectionDisconnected(connection: Connection, error: Error?) {
        
    }
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
}

