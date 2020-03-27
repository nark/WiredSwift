//
//  ThreadsViewController.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class ThreadsViewController: ConnectionViewController, NSTableViewDelegate, NSTableViewDataSource {
    @IBOutlet weak var threadsTableView: NSTableView!
    
    var boardsController:BoardsController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(didLoadThreads(_:)),
            name: .didLoadThreads, object: nil)
    }
    
    
    // MARK: -
    
    override var representedObject: Any? {
        didSet {
            if let conn = self.representedObject as? ServerConnection {
                self.connection = conn
                self.boardsController = ConnectionsController.shared.boardsController(forConnection: self.connection)
            }
        }
    }
    
    
    public var board: Board? {
        didSet {
            if self.connection != nil && self.connection.isConnected() {
                if let b = self.board {
                    self.boardsController.loadThreads(forBoard: b)
                }
            }
        }
    }
    
    
    // MARK: -
    
    @objc func didLoadThreads(_ n:Notification) {
        if n.object as? ServerConnection == self.connection {
            self.threadsTableView.reloadData()
        }
    }
    
    
    // MARK: -
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.board?.threads.count ?? 0
    }
    
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: ThreadCellView?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ThreadCell"), owner: self) as? ThreadCellView
        
        if let thread = self.board?.threads[row] {
            print("thread.subject: \(thread.subject)")
            view?.nickLabel?.stringValue = thread.nick
            view?.subjectLabel?.stringValue = thread.subject
        }

        return view
    }
}
