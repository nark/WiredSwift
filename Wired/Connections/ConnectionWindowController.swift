//
//  ConnectionWindowController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

public class ConnectionWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    public var connection: ServerConnection!
    public var bookmark: Bookmark!

    var autoreconnectTimer:Timer!
    var reconnectCounter = 0
    
    public var manualyDisconnected = false
    
    public static func connectConnectionWindowController(withBookmark bookmark:Bookmark) -> ConnectionWindowController? {
        if let cwc = AppDelegate.windowController(forBookmark: bookmark) {
            if let tabGroup = cwc.window?.tabGroup {
                tabGroup.selectedWindow = cwc.window
            }
            return cwc
        }
                
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: Bundle.main)
        if let connectionWindowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ConnectionWindowController")) as? ConnectionWindowController {
            let url = bookmark.url()
            
            connectionWindowController.connection = ServerConnection(withSpec: spec, delegate: connectionWindowController as? ConnectionDelegate)
            connectionWindowController.connection.nick = UserDefaults.standard.string(forKey: "WSUserNick") ?? connectionWindowController.connection.nick
            connectionWindowController.connection.status = UserDefaults.standard.string(forKey: "WSUserStatus") ?? connectionWindowController.connection.status
            
            connectionWindowController.connection.connectionWindowController = connectionWindowController
            
            if let b64string = AppDelegate.currentIcon?.tiffRepresentation(using: NSBitmapImageRep.TIFFCompression.none, factor: 0)?.base64EncodedString() {
                connectionWindowController.connection.icon = b64string
            }
            
            DispatchQueue.global().async {
                if connectionWindowController.connection.connect(withUrl: url) == true {
                    DispatchQueue.main.async {
                        ConnectionsController.shared.addConnection(connectionWindowController.connection)
                        
                        connectionWindowController.attach(connection: connectionWindowController.connection)
                        connectionWindowController.windowDidLoad()
                        connectionWindowController.showWindow(connectionWindowController)
                    }
                } else {
                    DispatchQueue.main.async {
                        if let wiredError = connectionWindowController.connection.socket.errors.first {
                            AppDelegate.showWiredError(wiredError)
                        }
                    }
                }
            }
            
            return connectionWindowController
        }
        
        return nil
    }
    
    
    
    
    override public func windowDidLoad() {
        super.windowDidLoad()
    
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(notification:)),
            name: NSWindow.willCloseNotification, object: self.window)
        
        NotificationCenter.default.addObserver(
            self, selector:#selector(linkConnectionDidClose(notification:)) ,
            name: .linkConnectionDidClose, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(didToggleLeftSidebarView(_:)),
            name: .didToggleLeftSidebarView, object: nil)
        
        self.window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: "Chat")
        
