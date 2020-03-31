//
//  ResourcesController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let selectedResourceDidChange = Notification.Name("selectedResourceDidChange")
}


class ResourcesController: ConnectionViewController, ConnectionDelegate, NSOutlineViewDelegate, NSOutlineViewDataSource, NSUserInterfaceValidations {
    @IBOutlet weak var resourcesOutlineView: NSOutlineView!
        
    var selectedBookmark:Bookmark!
    
    struct ResourceIdentifiers {
        static let connections = NSLocalizedString("CONNECTIONS", comment: "")
        static let bookmarks = NSLocalizedString("BOOKMARKS", comment: "")
        static let trackers = NSLocalizedString("TRACKERS", comment: "")
        static let history = NSLocalizedString("HISTORY", comment: "")
    }
    
    let categories = [
        ResourceIdentifiers.connections,
        ResourceIdentifiers.bookmarks,
//        ResourceIdentifiers.trackers,
//        ResourceIdentifiers.history
    ]
    
    // MARK: View Lifecycle -
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector:  #selector(selectedResourceDidChange), name: .selectedResourceDidChange, object: nil)
        
        NotificationCenter.default.addObserver(self, selector:  #selector(didUpdateConnections), name: .didAddNewConnection, object: nil)
        NotificationCenter.default.addObserver(self, selector:  #selector(didUpdateConnections), name: .didRemoveConnection, object: nil)
        NotificationCenter.default.addObserver(self, selector:  #selector(didUpdateConnections), name: .didAddNewBookmark, object: nil)
        
        resourcesOutlineView.target = self
        resourcesOutlineView.doubleAction = #selector(doubleClickResource)
    }

    


    
    override func viewDidAppear() {
        super.viewDidAppear()
                
        self.resourcesOutlineView.reloadData()
        self.resourcesOutlineView.expandItem(nil, expandChildren: true)
    }
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? ServerConnection {
                self.connection = c
                c.delegates.append(self)
            }
        }
    }
    
    
    
    
    
    @objc private func doubleClickResource() {
        if let clickedItem = resourcesOutlineView.item(atRow: resourcesOutlineView.clickedRow) {
            if let bookmark = clickedItem as? Bookmark {
                _ = ConnectionWindowController.connectConnectionWindowController(withBookmark: bookmark)
            }
            // reveal connection on double click
            else if let connection = clickedItem as? Connection {
                if let cwc = AppDelegate.windowController(forConnection: connection) {
                    if let tabGroup = cwc.window?.tabGroup {
                        tabGroup.selectedWindow = cwc.window
                    }
                }
            }
        }
    }
    
    
    
    @objc func selectedResourceDidChange(_ notification: Notification) {
        if let sourceOutlineView = notification.object as? NSOutlineView {
            if sourceOutlineView != resourcesOutlineView {
                resourcesOutlineView.selectRowIndexes(sourceOutlineView.selectedRowIndexes, byExtendingSelection: false)
            }
        }
    }
    
    
    @objc func didUpdateConnections(_ notification: Notification) {
        if let _ = notification.object as? Connection {
            self.resourcesOutlineView.reloadData()
        }
        else if let _ = notification.object as? Bookmark {
            self.resourcesOutlineView.reloadData()
        }
    }
    
    
    
    // MARK: -
    @IBAction func disconnect(_ sender: Any) {
        if let selectedConnection = self.selectedItem() as? ServerConnection {
            self.connection.connectionWindowController!.manualyDisconnected = true
            
            selectedConnection.disconnect()
        }
    }
    
    @IBAction func addToBookmarks(_ sender: Any) {
        AppDelegate.shared.addToBookmarks(sender)
    }
    
