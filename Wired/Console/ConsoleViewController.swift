//
//  ConsoleViewController.swift
//  Wired
//
//  Created by Rafael Warnault on 26/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class ConsoleViewController: ConnectionViewController, ConnectionDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate {
    @IBOutlet weak var messagesOutlineView: NSOutlineView!
    
    var messages:[P7Message] = []
    var sentMessages:[P7Message] = []
    var receivedMessages:[P7Message] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? ServerConnection {
                self.connection = c
                                
                c.delegates.append(self)
            }
        }
    }
    
    
    // MARK: -
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let message = item as? P7Message {
            return message.numberOfParameters
        }
        return self.messages.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let message = item as? P7Message {
            let key = message.parameterKeys[index]
            return [key, message]
        }
        return self.messages[index]
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is P7Message
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?
        
        view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MessageCell"), owner: self) as? NSTableCellView
        
        if let message = item as? P7Message {
            if tableColumn?.identifier.rawValue == "Date" {
                view?.textField?.stringValue = AppDelegate.dateTimeFormatter.string(from: Date())
            }
            else if tableColumn?.identifier.rawValue == "Type" {
                view?.textField?.stringValue = receivedMessages.contains(message) ? "Received" : "Sent"
            }
            else if tableColumn?.identifier.rawValue == "Message" {
                view?.textField?.stringValue = message.name
            }
            else if tableColumn?.identifier.rawValue == "Size" {
                view?.textField?.stringValue = "\(message.size) bytes"
            }
        } else if let paramArray = item as? Array<Any> {
            
            if tableColumn?.identifier.rawValue == "Date" {
                if let key = paramArray.first as? String {
                    view?.textField?.stringValue = key
                }
            }
            else if tableColumn?.identifier.rawValue == "Message" {
                if  let key = paramArray.first as? String,
                    let message = paramArray.last as? P7Message {
                    
                    view?.textField?.stringValue = message.lazy(field: key) ?? ""
                }
            } else {
                view?.textField?.stringValue = ""
            }
        }
        return view
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
            self.add(message: message)
        }
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        if connection == self.connection {
            self.add(message: message)
        }
    }
    
    
    func connectionDidSendMessage(connection: Connection, message: P7Message) {
        if connection == self.connection {
            self.add(message: message, sent: true)
        }
    }
    
    
    private func add(message: P7Message, sent: Bool = false) {
        self.messages.append(message)
        
        if sent {
            self.sentMessages.append(message)
        } else {
            self.receivedMessages.append(message)
        }
        
        self.messagesOutlineView.reloadData()        
        self.messagesOutlineView.scrollRowToVisible(self.messages.count - 1)
    }
}
