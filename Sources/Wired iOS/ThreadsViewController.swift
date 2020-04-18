//
//  ThreadsViewController.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 17/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit
import WiredSwift_iOS

class ThreadsViewController: UITableViewController, ConnectionDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

    }
    
    
    override func viewDidDisappear(_ animated: Bool) {
        if let connection = self.connection {
            connection.removeDelegate(self)
        }
    }
    
    var bookmark:Bookmark!
    var board:Board!
    var connection: Connection? {
        didSet {
            // Update the view.
            if let connection = self.connection {
                connection.addDelegate(self)
                print("ThreadsViewController connection changed")
                self.reloadThreads(forBoard: self.board)
                
            } else {
                print("ThreadsViewController connection is now nil")
                self.tableView.reloadData()
            }
        }
    }
    
    
    private func reloadThreads(forBoard board:Board) {
        if let connection = self.connection {
            AppDelegate.shared.hud.show(in: self.view)
            
            let message = P7Message(withName: "wired.board.get_threads", spec: connection.spec)
            message.addParameter(field: "wired.board.board", value: board.path)

            board.threads = []
                
            _ = connection.send(message: message)
        }
    }
    
    
    
    // MARK: -
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if connection == self.connection {
            if message.name == "wired.board.thread_list" {
                let thread = BoardThread(message, board: board, connection: connection)
                
                board.addThread(thread)
                
                self.tableView.reloadData()
            }
            else if message.name == "wired.board.thread_list.done" {
                AppDelegate.shared.hud.dismiss(afterDelay: 0.5)
                self.tableView.reloadData()
            }
        }
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
    
    
    
    // MARK: -
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let indexPath = self.tableView.indexPathForSelectedRow {
            if segue.identifier == "ShowPosts" {
                let thread = self.board.threads.reversed()[indexPath.row]
                
                if let postsViewController = segue.destination as? PostsViewController {
                    postsViewController.thread      = thread
                    postsViewController.board       = board
                    postsViewController.bookmark    = self.bookmark
                    postsViewController.connection  = self.connection
                }
            }
        }
    }
    
    

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        if self.board != nil {
            return 1
        }
        return 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let board = self.board {
            return board.threads.count
        }
        return 0
    }


    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ThreadCell", for: indexPath) as! ThreadViewCell
        
        let thread = self.board.threads.reversed()[indexPath.row]

        cell.subjectTextField?.text     = thread.subject
        cell.nickTextField?.text        = thread.nick
        cell.repliesTextField?.text     = "\(thread.replies ?? 0) replies"
        
        if let date = thread.lastReplyDate ?? thread.editDate ?? thread.postDate {
            cell.dateTextField?.text = AppDelegate.dateTimeFormatter.string(from: date)
        }
        
        return cell
    }


    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
