//
//  ViewController.swift
//  Wired 3
//
//  Created by Rafael Warnault on 15/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa



class ConnectController: ConnectionViewController, ConnectionDelegate {
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var addressField: NSTextField!
    @IBOutlet weak var loginField: NSTextField!
    @IBOutlet weak var passwordField: NSSecureTextField!
    @IBOutlet weak var connectButton: NSButton!
    
    public var connectionWindowController:ConnectionWindowController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
//
//    public func connect(withBookmark bookmark: Bookmark) {
//        let url = bookmark.url()
//
//        addressField.stringValue = "\(url.hostname):\(url.port)"
//        loginField.stringValue = url.login
//        passwordField.stringValue = url.password
//
//        self.connection = ServerConnection(withSpec: spec, delegate: self)
//        self.connection.nick = UserDefaults.standard.string(forKey: "WSUserNick") ?? self.connection.nick
//        self.connection.status = UserDefaults.standard.string(forKey: "WSUserStatus") ?? self.connection.status
//
//        self.progressIndicator.startAnimation(self)
//
//        DispatchQueue.global().async {
//            if self.connection.connect(withUrl: url) == true {
//                DispatchQueue.main.async {
//                    ConnectionsController.shared.addConnection(self.connection)
//
//                    self.progressIndicator.stopAnimation(self)
//                    self.performSegue(withIdentifier: "showPublicChat", sender: self)
//                }
//            } else {
//                DispatchQueue.main.async {
//                    if let wiredError = self.connection.socket.errors.first {
//                        AppDelegate.showWiredError(wiredError)
//                    }
//                }
//            }
//        }
//    }
//
    
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
        
        self.connection = ServerConnection(withSpec: spec, delegate: self)
        self.connection.nick = UserDefaults.standard.string(forKey: "WSUserNick") ?? self.connection.nick
        self.connection.status = UserDefaults.standard.string(forKey: "WSUserStatus") ?? self.connection.status
        
        if let b64string = AppDelegate.currentIcon?.tiffRepresentation(using: NSBitmapImageRep.TIFFCompression.none, factor: 0)?.base64EncodedString() {
            self.connection.icon = b64string
        }
            
        self.progressIndicator.startAnimation(sender)
        connectButton.isEnabled = false
                
        DispatchQueue.global().async {
            if self.connection.connect(withUrl: url) {
                DispatchQueue.main.async {
                    self.connection.connectionWindowController = self.connectionWindowController
                    ConnectionsController.shared.addConnection(self.connection)
                    
                    self.progressIndicator.stopAnimation(sender)
                    
                    self.view.window?.orderOut(sender)
                    self.connectionWindowController.window?.endSheet(self.view.window!, returnCode: NSApplication.ModalResponse.OK)
                    
                    // distribute connection to sub components
                    self.connectionWindowController.attach(connection: self.connection)
                }
            } else {
                DispatchQueue.main.async {
                    if let wiredError = self.connection.socket.errors.first {
                        AppDelegate.showWiredError(wiredError)
                    }
                    
                    self.connectButton.isEnabled = true
                    self.progressIndicator.stopAnimation(self)
                }
            }
        }
    }
    
    
    @IBAction func cancel(_ sender: Any) {
        self.view.window?.orderOut(sender)
        
        self.connectionWindowController.window?.endSheet(self.view.window!, returnCode: NSApplication.ModalResponse.cancel)
    }
    
    
    
    func connectionDidConnect(connection: Connection) {
        // print("connectionDidConnect")
    }
    
    func connectionDidFailToConnect(connection: Connection, error: Error) {
        // print("connectionDidFailToConnect")
    }
    
    func connectionDisconnected(connection: Connection, error: Error?) {
        // print("connectionDisconnected")
        //ConnectionsController.shared.removeConnection(connection as! ServerConnection)
    }
    
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        // print("connectionDidReceiveMessage")
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        // print("connectionDidReceiveError")
    }

}

