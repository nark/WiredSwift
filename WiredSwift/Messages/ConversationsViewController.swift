//
//  ConversationsViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 21/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let selectedConversationDidChange = Notification.Name("SelectedConversationDidChange")
}


class ConversationsViewController: ConnectionViewController, ConnectionDelegate, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
    @IBOutlet weak var conversationsTableView: NSTableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self, selector: #selector(shouldSelectConversation(_:)),
            name: NSNotification.Name("ShouldSelectConversation"), object: nil)
    }
    
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        ConversationsController.shared.reload()
    }
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? Connection {
                self.connection = c
                
                self.connection.addDelegate(self)
            }
        }
    }
    
    
    // MARK: -
    @objc func shouldSelectConversation(_ n:Notification) {
        ConversationsController.shared.reload()
        conversationsTableView.reloadData()
                
        if let c = n.object as? Conversation {
            if let index = ConversationsController.shared.conversations().index(of: c) {
                self.conversationsTableView.selectRowIndexes([index], byExtendingSelection: false)
            }
        }
    }
    
    
    

    // MARK: -
    @IBAction func deleteConversation(_ sender: Any) {
        if let c = self.selectedConversation {
            ConnectionsController.shared.removeConversation(c)
            ConversationsController.shared.reload()
            conversationsTableView.reloadData()
            
            NotificationCenter.default.post(name: .selectedConversationDidChange, object: self.selectedConversation)
        }
    }

    
    
    // MARK: -
    func numberOfRows(in tableView: NSTableView) -> Int {
        return ConversationsController.shared.conversations().count
    }
    
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: ConversationCellView?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ConversationCell"), owner: self) as? ConversationCellView
        
        let conversation = ConversationsController.shared.conversations()[row]
        
        view?.userNick?.stringValue = conversation.nick!
        //view?.userStatus?.stringValue = conversation.date!
        
        let unreads = conversation.unreads()
        if unreads > 0 {
            view?.unreadBadge?.stringValue = "\(unreads)"
        } else {
           view?.unreadBadge?.stringValue = ""
        }

        if let base64ImageString = conversation.icon?.base64EncodedData() {
            if let data = Data(base64Encoded: base64ImageString, options: .ignoreUnknownCharacters) {
                view?.userIcon?.image = NSImage(data: data)
            }
        }
        
        return view
    }
    
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if let conversation = self.selectedConversation {            
            DispatchQueue.global(qos: .userInitiated).async {
            
                _ = conversation.markAllAsRead()
                                
                DispatchQueue.main.async {
                    try? AppDelegate.shared.persistentContainer.viewContext.save()
                    if let index = ConversationsController.shared.conversations().index(of: conversation) {
                        self.conversationsTableView.reloadData(forRowIndexes: [index], columnIndexes: [0])
                        AppDelegate.updateUnreadMessages(forConnection: self.connection)
                    }
                }
            }
            
            conversation.connection = self.connection
            NotificationCenter.default.post(name: .selectedConversationDidChange, object: conversation)
        }
        else {
            NotificationCenter.default.post(name: .selectedConversationDidChange, object: nil)
        }
    }
    
    
    
    // MARK: -
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        if self.selectedConversation != nil {
            menu.addItem(withTitle: "Delete Conversation", action: #selector(deleteConversation(_:)), keyEquivalent: "")
        }
    }
    
    
    // MARK: -
    
    public var selectedConversation:Conversation? {
        get {
            if self.conversationsTableView.selectedRow > -1 {
                return ConversationsController.shared.conversations()[self.conversationsTableView.selectedRow]
            }
            return nil
        }
    }
    
    
    
    // MARK: -
    
    func connectionDidConnect(connection: Connection) {
        
    }
    
    func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    func connectionDisconnected(connection: Connection, error: Error?) {
        
    }
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if connection == self.connection {
            if message.name == "wired.message.message" {
                guard let userID = message.uint32(forField: "wired.user.id") else {
                    return
                }
                
                guard let messageString = message.string(forField: "wired.message.message") else {
                    return
                }
                
                if let userInfo = ConnectionsController.shared.usersController(forConnection: connection).user(forID: userID) {
                    let context = AppDelegate.shared.persistentContainer.viewContext
                    var conversation = ConnectionsController.shared.conversation(withNick: userInfo.nick, onConnection: connection)
                    
                    if conversation == nil {
                        conversation = NSEntityDescription.insertNewObject(
                            forEntityName: "Conversation", into: context) as? Conversation

                        conversation!.nick = userInfo.nick!
                        conversation!.icon = userInfo.icon
                        conversation!.uri = connection.URI
                        conversation?.userID = connection.userID
                        
                        conversation?.connection = connection
                        
                        AppDelegate.shared.saveAction(self as AnyObject)
                        
                        ConversationsController.shared.reload()
                        conversationsTableView.reloadData()
                    }
                    
                    conversation!.connection = connection
                    
                    if let cdObject = NSEntityDescription.insertNewObject(forEntityName: "Message", into: context) as? Message {
                        cdObject.body = messageString
                        cdObject.nick = userInfo.nick
                        cdObject.userID = Int32(userInfo.userID)
                        cdObject.me = false
                        cdObject.read = NSApp.isActive && self.view.window != nil && self.view.window!.isKeyWindow
                                                    
                        conversation!.addToMessages(cdObject)
                        
                        try? context.save()
                        
                        if let index = ConversationsController.shared.conversations().index(of: conversation!) {
                            self.conversationsTableView.reloadData(forRowIndexes: [index], columnIndexes: [0])
                        }
                                                                      
                        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "ReceivedPrivateMessage"), object: [connection, cdObject])
                        
                        // add unread
                        
                        if NSApp.isActive == false || self.view.window?.isKeyWindow == false || AppDelegate.selectedToolbarIdentifier(forConnection: connection) != "Messages" {
                            AppDelegate.notify(identifier: "privateMessage", title: "New Message", subtitle: userInfo.nick!, text: messageString, connection: connection)
                            AppDelegate.updateUnreadMessages(forConnection: connection)
                        }
                    }
                }
            }
        }
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
    
}
