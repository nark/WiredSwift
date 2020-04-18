//
//  MasterViewController.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 31/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit
import CoreData
import WiredSwift_iOS
import JGProgressHUD
import Reachability


class BookmarksViewController: UITableViewController {
     let reachability = try! Reachability()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(shouldOpenNewConnection(_:)), name: .shouldOpenNewConnection, object: nil)

        let userProfileButton = UIBarButtonItem(image: UIImage(named: "Settings"), style: .plain, target: self, action: #selector(showUserProfile(_:)))
        //let userProfileButton = UIBarButtonItem(title: "Profile", style: .plain, target: self, action: #selector(showUserProfile(_:)))
        navigationItem.leftBarButtonItem = userProfileButton
        
        ConnectionsController.shared.reloadBookmarks()
        self.tableView.reloadData()

        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(insertNewObject(_:)))
        navigationItem.rightBarButtonItem = addButton

        if let split = self.splitViewController {
            if UIApplication.shared.statusBarOrientation == .portrait {
                UIView.animate(withDuration: 0.3, animations: {
                    split.preferredDisplayMode = .primaryOverlay
                }, completion: nil)
            }
        }
    }
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    // MARK: - @objc
    
    @objc func shouldOpenNewConnection(_ n: Notification) {
        self.performSegue(withIdentifier: "ShowBookmark", sender: self)
    }

    @objc func insertNewObject(_ sender: Any) {
        self.performSegue(withIdentifier: "ShowBookmark", sender: self)
    }
    
    @objc func showUserProfile(_ sender: Any) {
        self.performSegue(withIdentifier: "ShowProfile", sender: self)
    }
    
    @objc func showConnections() {
        if let split = self.splitViewController {
            if UIApplication.shared.statusBarOrientation == .portrait {
                UIView.animate(withDuration: 0.3, animations: {
                    split.preferredDisplayMode = .primaryOverlay
                }, completion: nil)
            }
        }
    }

    
    // MARK: - IBAction
    
    @IBAction func connect(_ sender: Any) {
        if let indexPath = tableView.indexPathForSelectedRow {
            let bookmark = ConnectionsController.shared.bookmarks[indexPath.row]
            
            AppDelegate.shared.connect(withBookmark: bookmark, inViewController: self, connectionDelegate: nil) {(connection) in
                if connection.isConnected() {
                    self.tableView.reloadRows(at: [indexPath], with: .none)
                    
                    self.dismiss(animated: true) { }
                }
            }
        }
    }

    
    
    // MARK: - Segues

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ShowBookmark" {
            let controller = (segue.destination as! UINavigationController).topViewController as! BookmarkViewController
            controller.masterViewController = self
        }
        else if segue.identifier == "showDetail" {
//            if let indexPath = tableView.indexPathForSelectedRow {
//                let bookmark = ConnectionsController.shared.bookmarks[indexPath.row]
//                let controller = (segue.destination as! UINavigationController).topViewController as! ChatViewController
//
//                controller.bookmark = bookmark
//                controller.connection = ConnectionsController.shared.connections[bookmark]
//                self.chatViewControllers[controller.connection!] = controller
//                controller.navigationItem.leftBarButtonItem = self.splitViewController?.displayModeButtonItem
//                controller.navigationItem.leftItemsSupplementBackButton = true
//            }
        }
    }
    
    
    
    
    
    // MARK: -
    
    private func select(_ bookmark:Bookmark) {
        //already connected
        if let connection = ConnectionsController.shared.connections[bookmark], connection.isConnected() == true {
            if connection.isConnected() == true {
                if let ctbc = AppDelegate.shared.window?.rootViewController as? ConnectionTabBarController {
                    ctbc.bookmark = bookmark
                    ctbc.connection = connection
                    
                    self.dismiss(animated: true) { }
                }
            }
        } else {
            // connect
            self.connect(self)
        }
    }

    
    private func setupReachability() {
        self.reachability.whenReachable = { _ in

        }
        
        self.reachability.whenUnreachable = { _ in
            for b in ConnectionsController.shared.bookmarks {
                if let connection = ConnectionsController.shared.connections[b] {
                    if connection.isConnected() {
                        connection.disconnect()
                    }
                }
            }
        }
        
        do {
            try self.reachability.startNotifier()
        } catch {

        }
    }
}





// MARK: - Table View

extension BookmarksViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
           return 1
       }

       override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
           return ConnectionsController.shared.bookmarks.count
       }

       override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
           let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as? BookmarkTableViewCell
           
           let bookmark = ConnectionsController.shared.bookmarks[indexPath.row]
           let connection = ConnectionsController.shared.connections[bookmark]
           
           cell?.nameLabel!.text = bookmark.name
           cell?.accessoryType = .none
        
           if connection != nil && connection?.isConnected() == true {
               cell?.statusImageView.image = UIImage(named: "ConnectionStatusConnected")
            
            if AppDelegate.shared.currentConnection == connection {
                cell?.accessoryType = .checkmark
            }
           } else {
               cell?.statusImageView.image = nil
           }
           
           return cell!
       }
              
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let bookmark = ConnectionsController.shared.bookmarks[indexPath.row]

        self.select(bookmark)
    }
    
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
       // Return false if you do not want the specified item to be editable.
       return true
    }


    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
       if editingStyle == .delete {
           let bookmark = ConnectionsController.shared.bookmarks.remove(at: indexPath.row)
           
           AppDelegate.shared.persistentContainer.viewContext.delete(bookmark)
           AppDelegate.shared.saveContext()
           
           tableView.deleteRows(at: [indexPath], with: .fade)
       } else if editingStyle == .insert {
           // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
       }
    }
}




extension BookmarksViewController: ConnectionDelegate {
    // MARK: -
    func connectionDisconnected(connection: Connection, error: Error?) {

    }
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {

    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
}
