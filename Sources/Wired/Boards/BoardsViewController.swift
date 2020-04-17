//
//  BoardsViewController.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class BoardsViewController: ConnectionViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    @IBOutlet weak var boardsOutlineView: NSOutlineView!
    
    public var threadsViewsController:ThreadsViewController!
    
    var boardsController:BoardsController!
    var boardIcon:NSImage!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self, selector: #selector(didLoadBoards(_:)),
            name: .didLoadBoards, object: nil)
        
        self.boardIcon = NSImage(named: "BoardSmall")
        self.boardIcon.size = NSMakeSize(16.0, 16.0)
    }
    
    
    override var representedObject: Any? {
        didSet {
            if let conn = self.representedObject as? ServerConnection {
                self.connection = conn
                self.boardsController = ConnectionsController.shared.boardsController(forConnection: self.connection)
                
                self.boardsController.loadBoard()
            }
        }
    }
    
    
    
    // MARK: -
    
    @objc func didLoadBoards(_ n:Notification) {
        if n.object as? ServerConnection == self.connection {
            self.boardsOutlineView.reloadData()
            self.boardsOutlineView.expandItem(nil, expandChildren: true)
        }
    }
    
    
    // MARK: -
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if self.boardsController == nil {
            return 0
        }
        
        if let board = item as? Board {
            return board.boards.count
        }
        
        return self.boardsController.boards.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let board = item as? Board {
            return board.boards[index]
        }
        return self.boardsController.boards[index]
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let board = item as? Board {
            return board.boards.count > 0
        }
        return false
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?
        
        view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DataCell"), owner: self) as? NSTableCellView
        
        if let board = item as? Board {
            view?.textField?.stringValue = board.name
            view?.imageView?.image = self.boardIcon
        }
        return view
    }
    
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = self.boardsOutlineView.selectedRow
        
        self.threadsViewsController.board = nil
        
        if selectedRow == -1 {
            self.threadsViewsController.board = nil
            
        } else {
            if let board = self.boardsOutlineView.item(atRow: selectedRow) as? Board {
                self.threadsViewsController.board = board
            }
        }
    }
}
