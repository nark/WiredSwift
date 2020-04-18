//
//  ChatsViewController.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 17/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit
import WiredSwift_iOS

class ChatsViewController: UITableViewController {
    var chatViewControllers = [Connection:ChatViewController]()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        ConnectionsController.shared.reloadBookmarks()
    }
    
    var bookmark:Bookmark!
    var connection: Connection? {
        didSet {
            // Update the view.
            if let c = self.connection {
                print("ChatsViewController connection changed")
            } else {
                print("ChatsViewController connection is now nil")
            }
            
            self.tableView.reloadData()
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        if let connection = self.connection, connection.isConnected() {
            return 2
        }
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView.numberOfSections == 2 {
            if let connection = self.connection, connection.isConnected() {
                if section == 0 {
                    return 1
                }
                else if section == 1 {
                    return 0
                }
            }
        }
        
        return ConnectionsController.shared.bookmarks.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if tableView.numberOfSections == 2 {
            if section == 0 {
                return "CHATS"
            }
            else if section == 1 {
                return "PRIVATE MESSAGES"
            }
        }
        
        return "BOOKMARKS"
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatCell", for: indexPath)

        if tableView.numberOfSections == 2 {
            if indexPath.section == 0 {
                cell.textLabel?.text = "Public Chat"
                cell.detailTextLabel?.textColor = UIColor.lightGray
                cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 13.0)
            }
        }
        else {
            let bookmark = ConnectionsController.shared.bookmarks[indexPath.row]
            cell.textLabel?.text = bookmark.name
            cell.detailTextLabel?.text = ""
        }

        return cell
    }
    
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.numberOfSections == 2 {
            if indexPath.section == 0 {
                if let c = self.connection, let chatViewController = self.chatViewControllers[c] {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        if let split = splitViewController {
                            if let navController = split.viewControllers[1] as? UINavigationController {
                                navController.pushViewController(chatViewController, animated: false)
                            }
                        }
                    } else {
                        self.navigationController?.pushViewController(chatViewController, animated: true)
                    }
                } else {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        if let split = splitViewController {
                            if let navController = split.viewControllers[1] as? UINavigationController {
                                if let chatViewController = navController.topViewController as? ChatViewController {
                                    chatViewController.bookmark     = self.bookmark
                                    chatViewController.connection   = self.connection
                                    
                                    self.chatViewControllers[self.connection!] = chatViewController
                                }
                            }
                        }
                    } else {
                        self.performSegue(withIdentifier: "showChat", sender: self)
                    }
                }
            }
        } else {
            // connect
            let bookmark = ConnectionsController.shared.bookmarks[indexPath.row]
            
            AppDelegate.shared.connect(withBookmark: bookmark, inViewController: self, connectionDelegate: nil) {(connection) in
                if connection.isConnected() {
                    //self.tableView.reloadRows(at: [indexPath], with: .none)
                }
            }
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - Segues

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showChat" {
            if let controller = segue.destination as? ChatViewController {
                controller.bookmark     = self.bookmark
                controller.connection   = self.connection
                
                self.chatViewControllers[self.connection!] = controller
                
                if UIDevice.current.userInterfaceIdiom == .pad {
                    if let split = splitViewController {
                        print("split OK")
                        //split.showDetailViewController(controller, sender: sender)
                        controller.becomeFirstResponder()
                        
//                        if let navController = split.viewControllers[1] as? UINavigationController {
//                            print("navController set viewControllers")
//                            navController.viewControllers = [controller]
//                        }
                    }
                }
            }
        }
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
