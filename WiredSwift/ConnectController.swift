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
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var addressField: NSTextField!
    @IBOutlet weak var loginField: NSTextField!
    @IBOutlet weak var passwordField: NSSecureTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    
    public func connect(withBookmark bookmark: Bookmark) {
        let url = bookmark.url()
        
        addressField.stringValue = "\(url.hostname):\(url.port)"
        loginField.stringValue = url.login
        passwordField.stringValue = url.password
        
        self.connection = Connection(withSpec: spec, delegate: self)
        self.connection.nick = UserDefaults.standard.string(forKey: "WSUserNick") ?? self.connection.nick
        self.connection.status = UserDefaults.standard.string(forKey: "WSUserStatus") ?? self.connection.status
        
        self.progressIndicator.startAnimation(self)
                
        DispatchQueue.global().async {
            if self.connection.connect(withUrl: url) {
                DispatchQueue.main.async {
                    ConnectionsController.shared.addConnection(self.connection)
                    
                    self.progressIndicator.stopAnimation(self)
                    self.performSegue(withIdentifier: "showPublicChat", sender: self)
                }
            }
        }
    }
    
    
    @IBAction func connect(_ sender: Any) {
        if addressField.stringValue.count == 0 {
            return
        }
        
        let url = Url(withString: "wired://\(addressField.stringValue)")
        
        if loginField.stringValue.count == 0 {
            // force guest login by default
            url.login = "guest"
        } else {
            url.login = loginField.stringValue
        }
        
        url.password = passwordField.stringValue
        
        self.connection = Connection(withSpec: spec, delegate: self)
        self.connection.nick = UserDefaults.standard.string(forKey: "WSUserNick") ?? self.connection.nick
        self.connection.status = UserDefaults.standard.string(forKey: "WSUserStatus") ?? self.connection.status
        
        self.progressIndicator.startAnimation(sender)
                
        DispatchQueue.global().async {
            if self.connection.connect(withUrl: url) {
                DispatchQueue.main.async {
                    ConnectionsController.shared.addConnection(self.connection)
                    
                    self.progressIndicator.stopAnimation(sender)
                    self.performSegue(withIdentifier: "showPublicChat", sender: sender)
                }
            }
        }
    }
    
    
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "showPublicChat" {
            if let connectionWindowController = segue.destinationController as? ConnectionWindowController {
                connectionWindowController.connection = self.connection
                
                if let splitViewController = connectionWindowController.contentViewController as? NSSplitViewController {
                    if let resourcesController = splitViewController.splitViewItems[0].viewController as? ResourcesController {
                          resourcesController.representedObject = self.connection
                    }
                      
                    if let splitViewController2 = splitViewController.splitViewItems[1].viewController as? NSSplitViewController {
                        if let userController = splitViewController2.splitViewItems[1].viewController as? UserController {
                            userController.representedObject = self.connection
                        }

                        if let chatController = splitViewController2.splitViewItems[0].viewController as? ChatController {
                            chatController.representedObject = self.connection
                        }
                        
                        connectionWindowController.window?.title = self.connection.serverInfo.serverName

                        self.view.window!.performClose(nil)
                        connectionWindowController.window?.mergeAllWindows(self)
                    }
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
        ConnectionsController.shared.removeConnection(connection)
    }
    
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        // print("connectionDidReceiveMessage")
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        // print("connectionDidReceiveError")
    }
}

