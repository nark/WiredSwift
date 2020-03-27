//
//  PostsViewController.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class PostsViewController: ConnectionViewController, NSTableViewDelegate, NSTableViewDataSource {
    @IBOutlet weak var postsTableView: NSTableView!
    
    var boardsController:BoardsController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(didLoadPosts(_:)),
            name: .didLoadPosts, object: nil)
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

            }
        }
    }
    
    public var thread: Thread? {
        didSet {
            if self.connection != nil && self.connection.isConnected() {
                if let t = self.thread {
                    self.boardsController.loadPosts(forThread: t)
                }
            }
        }
    }
    
    
    
    
    // MARK: -
    
    @objc func didLoadPosts(_ n:Notification) {
        if n.object as? ServerConnection == self.connection {
            self.postsTableView.reloadData()
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
            view?.nickLabel?.stringValue = thread.nick
            view?.subjectLabel?.stringValue = thread.subject
        }

        return view
    }
    
}
