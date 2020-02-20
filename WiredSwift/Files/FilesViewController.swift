//
//  FilesViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa


class FileCell: NSBrowserCell {
    override init(imageCell i: NSImage?) {
        super.init(imageCell: i)
        isLeaf = true
    }
    
    override init(textCell s: String) {
        super.init(textCell: s)
        isLeaf = true
    }
    
    required init(coder c: NSCoder) {
        super.init(coder: c)
        isLeaf = true
    }
}


class FilesViewController: ConnectionController, ConnectionDelegate, NSBrowserDelegate {
    @IBOutlet weak var browser: NSBrowser!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    
    var filesController:FilesController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        browser.setCellClass(FileCell.self)
        browser.target = self
        browser.doubleAction = #selector(doubleClickFile)
        
        NotificationCenter.default.addObserver(self, selector:  #selector(didLoadDirectory(_:)), name: .didLoadDirectory, object: nil)
    }
    
    
    override func viewDidAppear() {
        super.viewDidAppear()
    }
    
    override var representedObject: Any? {
        didSet {
            if let conn = self.representedObject as? Connection {
                self.connection = conn
                self.filesController = ConnectionsController.shared.filesController(forConnection: self.connection)
                
                self.connection.delegates.append(self)
                
                self.filesController.load(ofFile: nil)
                self.progressIndicator.startAnimation(self)
                self.updateView()
            }
        }
    }
    
    
    private func updateView() {        
        if self.connection != nil {
            //self.filesController.load(ofFile: nil)
        }
    }
    
    
    
    // MARK: -
    
    @objc func didLoadDirectory(_ notification: Notification) {
        if let file = notification.object as? File {
            let columnIndex = file.path.split(separator: "/").count
            print("columnIndex : \(columnIndex)")
            
            browser.reloadColumn(columnIndex)
            self.progressIndicator.stopAnimation(self)
        }
    }
    
    
    @objc private func doubleClickFile() {
        if let clickedItem = browser.item(atRow: browser.clickedRow, inColumn: browser.clickedColumn) {
            if let file = clickedItem as? File {
                if !file.isFolder() {
                    TransfersController.shared.download(file)
                }
            }
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

    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
    
    // MARK: -

    func browser(_ browser: NSBrowser, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet, inColumn column: Int) -> IndexSet {
        if let index = proposedSelectionIndexes.first {
            if let file = browser.item(atRow: index, inColumn: column) as? File {
                if file.isFolder() && file.children.count == 0 {
                    self.filesController.load(ofFile: file)
                    self.progressIndicator.startAnimation(self)
                }
            }
        }
        
        return proposedSelectionIndexes;
    }
    
    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        if let file = item as? File {
            return file.children.count
        }
        return self.filesController.rootFile.children.count
    }
    
    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any {
        if let file = item as? File {
            return file.children[index]
        }
        return self.filesController.rootFile.children[index]
    }
    
    
    func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool {
        if let f = item as? File {
            return f.type == .file
        }
        return true
    }
    
    
    func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? {
        if let f = item as? File {
            return f.name
        }
        return "nil"
    }
    
    func browser(_ sender: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
        if let f = sender.item(atRow: row, inColumn: column) as? File {
            if let theCell = cell as? FileCell {
                //theCell.isLeaf = f.type == .file
                if let icon = f.icon() {
                    icon.size = NSMakeSize(16.0, 16.0)
                    theCell.image = icon
                }
            }
        }
    }
}
