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
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if  message.name == "wired.chat.user_list" ||
            message.name == "wired.chat.user_join"  {
            let userInfo = UserInfo(message: message)
            
            self.users.append(userInfo)
            
            self.usersTableView.reloadData()
        }
        else if  message.name == "wired.chat.user_status" {
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }
            
            if let user = self.user(forID: userID) {
                user.update(withMessage: message)
                
                self.usersTableView.reloadData()
            }
        }
        else if message.name == "wired.chat.user_leave" {
            if let userID = message.uint32(forField: "wired.user.id") {
                if let index = users.index(where: {$0.userID == userID}) {
                    users.remove(at: index)
                    self.usersTableView.reloadData()
                }
            }
        }
        else if message.name == "wired.account.privileges" {

        }
        else if message.name == "wired.chat.user_list.done" {
            self.usersTableView.reloadData()
        }
    }
    
    
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return users.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: UserCellView?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "UserCell"), owner: self) as? UserCellView
        
        view?.userNick?.stringValue = self.users[row].nick
        view?.userStatus?.stringValue = self.users[row].status
        
        if let base64ImageString = self.users[row].icon?.base64EncodedData() {
            if let data = Data(base64Encoded: base64ImageString, options: .ignoreUnknownCharacters) {
                view?.userIcon?.image = NSImage(data: data)
            }
        }
        
        if self.users[row].idle == true {
            view?.alphaValue = 0.5
        } else {
            view?.alphaValue = 1.0
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
