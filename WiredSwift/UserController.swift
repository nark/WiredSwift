//
//  UserController.swift
//  Wired 3
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa

class UserController: ConnectionController, ConnectionDelegate, NSTableViewDelegate, NSTableViewDataSource {
    @IBOutlet weak var usersTableView: NSTableView!
    
    private var users:[UserInfo] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    
    override func viewDidAppear() {
        
    }
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? Connection {
                self.connection = c
                
                c.delegates.append(self)
                
                _ = self.connection.joinChat(chatID: 1)
            }
        }
    }
    
    
    
    func connectionDidConnect(connection: Connection) {
        
    }
    
    func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    func connectionDisconnected(connection: Connection, error: Error?) {
        
    }
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if  message.name == "wired.chat.user_list" ||
            message.name == "wired.chat.user_join"  {
            let userInfo = UserInfo(message: message)
            
            self.users.append(userInfo)
        }
        else if message.name == "wired.chat.user_leave" {
            if let userID = message.uint32(forField: "wired.user.id") {
                if let index = users.index(where: {$0.userID == userID}) {
                    users.remove(at: index)
                    self.usersTableView.reloadData()
                }
            }
        }
        else if message.name == "wired.chat.user_list.done" {
            self.usersTableView.reloadData()
        }
    }
    
    
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return users.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: NSTableCellView?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "UserCell"), owner: self) as? NSTableCellView
        
        view?.textField?.stringValue = self.users[row].nick
        
        if let base64ImageString = self.users[row].icon?.base64EncodedData() {
            if let data = Data(base64Encoded: base64ImageString, options: .ignoreUnknownCharacters) {
                view?.imageView?.image = NSImage(data: data)
            }
        }

        return view
    }
    
    
    private func user(forID uid: UInt32) -> UserInfo? {
        for u in users {
            if u.userID == uid {
                return u
            }
        }
        return nil
    }
}
