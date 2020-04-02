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
    let hud = JGProgressHUD(style: .dark)
    //var chatViewController: ChatViewController? = nil
    
    var bookmarks = [Bookmark]()
    var connections = [Bookmark:Connection]()
    var chatViewControllers = [Connection:ChatViewController]()
    
     let reachability = try! Reachability()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let userProfileButton = UIBarButtonItem(image: UIImage(named: "Settings"), style: .plain, target: self, action: #selector(showUserProfile(_:)))
        //let userProfileButton = UIBarButtonItem(title: "Profile", style: .plain, target: self, action: #selector(showUserProfile(_:)))
        navigationItem.leftBarButtonItem = userProfileButton
        
        self.reloadBookmarks()

        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(insertNewObject(_:)))
        navigationItem.rightBarButtonItem = addButton
        
        hud.textLabel.text = "Loading"

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
            let bookmark = bookmarks[indexPath.row]
          
            let spec = P7Spec()
            let url = bookmark.url()
            
            let connection = Connection(withSpec: spec, delegate: self)
            connection.nick = UserDefaults.standard.string(forKey: "WSUserNick") ?? "Swift iOS"
            connection.status = UserDefaults.standard.string(forKey: "WSUserStatus") ?? "Around"
            
            if let b64string = UserDefaults.standard.image(forKey: "WSUserIcon")?.pngData()?.base64EncodedString() {
                connection.icon = b64string
            }
                
            self.hud.show(in: self.view)
            
            // perform  connect
            DispatchQueue.global().async {
                if connection.connect(withUrl: url) {
                    DispatchQueue.main.async {
                        self.hud.dismiss(afterDelay: 1.0)
                        
                        self.connections[bookmark] = connection
                                                
                        self.performSegue(withIdentifier: "showDetail", sender: self)
                        
                        if let split = self.splitViewController {
                            UIView.animate(withDuration: 0.3, animations: {
                                split.preferredDisplayMode = .primaryHidden
                            }, completion: nil)
                        }
                        
                        // update bookmark with server name
                        bookmark.name = connection.serverInfo.serverName
                        AppDelegate.shared.saveContext()
                        self.tableView.reloadRows(at: [indexPath], with: .none)
                    }
                    
                } else {
                    DispatchQueue.main.async {
                        self.hud.dismiss(afterDelay: 1.0)
                        // not connected
                        print(connection.socket.errors)
                        
                        let alertController = UIAlertController(title: "Connection Error", message:
                            "Enable to connect to \(bookmark.hostname!)", preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: "OK", style: .default))

                        self.present(alertController, animated: true, completion: nil)
                    }
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
            if let indexPath = tableView.indexPathForSelectedRow {
                let bookmark = bookmarks[indexPath.row]
                let controller = (segue.destination as! UINavigationController).topViewController as! ChatViewController
                
                controller.bookmark = bookmark
                controller.connection = connections[bookmark]
                self.chatViewControllers[controller.connection!] = controller
                controller.navigationItem.leftBarButtonItem = self.splitViewController?.displayModeButtonItem
                controller.navigationItem.leftItemsSupplementBackButton = true
            }
        }
    }
    
    


    // MARK: -
    
    public func reloadBookmarks() {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Bookmark")
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }
        
        let context = appDelegate.persistentContainer.viewContext
        
        do {
            let results = try context.fetch(fetchRequest)
            let bookmarks = results as! [Bookmark]
            
            self.bookmarks = bookmarks
            
        } catch let error as NSError {
            print("Could not fetch \(error)")
        }
        
        self.tableView.reloadData()
    }
    
    
    
    // MARK: -
    
    private func setupReachability() {
        self.reachability.whenReachable = { _ in

        }
        
        self.reachability.whenUnreachable = { _ in
            for b in self.bookmarks {
                if let connection = self.connections[b] {
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
           return bookmarks.count
       }

       override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
           let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as? BookmarkTableViewCell
           
           let bookmark = bookmarks[indexPath.row]
           let connection = self.connections[bookmark]
           
           cell?.nameLabel!.text = bookmark.name
           
           if connection != nil && connection?.isConnected() == true {
               cell?.statusImageView.image = UIImage(named: "ConnectionStatusConnected")
           } else {
               cell?.statusImageView.image = nil
           }
           
           return cell!
       }
       
       override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
           let bookmark = bookmarks[indexPath.row]
           
           if let connection = self.connections[bookmark] {
               if connection.isConnected() == true {
                   if let controller = self.chatViewControllers[connection] {
                       if UIDevice.current.userInterfaceIdiom == .pad {
                           if let split = splitViewController {
                               if let navController = split.viewControllers[1] as? UINavigationController {
                                   navController.viewControllers = [controller]
                                   UIView.animate(withDuration: 0.3, animations: {
                                       split.preferredDisplayMode = .primaryHidden
                                   }, completion: nil)
                               }
                           }
                       } else {
                           self.navigationController?.pushViewController(controller, animated: true)
                       }
                   }
               }
           } else {
               self.connect(self)
           }
       }

       override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
           // Return false if you do not want the specified item to be editable.
           return true
       }


       override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
           if editingStyle == .delete {
               let bookmark = bookmarks.remove(at: indexPath.row)
               
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
        if let controller = self.chatViewControllers[connection] {
            if let bookmark = controller.bookmark {
                self.connections.removeValue(forKey: bookmark)
                self.chatViewControllers.removeValue(forKey: connection)
                
                self.tableView.reloadData()
            }
        }
    }
    
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
    
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
}
