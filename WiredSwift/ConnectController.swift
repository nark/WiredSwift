//
//  ViewController.swift
//  Wired 3
//
//  Created by Rafael Warnault on 15/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa
import Wired

class ConnectController: ConnectionController, ConnectionDelegate {
    @IBOutlet weak var addressField: NSTextField!
    @IBOutlet weak var loginField: NSTextField!
    @IBOutlet weak var passwordField: NSSecureTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    
    @IBAction func connect(_ sender: Any) {
        if addressField.stringValue.count   == 0 ||
           loginField.stringValue.count     == 0 {
            return
        }
        
        let url         = Url(withString: "wired://\(addressField.stringValue)")
        url.login       = loginField.stringValue
        url.password    = passwordField.stringValue
        
        self.connection = Connection(withSpec: spec, delegate: self)
        
        if self.connection.connect(withUrl: url) {
            self.performSegue(withIdentifier: "showPublicChat", sender: sender)
        }
    }
    
    
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "showPublicChat" {
            if let windowController = segue.destinationController as? NSWindowController {
                if let serverName = self.connection.serverInfo?.serverName {
                    windowController.window?.title = serverName
                }
                
                if let splitViewController = windowController.contentViewController as? NSSplitViewController {
                    if let userController = splitViewController.splitViewItems[1].viewController as? UserController {
                        userController.representedObject = self.connection
                    }

                    if let chatController = splitViewController.splitViewItems[0].viewController as? ChatController {
                        chatController.representedObject = self.connection
                    }
                    
                    self.view.window!.performClose(nil)
                }
            }
        }
    }
    
    func connectionDidConnect(connection: Connection) {
        // print("connectionDidConnect")
    }
    
    func connectionDidFailToConnect(connection: Connection, error: Error) {
        // print("connectionDidFailToConnect")
    }
    
    func connectionDisconnected(connection: Connection, error: Error?) {
        // print("connectionDisconnected")
    }
    
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        // print("connectionDidReceiveMessage")
    }
}

