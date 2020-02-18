//
//  ResourcesController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class ResourcesController: ConnectionController, ConnectionDelegate, NSOutlineViewDelegate, NSOutlineViewDataSource {
    @IBOutlet weak var resourcesOutlineView: NSOutlineView!
    
    struct ResourceIdentifiers {
        static let connections  = "CONNECTIONS"
        static let bookmarks    = "BOOKMARKS"
        static let trackers     = "TRACKERS"
        static let history      = "HISTORY"
    }
    
    let categories = [
        ResourceIdentifiers.connections,
        ResourceIdentifiers.bookmarks,
        ResourceIdentifiers.trackers,
        ResourceIdentifiers.history
    ]
    
    // MARK: View Lifecycle -
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        NotificationCenter.default.addObserver(self, selector:  #selector(didAddNewConnection), name: .didAddNewConnection, object: nil)
    }
    
    
    @objc func didAddNewConnection(_ notification: Notification) {
        if let _ = notification.object as? Connection {
            self.resourcesOutlineView.reloadData()
        }
    }

    
    override func viewDidAppear() {
        super.viewDidAppear()
                
        self.resourcesOutlineView.reloadData()
        self.resourcesOutlineView.expandItem(nil, expandChildren: true)
    }
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? Connection {
                self.connection = c
                //self.connections.append(c)
                c.delegates.append(self)
            }
        }
    }
    
    
    // MARK: Connection Delegate -
    func connectionDidConnect(connection: Connection) {

    }
    
    func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    func connectionDisconnected(connection: Connection, error: Error?) {

    }
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        self.resourcesOutlineView.reloadData()
        self.resourcesOutlineView.expandItem(nil, expandChildren: true)
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
    
    
    // MARK: OutlineView DataSource & Delegate -
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let c = item as? String {
            if c == ResourceIdentifiers.connections {
                return ConnectionsController.shared.connections.count
            }
            else if c == ResourceIdentifiers.bookmarks {
                return 0
            }
            else if c == ResourceIdentifiers.trackers {
                return 0
            }
            else if c == ResourceIdentifiers.history {
                return 0
            }
        }

        return self.categories.count
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let c = item as? String {
            if c == ResourceIdentifiers.connections {
                return ConnectionsController.shared.connections[index]
            }
        }

        return self.categories[index]
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let s = item as? String, self.categories.contains(s) {
            return true
        }
        
        return false
    }


    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if let _ = item as? String {
            return false
        }
        return true
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        if let _ = item as? String {
            return true
        }
        return false
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?

        if let resource = item as? String {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "HeaderCell"), owner: self) as? NSTableCellView
            view?.textField?.stringValue = resource
        }
        else if let connection = item as? Connection {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DataCell"), owner: self) as? NSTableCellView
            view?.textField?.stringValue = connection.serverInfo.serverName
        }
        
        return view
    }
}
