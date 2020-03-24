//
//  ConnectionWindowController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class ConnectionWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    public var connection: Connection!
    
    
    override func windowDidLoad() {
        super.windowDidLoad()
    
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(notification:)),
            name: NSWindow.willCloseNotification, object: self.window)
        
        NotificationCenter.default.addObserver(
            self, selector:#selector(linkConnectionDidClose(notification:)) ,
            name: .linkConnectionDidClose, object: nil)
        
        self.window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: "Chat")
    }
    

    
    @objc private func windowWillClose(notification: Notification) -> Void {
        if let w = notification.object as? NSWindow, w == self.window {
            self.disconnect()
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    
    @objc private func linkConnectionDidClose(notification: Notification) -> Void {
        if let c = notification.object as? Connection, c == self.connection {
            if let item = self.toolbarItem(withIdentifier: "Disconnect") {
                item.image = NSImage(named: "Reconnect")
                item.label = "Reconnect"
            }
        }
    }
    
    
    func windowDidBecomeKey(_ notification: Notification) {
        if self.window == notification.object as? NSWindow {
            if let splitViewController = self.contentViewController as? NSSplitViewController {
                if let tabViewController = splitViewController.splitViewItems[1].viewController as? NSTabViewController {
                    // check if selected toolbar identifier is selected
                    if let identifier = tabViewController.tabView.tabViewItem(at: tabViewController.selectedTabViewItemIndex).identifier as? String {
                        if identifier == "Chat" {
                            AppDelegate.resetChatUnread(forKey: "WSUnreadChatMessages", forConnection: self.connection)
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
                            self.connection.disconnect()
                            item.image = NSImage(named: "Reconnect")
                            item.label = "Reconnect"
                        }
                    }
                } else {
                    self.connection.disconnect()
                    item.image = NSImage(named: "Reconnect")
                    item.label = "Reconnect"
                }
    
            } else {
                item.isEnabled = false
                DispatchQueue.global().async {
                    if self.connection.connect(withUrl: self.connection.url) {
                        DispatchQueue.main.async {
                            print("reconnected")
                            _ = self.connection.joinChat(chatID: 1)
                            
                            NotificationCenter.default.post(name: .linkConnectionDidReconnect, object: self.connection)
                            
                            item.image = NSImage(named: "Disconnect")
                            item.label = "Disconnect"
                            
                            item.isEnabled = true
                        }
                    } else {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .linkConnectionDidFailReconnect, object: self.connection)
                            item.isEnabled = false
                        }
                    }
                }
            }
        }
    }

    
    
    public func disconnect() {
        if self.connection != nil {
            ConnectionsController.shared.removeConnection(self.connection)
            
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
    
}
