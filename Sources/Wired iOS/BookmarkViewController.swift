//
//  BookamrkViewController.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 31/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit
import CoreData
import KeychainAccess
import WiredSwift_iOS

class BookmarkViewController: UITableViewController {
    @IBOutlet var addressTextField:     UITextField!
    @IBOutlet var loginTextField:       UITextField!
    @IBOutlet var passwordTextField:    UITextField!
    
    public var masterViewController:BookmarksViewController!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        //self.navigationItem.rightBarButtonItem = self.editButtonItem
        addressTextField.becomeFirstResponder()
    }
    
    
    // MARK: -
    
    @IBAction func cancel(_ sender: Any) {
        self.dismiss(animated: true) {  }
    }
    
    @IBAction func ok(_ sender: Any) {
        // validate
        if (self.addressTextField.text == nil || self.addressTextField.text!.isEmpty) ||
            (self.loginTextField.text == nil || self.loginTextField.text!.isEmpty) {
            return
        }
        
        let context = AppDelegate.shared.persistentContainer.viewContext
        let bookmark:Bookmark = NSEntityDescription.insertNewObject(
            forEntityName: "Bookmark", into: context) as! Bookmark

        bookmark.name = self.addressTextField.text
        bookmark.hostname = self.addressTextField.text
        bookmark.login = self.loginTextField.text
        
        let keychain = Keychain(server: "wired://\(bookmark.hostname!)", protocolType: .irc)
        keychain[bookmark.login!] = self.passwordTextField.text
        
        AppDelegate.shared.saveContext()
        
        //self.masterViewController.reloadBookmarks()
        
        self.dismiss(animated: true) {  }
    }
    

}
