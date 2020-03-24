//
//  UsersViewController.swift
//  Wired 3
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa

class UsersViewController: ConnectionViewController, ConnectionDelegate, NSTableViewDelegate, NSTableViewDataSource {
    @IBOutlet weak var usersTableView: NSTableView!
    
    private var usersController:UsersController?

    
    // MARK: - View Controller
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(userLeftPublicChat(_:)),
            name: NSNotification.Name("UserLeftPublicChat"), object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector:#selector(linkConnectionDidClose(notification:)) ,
            name: .linkConnectionDidClose, object: nil)
        
        self.usersTableView.target = self
        self.usersTableView.doubleAction = #selector(tableDoubleClick(_:))
    }
    
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? Connection {
                self.connection = c
                self.usersController = ConnectionsController.shared.usersController(forConnection: self.connection)
                
                c.delegates.append(self)
                
                _ = self.connection.joinChat(chatID: 1)
            }
        }
    }
    
    
    
    
    // MARK: - Notification
    
    @objc func tableDoubleClick(_ sender: Any) {
        if self.usersTableView.selectedRow != -1 {
            if let selectedUser = self.usersController?.user(at: self.usersTableView.selectedRow) {
                _ = ConversationsController.shared.openConversation(onConnection: self.connection, withUser: selectedUser)
            }
        }
    }
    
    
    @objc func userLeftPublicChat(_ n:Notification) {
        if let c = n.object as? Connection, self.connection == c {
            self.usersTableView.reloadData()
        }
    }
    
    
    
    @objc private func linkConnectionDidClose(notification: Notification) -> Void {
        if let c = notification.object as? Connection, c == self.connection {
            self.usersController?.removeAllUsers()
            self.usersTableView.reloadData()
        }
    }
    
    
    // MARK: - connection Delegate
    
    
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
        
            self.usersController!.userJoin(message: message)
            self.usersTableView.reloadData()
        }
        else if  message.name == "wired.chat.user_status" {
            self.usersController!.updateStatus(message: message)
            self.usersTableView.reloadData()
        }
        else if  message.name == "wired.chat.user_icon" {
            self.usersController!.updateStatus(message: message)
            self.usersTableView.reloadData()
        }
        else if message.name == "wired.chat.user_leave" {
            // self.usersController!.userLeave(message: message)
            // self.usersTableView.reloadData()
        }
        else if message.name == "wired.account.privileges" {

        }
        else if message.name == "wired.chat.user_list.done" {
            self.usersTableView.reloadData()
        }
    }
    
    
    
    // MARK: - Table View
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.usersController?.numberOfUsers() ?? 0
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: UserCellView?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "UserCell"), owner: self) as? UserCellView
        
        if let uc = self.usersController, let user = uc.user(at: row) {
            view?.userNick?.stringValue = user.nick
            view?.userStatus?.stringValue = user.status
            
            if let base64ImageString = user.icon?.base64EncodedData() {
                if let data = Data(base64Encoded: base64ImageString, options: .ignoreUnknownCharacters) {
                    view?.userIcon?.image = NSImage(data: data)
                }
            }
                        
            if user.idle == true {
                view?.alphaValue = 0.5
            } else {
                view?.alphaValue = 1.0
            }
        }

        return view
    }
}
