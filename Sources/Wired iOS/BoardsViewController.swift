//
//  BoardsViewController.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 17/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit
import WiredSwift_iOS

class BoardsViewController: UITableViewController, ConnectionDelegate {
    public private(set) var boards:[Board] = []
    //public private(set) var boardsByPath:[String:Board] = [:]
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

    }
    
    
    var bookmark:Bookmark!
    var connection: Connection? {
        didSet {
            // Update the view.
            if let connection = self.connection {
                connection.addDelegate(self)
                print("BoardsViewController connection changed")
                self.reloadBoards()
                
            } else {
                print("BoardsViewController connection is now nil")
                self.tableView.reloadData()
            }
        }
    }
    
    
    
    
    
    // MARK: -
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if connection == self.connection {
            if message.name == "wired.board.board_list" {
                let board = Board(message, connection: connection)
                self.boards.append(board)
                
                self.tableView.reloadData()
            }
            else if message.name == "wired.board.board_list.done" {
                AppDelegate.shared.hud.dismiss(afterDelay: 1.0)
                
                self.tableView.reloadData()
            }
        }
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
    

    
    // MARK: -
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let indexPath = self.tableView.indexPathForSelectedRow {
            if segue.identifier == "ShowThreads" {
                let board = self.boards[indexPath.row]
                
                if let threadsViewController = segue.destination as? ThreadsViewController {
                    threadsViewController.board = board
                    threadsViewController.bookmark = self.bookmark
                    threadsViewController.connection = self.connection
                }
            }
        }
    }
    
    

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        if let connection = self.connection, connection.isConnected() {
            return 1
        }
        return 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let connection = self.connection, connection.isConnected() {
            return self.boards.count
        }
        
        return 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BoardCell", for: indexPath)

        let board = self.boards[indexPath.row]
        cell.indentationLevel = board.path.split(separator: "/").count - 1
        cell.indentationWidth = 15.0
        cell.textLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        cell.textLabel?.text = board.name

        if #available(iOS 13.0, *) {
            cell.imageView?.image = UIImage(named: "Board")?.withTintColor(UIColor.systemGreen)
        } else {
            cell.imageView?.image = UIImage(named: "Board")
        }
        
        return cell
    }

    
    
    // MARK: -
    
    private func parentBoard(forPath path:String) -> Board? {
        for parent in self.boards {
            let parentPath = (path as NSString).deletingLastPathComponent
            if parent.path == parentPath {
                return parent
            }
        }
        return nil
    }
    
    
    private func reloadBoards() {
        if let connection = self.connection {
            AppDelegate.shared.hud.show(in: view)
            
            self.boards.removeAll()
            
            let message = P7Message(withName: "wired.board.get_boards", spec: connection.spec)
            
            _ = connection.send(message: message)
        }
    }
}