//        #if DEBUG
//            //
//        #else
//            if let ti = self.toolbarItem(withIdentifier: "Console") {
//                if let index = self.window?.toolbar?.items.index(of: ti) {
//                    self.window?.toolbar?.removeItem(at: index)
//                }
//            }
//        #endif
        
        self.perform(#selector(showConnectSheet), with: nil, afterDelay: 0.2)
    }

    
    
    // MARK: -
    
    @objc func didToggleLeftSidebarView(_ n:Notification) {
        if let splitViewController = self.contentViewController as? NSSplitViewController {
            splitViewController.splitViewItems.first?.isCollapsed = !splitViewController.splitViewItems.first!.isCollapsed
        }
    }
    
    
    @objc private func showConnectSheet() {
        if self.connection == nil {
            let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: Bundle.main)
            if let connectWindowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ConnectWindowController")) as? NSWindowController {
                if let connectViewController = connectWindowController.window?.contentViewController as? ConnectController {
                    connectViewController.connectionWindowController = self
                    
                    self.window!.beginSheet(connectWindowController.window!) { (modalResponse) in
                        if modalResponse == .cancel {
                            self.close()
                        }
                    }
                }
            }
        }
    }
    

    
    @objc private func windowWillClose(notification: Notification) -> Void {
        if let w = notification.object as? NSWindow {
            if w == self.window {
                self.disconnect()
                
                if self.connection != nil {
                    ConnectionsController.shared.removeConnection(self.connection)
                }
                
                NSApp.removeWindowsItem(w)

                self.window = nil

                NotificationCenter.default.removeObserver(self)
            }
        }
    }
    
    
    @objc private func linkConnectionDidClose(notification: Notification) -> Void {
        if let c = notification.object as? Connection, c == self.connection {
            if let item = self.toolbarItem(withIdentifier: "Disconnect") {
                item.image = NSImage(named: "Reconnect")
                item.label = "Reconnect"
            }
            
            if !self.manualyDisconnected {
                if UserDefaults.standard.bool(forKey: "WSAutoReconnect") {
                    self.startAutoReconnect()
                    
                } else {
                    AppDelegate.notify(identifier: "connection", title: "Server Disconnected", text: "You have been disconnected form \(self.connection.serverInfo.serverName!)", connection: self.connection)
                }
            }
            
            self.manualyDisconnected = false
        }
    }
    
    
    private func windowDidBecomeKey(_ notification: Notification) {
        if self.window == notification.object as? NSWindow {
            if let splitViewController = self.contentViewController as? NSSplitViewController {
                if let tabViewController = splitViewController.splitViewItems[1].viewController as? NSTabViewController {
                    // check if selected toolbar identifier is selected
                    if let identifier = tabViewController.tabView.tabViewItem(at: tabViewController.selectedTabViewItemIndex).identifier as? String {
                        if identifier == "Chat" {
                            if self.connection != nil {
                                AppDelegate.resetChatUnread(forKey: "WSUnreadChatMessages", forConnection: self.connection)
                            }
                        }
                        else if identifier == "Messages" {
                            // hmm, we prefer to unread them by conversation, right ?
                            if let messageSplitView = tabViewController.tabViewItems[1].viewController as? MessagesSplitViewController {
                                if let conversationsViewController = messageSplitView.splitViewItems[1].viewController as? ConversationsViewController {
                                    if let conversation = conversationsViewController.selectedConversation {
                                        // mark conversation messages as read, only if conversation is selected
                                        DispatchQueue.global(qos: .userInitiated).async {
                                            _ = conversation.markAllAsRead()
                                            
                                            DispatchQueue.main.async {
                                                try? AppDelegate.shared.persistentContainer.viewContext.save()
                                                
                                                if let index = ConversationsController.shared.conversations().index(of: conversation) {
                                                    conversationsViewController.conversationsTableView.reloadData(forRowIndexes: [index], columnIndexes: [0])
                                                    AppDelegate.updateUnreadMessages(forConnection: self.connection)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    
    @IBAction func tabAction(_ sender: Any) {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "SelectedToolbarItemChanged"), object: self.window)
    }
    
    
    
    @IBAction func disconnect(_ sender: Any) {
        if let item = self.toolbarItem(withIdentifier: "Disconnect") {
            if self.connection.isConnected() {
                if UserDefaults.standard.bool(forKey: "WSCheckActiveConnectionsBeforeQuit") == true {
                    let alert = NSAlert()
                    alert.messageText = "Are you sure you want to disconnect?"
                    alert.informativeText = "Every running transfers may be stopped"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Cancel")
                    
                    alert.beginSheetModal(for: self.window!) { (modalResponse: NSApplication.ModalResponse) -> Void in
                        if modalResponse == .alertFirstButtonReturn {
                            self.manualyDisconnected = true
                            self.connection.disconnect()
                            item.image = NSImage(named: "Reconnect")
                            item.label = "Reconnect"
                        }
                    }
                } else {
                    self.manualyDisconnected = true
                    self.connection.disconnect()
                    item.image = NSImage(named: "Reconnect")
                    item.label = "Reconnect"
                }
    
            } else {
                self.reconnect()
            }
        }
    }
    
    
    private func reconnect() {
        self.reconnectCounter += 1
        
        if let item = self.toolbarItem(withIdentifier: "Disconnect") {
            if !self.connection.isConnected() {
                item.isEnabled = false
                item.label = "Reconnecting"
                
                DispatchQueue.global().async {
                    if self.connection.connect(withUrl: self.connection.url) {
                        DispatchQueue.main.async {
                            print("reconnected")
                            
                            self.stopAutoReconnect()
                            
                            _ = self.connection.joinChat(chatID: 1)
                            
                            NotificationCenter.default.post(name: .linkConnectionDidReconnect, object: self.connection)
                            
                            item.image = NSImage(named: "Disconnect")
                            item.label = "Disconnect"
                            
                            item.isEnabled = true
                        }
                    } else {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .linkConnectionDidFailReconnect, object: self.connection)
                            item.isEnabled = true
                            item.label = "Reconnect"
                        }
                    }
                }
            }
        }
    }

    
    
    public func attach(connection:ServerConnection) {
        self.connection = connection
        
        if let splitViewController = self.contentViewController as? NSSplitViewController {
            if let resourcesController = splitViewController.splitViewItems[0].viewController as? ResourcesController {
                  resourcesController.representedObject = self.connection
            }
              
            if let tabViewController = splitViewController.splitViewItems[1].viewController as? NSTabViewController {
                if let splitViewController2 = tabViewController.tabViewItems[0].viewController as? NSSplitViewController {
                    if let userController = splitViewController2.splitViewItems[1].viewController as? UsersViewController {
                        userController.representedObject = self.connection
                    }

                    if let chatController = splitViewController2.splitViewItems[0].viewController as? ChatViewController {
                        chatController.representedObject = self.connection
                    }
                    
                    self.window?.title = self.connection.serverInfo.serverName
                }
                
                for item in tabViewController.tabViewItems {
                    if let connectionController = item.viewController as? InfosViewController {
                        connectionController.representedObject = self.connection
                    }
                    else if let messagesSplitViewController = item.viewController as? MessagesSplitViewController {
                        if let conversationsViewController = messagesSplitViewController.splitViewItems[1].viewController as? ConversationsViewController {
                            conversationsViewController.representedObject = self.connection
                        }
                    }
                    else if let boardsSplitViewController = item.viewController as? BoardsSplitViewController {
                        if let boardsViewController = boardsSplitViewController.splitViewItems[0].viewController as? BoardsViewController {
                            boardsViewController.representedObject = self.connection
                            
                            if let threadsSplitViewController = boardsSplitViewController.splitViewItems[1].viewController as? NSSplitViewController {
                                if let threadsViewController = threadsSplitViewController.splitViewItems[0].viewController as? ThreadsViewController {
                                    boardsViewController.threadsViewsController = threadsViewController
                                    threadsViewController.representedObject = self.connection
                                    
                                    if let postsViewController = threadsSplitViewController.splitViewItems[1].viewController as? PostsViewController {
                                        threadsViewController.postsViewController = postsViewController
                                        postsViewController.representedObject = self.connection
                                    }
                                }
                                
                            }
                        }
                    }
                    else if let connectionController = item.viewController as? FilesViewController {
                        connectionController.representedObject = self.connection
                    }
                    else if let connectionController = item.viewController as? ConsoleViewController {
                        connectionController.representedObject = self.connection
                    }
                }
            }
            
            AppDelegate.updateUnreadMessages(forConnection: connection)
        }
    }
    
    public func disconnect() {
        if self.connection != nil {
            //ConnectionsController.shared.removeConnection(self.connection)
            self.connection.disconnect()
        }
    }
    
    
    
    private func toolbarItem(withIdentifier: String) -> NSToolbarItem? {
        for item in (self.window?.toolbar!.items)! {
                if item.itemIdentifier.rawValue == withIdentifier {
                    return item
                }
        }
        return nil
    }
    
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        return true
    }
    
    
    private func startAutoReconnect() {
        self.stopAutoReconnect()
        
        let interval = 10.0
        
        self.autoreconnectTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { (timer) in
            print("Try to auto-reconnect every \(interval) sec. (\(self.reconnectCounter))...")
            
            self.reconnect()
        }
    }
    
    private func stopAutoReconnect() {
        self.reconnectCounter = 0
        
        if self.autoreconnectTimer != nil {
            self.autoreconnectTimer.invalidate()
            self.autoreconnectTimer = nil
        }
    }
}
