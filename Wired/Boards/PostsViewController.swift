//
//  PostsViewController.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa


class PostsViewController: ConnectionViewController, NSTableViewDelegate, NSTableViewDataSource, BBCodeStringDelegate {
    
    @IBOutlet weak var postsTableView: NSTableView!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    
    var boardsController:BoardsController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(
        self, selector: #selector(didStartLoadingBoards(_:)),
        name: .didStartLoadingBoards, object: nil)
        
        NotificationCenter.default.addObserver(
        self, selector: #selector(didLoadBoards(_:)),
        name: .didLoadBoards, object: nil)
        
        NotificationCenter.default.addObserver(
        self, selector: #selector(didLoadThreads(_:)),
        name: .didLoadThreads, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(didLoadPosts(_:)),
            name: .didLoadPosts, object: nil)
        
        self.progressIndicator.startAnimation(self)
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
                if self.board == nil {
                    self.thread = nil
                    self.postsTableView.reloadData()
                }
            }
        }
    }
    
    public var thread: BoardThread? {
        didSet {
            if self.connection != nil && self.connection.isConnected() {
                if let t = self.thread {
                    self.boardsController.loadPosts(forThread: t)
                } else {
                    self.postsTableView.reloadData()
                }
            }
        }
    }
    
    
    
    
    // MARK: -
    
    @objc func didStartLoadingBoards(_ n:Notification) {
        if n.object as? ServerConnection == self.connection {
            self.progressIndicator.startAnimation(self)
        }
    }
    
    @objc func didLoadBoards(_ n:Notification) {
        if n.object as? ServerConnection == self.connection {
            self.progressIndicator.stopAnimation(self)
        }
    }
    
    @objc func didLoadThreads(_ n:Notification) {
        if n.object as? ServerConnection == self.connection {
            self.progressIndicator.stopAnimation(self)
        }
    }
    
    @objc func didLoadPosts(_ n:Notification) {
        if n.object as? ServerConnection == self.connection {
            self.postsTableView.reloadData()
            self.progressIndicator.stopAnimation(self)
        }
    }
    
    
    // MARK: -
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        if self.thread == nil {
            return 0
        }
        return self.thread?.posts.count ?? 0
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: PostCellView?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "PostCell"), owner: self) as? PostCellView
        
        if let post = self.thread?.posts[row] {
            view?.nickLabel?.stringValue = post.nick
            if let attributedString = self.BBCodeToAttributedString(withString: post.text) {
                view?.textLabel?.attributedStringValue = attributedString
            }
            view?.iconView.image = post.icon
        }

        return view
    }
    
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return UnselectedTableRowView()
    }
    
    
    
    // MARK: -
    
    private func BBCodeToAttributedString(withString string:String) -> NSAttributedString? {
        if let bbcs = BBCodeString.init(bbCode: string, andLayoutProvider: self) {
            return bbcs.attributedString
        }
        
        return NSAttributedString(string: string)
    }
    
    
    
    // MARK: -
    
    func getSupportedTags() -> [Any]! {
        return ["b", "i", "url", "img", "color"]
    }

    
    func getAttributesFor(_ element: BBElement!) -> [AnyHashable : Any]! {
        if element.tag == "b" {
            return [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 13)]
        }
        else if element.tag == "i" {
            return [NSAttributedString.Key.obliqueness: 0.1]
        }
        else if element.tag.starts(with: "url=") {
            return [NSAttributedString.Key.foregroundColor: NSColor.systemBlue,
                    NSAttributedString.Key.link: element.text,
                    NSAttributedString.Key.cursor: NSCursor.pointingHand]
        }
        else if element.tag.starts(with: "color=") {
            var color = NSColor.textColor
            if let htmlColor = element.tag.split(separator: "=").last {
                color = NSColor.init(hexString: String(htmlColor))
            }
            return [NSAttributedString.Key.foregroundColor: color]
        }

        return nil
    }
    
    
    func getAttributedText(for element: BBElement!) -> NSAttributedString! {
        if element.tag == "img" {
            let base64str = String((element.text as String).dropFirst(22))

            if let data = Data(base64Encoded: base64str, options: Data.Base64DecodingOptions.ignoreUnknownCharacters) {
                let ta = NSTextAttachment()
                ta.image = NSImage(data: data)

                return NSAttributedString(attachment: ta)
            }
        }
        else if element.tag == "url" {
            let attrs = [NSAttributedString.Key.foregroundColor: NSColor.systemBlue,
                         NSAttributedString.Key.link: element.text,
                         NSAttributedString.Key.cursor: NSCursor.pointingHand]
            
            return NSAttributedString(string: element.text as String, attributes: attrs as [NSAttributedString.Key : Any])
        }
        
        return nil
    }
}
