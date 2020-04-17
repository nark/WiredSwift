//
//  UsersViewController.swift
//  Wired 3
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa

class UsersViewController: ConnectionViewController, ConnectionDelegate, NSTableViewDelegate, NSTableViewDataSource, NSUserInterfaceValidations {
    @IBOutlet weak var usersTableView: NSTableView!
    
    private var usersController:UsersController?
    var selectedUser:UserInfo!
    
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
        self.usersTableView.doubleAction = #selector(doubleClickAction(_:))
    }
    
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? ServerConnection {
                self.connection = c
                self.usersController = ConnectionsController.shared.usersController(forConnection: self.connection)
                
                c.delegates.append(self)
                
                _ = self.connection.joinChat(chatID: 1)
            }
        }
    }
    
    
    
    
    // MARK: - Notification
    
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
    
    
    
    // MARK: - IBAction
    @IBAction func doubleClickAction(_ sender: Any) {
        self.selectedUser = self.selectedItem()
        
        self.showPrivateMessages(sender)
    }
    
    @IBAction func showPrivateMessages(_ sender: Any) {
        if let selectedUser = self.selectedUser {
            _ = ConversationsController.shared.openConversation(onConnection: self.connection, withUser: selectedUser)
            
            self.selectedUser = nil
        }
    }
    
    @IBAction func getUserInfo(_ sender: Any) {
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: Bundle.main)
        if let userInfoViewController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("UserInfoViewController")) as? UserInfoViewController {
            let popover = NSPopover()
            popover.contentSize = userInfoViewController.view.frame.size
            popover.behavior = .transient
            popover.animates = true
            popover.contentViewController = userInfoViewController
            
            userInfoViewController.connection = self.connection
            userInfoViewController.user = self.selectedUser
            self.selectedUser = nil
            
            popover.show(relativeTo: self.usersTableView.frame, of: self.usersTableView, preferredEdge: .minX)
        }
    }
    
    @IBAction func kickUser(_ sender: Any) {
        print("kickUser")
    }
    
    @IBAction func banUser(_ sender: Any) {
        print("banUser")
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
    
    
    
    
    
    // MARK: NSValidatedUserInterfaceItem
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let user = self.selectedItem() {
            self.selectedUser = user
            
            if item.action == #selector(showPrivateMessages(_:)) {
                return connection.isConnected()
            }
            else if item.action == #selector(getUserInfo(_:)) {
                return connection.isConnected()
            }
            else if item.action == #selector(kickUser(_:)) {
                return connection.isConnected()
            }
            else if item.action == #selector(banUser(_:)) {
                return connection.isConnected()
            }
        }
        return false
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
            view?.userNick?.textColor = NSColor.color(forEnum: user.color)
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
    
    
    
    // MARK: - Privates
    
    private func selectedItem() -> UserInfo? {
        var selectedIndex = usersTableView.clickedRow
                
        if selectedIndex == -1 {
            selectedIndex = usersTableView.selectedRow
        }
        
        if selectedIndex == -1 {
            return nil
        }
                
        return self.usersController?.user(at: selectedIndex)
    }
}
