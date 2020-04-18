//
//  PostsViewController.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 17/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit
import WiredSwift_iOS

class PostsViewController: UITableViewController, ConnectionDelegate, BBCodeStringDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

//        tableView.rowHeight = UITableView.automaticDimension
//        tableView.estimatedRowHeight = UITableView.automaticDimension
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        if let connection = self.connection {
            connection.removeDelegate(self)
        }
    }
    
    
    var bookmark:Bookmark!
    var board:Board!
    var thread:BoardThread!
    var connection: Connection? {
        didSet {
            // Update the view.
            if let connection = self.connection {
                connection.addDelegate(self)
                
                self.navigationItem.title = self.thread.subject
                
                self.reloadPosts(forThread: self.thread)
                
            } else {
                self.tableView.reloadData()
            }
        }
    }
    
    
    private func reloadPosts(forThread thread: BoardThread) {
        if let connection = self.connection {
            AppDelegate.shared.hud.show(in: self.view)
            
            let message = P7Message(withName: "wired.board.get_thread", spec: connection.spec)
            message.addParameter(field: "wired.board.thread", value: thread.uuid)

            thread.posts = []
                
            _ = connection.send(message: message)
        }
    }
    
    
    // MARK: -
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if connection == self.connection {
            if message.name == "wired.board.post_list" || message.name == "wired.board.thread" {
                let post = Post(message, board: self.board, thread: self.thread, connection: connection)
//
                thread.posts.append(post)
                
                self.tableView.reloadData()
            }
            else if message.name == "wired.board.post_list.done" {
                AppDelegate.shared.hud.dismiss(afterDelay: 0.5)
                self.tableView.reloadData()
            }
        }
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
    
    

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        if self.thread != nil {
            return 1
        }
        
        return 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let thread = self.thread {
            return thread.posts.count
        }
        return 0
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PostCell", for: indexPath) as! PostViewCell

        let post = self.thread.posts[indexPath.row]
        cell.isUserInteractionEnabled = true
        cell.bodyLabel?.attributedText = BBCodeToAttributedString(withString: post.text)
        cell.nickLabel.text = indexPath.row == 0 ? thread.nick : post.nick
        cell.iconView.image = post.icon
        
        if let date = post.editDate ?? post.postDate {
            cell.dateLabel?.text = AppDelegate.dateTimeFormatter.string(from: date)
        }

        
        return cell
    }
    
//    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
//        return UITableView.automaticDimension
//    }

    
    // MARK: -
    
    private func BBCodeToAttributedString(withString string:String) -> NSAttributedString? {
        if let bbcs = BBCodeString.init(bbCode: string, andLayoutProvider: self) {
            return bbcs.attributedString
        }
        
        return NSAttributedString(string: string)
    }
    
    
    
    // MARK: -
    
    func getSupportedTags() -> [Any]! {
        return ["b", "i", "url", "img", "color", "code"]
    }

    
    func getAttributesFor(_ element: BBElement!) -> [AnyHashable : Any]! {
        if element.tag == "b" {
            return [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 17)]
        }
        else if element.tag == "i" {
            return [NSAttributedString.Key.obliqueness: 0.1]
        }
        else if element.tag.starts(with: "url=") {
            return [NSAttributedString.Key.foregroundColor: UIColor.systemBlue,
                    NSAttributedString.Key.link: element.text as Any]
        }
        else if element.tag.starts(with: "color=") {
            var color = UIColor.lightText
            
            if let htmlColor = element.tag.split(separator: "=").last {
                color = UIColor.init(hexString: String(htmlColor))
            }
            
            return [NSAttributedString.Key.foregroundColor: color]
        }
        else if element.tag.starts(with: "code=") {
            var font = UIFont(name: "Menlo", size: 17)
            
            if #available(iOS 13.0, *) {
                font = UIFont.monospacedSystemFont(ofSize: 17, weight: UIFont.Weight.regular)
            }
            
            return [NSAttributedString.Key.foregroundColor: UIColor.lightText, NSAttributedString.Key.font: font as Any]
        }

        return nil
    }
    
    
    func getAttributedText(for element: BBElement!) -> NSAttributedString! {
        if element.tag == "img" {
            let base64str = String((element.text as String).dropFirst(22))

            if let data = Data(base64Encoded: base64str, options: Data.Base64DecodingOptions.ignoreUnknownCharacters) {
                let ta = NSTextAttachment()
                ta.image = UIImage(data: data)

                return NSAttributedString(attachment: ta)
            }
        }
        else if element.tag == "url" {
            let attrs = [NSAttributedString.Key.foregroundColor: UIColor.systemBlue,
                         NSAttributedString.Key.link: element.text]
            
            return NSAttributedString(string: element.text as String, attributes: attrs as [NSAttributedString.Key : Any])
        }
        
        return nil
    }
}
