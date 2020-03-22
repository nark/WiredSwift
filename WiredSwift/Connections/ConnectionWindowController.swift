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
    
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(notification:)), name: NSWindow.willCloseNotification, object: self.window)
        
        self.window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: "Chat")
    }
    

    
    @objc private func windowWillClose(notification: Notification) -> Void {
        if let w = notification.object as? NSWindow, w == self.window {
            self.disconnect()
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    
    func windowDidBecomeKey(_ notification: Notification) {
        if self.window == notification.object as? NSWindow {
            if let splitViewController = self.contentViewController as? NSSplitViewController {
                if let tabViewController = splitViewController.splitViewItems[1].viewController as? NSTabViewController {
                    if let identifier = tabViewController.tabView.tabViewItem(at: tabViewController.selectedTabViewItemIndex).identifier as? String {
                        if identifier == "Chat" {
                            AppDelegate.resetUnread(forKey: "WSUnreadChatMessages", forConnection: self.connection)
                        }
                        else if identifier == "Messages" {
                            AppDelegate.resetUnread(forKey: "WSUnreadPrivateMessages", forConnection: self.connection)
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
        self.window?.close()
    }

    
    public func disconnect() {
        if self.connection != nil {
            ConnectionsController.shared.removeConnection(self.connection)
            
            self.connection.disconnect()
        }
    }
}
