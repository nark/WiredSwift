//
//  ConnectionsController.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 17/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit
import CoreData
import WiredSwift_iOS

public class ConnectionsController {
    public static let shared = ConnectionsController()
    
    public var bookmarks   = [Bookmark]()
    public var connections = [Bookmark:Connection]()
    
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
    }
}