    @IBAction func editBookmark(_ sender: Any) {
        if let bookmark = self.selectedBookmark {
            let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: Bundle.main)
            if let bookmarkWindowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("BookmarkViewController")) as? NSWindowController {
                if let bookmarkViewController = bookmarkWindowController.contentViewController as? BookmarkViewController {
                    bookmarkViewController.bookmark = bookmark
                    
                    NSApp.mainWindow?.beginSheet(bookmarkWindowController.window!, completionHandler: { (modalResponse) in
                        if modalResponse == .OK {
                            self.resourcesOutlineView.reloadData()
                        }
                        
                        self.selectedBookmark = nil
                    })
                }
            }
        }
    }
    
    @IBAction func removeBookmark(_ sender: Any) {
        if let selectedItem = self.selectedItem()  {
            if let bookmark = selectedItem as? Bookmark {
                let alert = NSAlert()
                alert.messageText = "Are you sure you want to delete this bookmark?"
                alert.informativeText = "This operation is not recoverable"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")
                
                alert.beginSheetModal(for: self.view.window!) { (modalResponse: NSApplication.ModalResponse) -> Void in
                    if modalResponse == .alertFirstButtonReturn {
                        ConnectionsController.shared.removeBookmark(bookmark)
                        self.resourcesOutlineView.reloadData()
                    }
                }
            }
        }
    }
    
    
    // MARK: NSValidatedUserInterfaceItem
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        
        if let connection = self.selectedItem() as? ServerConnection {
            if item.action == #selector(addToBookmarks(_:)) {
                return true
            }
            else if item.action == #selector(disconnect(_:)) {
                return connection.isConnected()
            }
        } else {
            if let bookmark = self.selectedItem() as? Bookmark {
                self.selectedBookmark = bookmark
                
                if item.action == #selector(editBookmark(_:)) {
                    return true
                }
                if item.action == #selector(removeBookmark(_:)) {
                    return true
                }
            }
        }
           
        return false
    }
    
    

    
    // MARK: Connection Delegate -
    func connectionDidConnect(connection: Connection) {

    }
    
    func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    func connectionDisconnected(connection: Connection, error: Error?) {
        self.resourcesOutlineView.reloadData()
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
                return ConnectionsController.shared.bookmarks().count
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
            else if c == ResourceIdentifiers.bookmarks {
                return ConnectionsController.shared.bookmarks()[index]
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
            if connection.isConnected() {
                view?.imageView?.image = NSImage(named: "ConnectionStatusConnected")
            } else {
                view?.imageView?.image = NSImage(named: "ConnectionStatusDisconnected")
            }
        }
        else if let bookmark = item as? Bookmark {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DataCell"), owner: self) as? NSTableCellView
            if let name = bookmark.name {
                view?.textField?.stringValue = name
                view?.imageView?.image = NSImage(named: "BookmarksSmall")
            }
        }
        
        return view
    }
    
    
    
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return 24
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if let selectedItem = self.selectedItem() {
            NotificationCenter.default.post(name: .selectedResourceDidChange, object: resourcesOutlineView)
            
            if let bookmark = selectedItem as? Bookmark {
                if let cwc = AppDelegate.windowController(forBookmark: bookmark) {
                    if let tabGroup = cwc.window?.tabGroup {
                        tabGroup.selectedWindow = cwc.window
                    }
                }
            }
            else if let connection = selectedItem as? ServerConnection {
                if let cwc = AppDelegate.windowController(forConnection: connection) {
                    if let tabGroup = cwc.window?.tabGroup {
                        tabGroup.selectedWindow = cwc.window
                    }
                }
            }
        }
    }
    
    
    // MARK: - Menu Delegate
//    func menuNeedsUpdate(_ menu: NSMenu) {
//        menu.removeAllItems()
//        
//        if menu != resourcesOutlineView.menu {
//            let cogItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
//            cogItem.image = NSImage(named: "NSActionTemplate")
//            menu.addItem(cogItem)
//        }
//
//        
//        if let selectedItem = self.selectedItem()  {
//            if let connection = selectedItem as? Connection {
//                if connection.isConnected() {
//                    menu.addItem(withTitle: "Add To Bookmarks", action: #selector(addToBookmarks(_:)), keyEquivalent: "")
//                    menu.addItem(NSMenuItem.separator())
//                    menu.addItem(withTitle: "Disconnect", action: #selector(disconnect(_:)), keyEquivalent: "")
//                }
//            }
//            else if let b = selectedItem as? Bookmark {
//                self.selectedBookmark = b
//                menu.addItem(withTitle: "Edit Bookmark", action: #selector(editBookmark(_:)), keyEquivalent: "")
//                menu.addItem(withTitle: "Remove Bookmark", action: #selector(removeSelectedBookmark), keyEquivalent: "")
//            }
//        }
//    }
    

    
    
    
    // MARK: - Private
    private func selectedItem() -> Any? {
        var selectedIndex = resourcesOutlineView.clickedRow
                
        if selectedIndex == -1 {
            selectedIndex = resourcesOutlineView.selectedRow
        }
        
        if selectedIndex == -1 {
            return nil
        }
                
        return resourcesOutlineView.item(atRow: selectedIndex)
    }
}
