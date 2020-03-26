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
    @IBOutlet weak var serverNameLabel: NSTextField!
    @IBOutlet weak var serverDescriptionLabel: NSTextField!
    @IBOutlet weak var uptimeLabel: NSTextField!
    @IBOutlet weak var urlLabel: NSTextField!
    @IBOutlet weak var filesLabel: NSTextField!
    @IBOutlet weak var sizeLabel: NSTextField!
    @IBOutlet weak var versionLabel: NSTextField!
    @IBOutlet weak var protocolLabel: NSTextField!
    @IBOutlet weak var cipherLabel: NSTextField!
    @IBOutlet weak var compressionLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? ServerConnection {
                self.connection = c
                                
                c.delegates.append(self)
                
                self.updateView()
            }
        }
    }
    
    
    private func updateView() {
        if self.connection != nil {
            self.serverNameLabel.stringValue = self.connection.serverInfo.serverName
            self.serverDescriptionLabel.stringValue = self.connection.serverInfo.serverDescription
            self.versionLabel.stringValue = "\(self.connection.serverInfo.applicationName!) \(self.connection.serverInfo.applicationVersion!) on \(self.connection.serverInfo.osName!) \(self.connection.serverInfo.osVersion!) (\(self.connection.serverInfo.arch!))"
            
            self.protocolLabel.stringValue = "\(self.connection.socket.remoteName!) \(self.connection.socket.remoteVersion!)"
            self.cipherLabel.stringValue = "\(P7Socket.CipherType.pretty(self.connection.socket.cipherType))"
            self.urlLabel.stringValue = "wiredp7://\(self.connection.url.hostname):\(self.connection.url.port)"
            self.compressionLabel.stringValue = "Unsupported (yet)"
            
            let image = NSImage(data: self.connection.serverInfo.serverBanner)
            self.bannerImage.image = image
            
            if let string = AppDelegate.timeIntervalFormatter.string(from: Date().timeIntervalSince(self.connection.serverInfo.startTime)) {
                self.uptimeLabel.stringValue = string
            }
            
            self.filesLabel.stringValue = "\(self.connection.serverInfo!.filesCount!)"
            self.sizeLabel.stringValue = AppDelegate.byteCountFormatter.string(fromByteCount: Int64(self.connection.serverInfo.filesSize))
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

