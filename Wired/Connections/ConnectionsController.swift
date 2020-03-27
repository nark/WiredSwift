//
//  ConnectionsController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let didAddNewConnection = Notification.Name("didAddNewConnection")
    static let didRemoveConnection = Notification.Name("didRemoveConnection")
    
    static let shouldSelectConversation = Notification.Name("shouldSelectConversation")
}

class ConnectionsController {
    public static let shared = ConnectionsController()
    
    var connections:[ServerConnection] = []
    var usersControllers:[UsersController] = []
    var filesControllers:[FilesController] = []
    var boardsControllers:[BoardsController] = []
    
    
    private init() {

    }
    

    
    
    
    // MARK: - Connections
    
    public func addConnection(_ connection: ServerConnection) {
        if connections.index(of: connection) == nil {
            connections.append(connection)
            
            NotificationCenter.default.post(name: .didAddNewConnection, object: connection, userInfo: nil)
        }
    }
    
    public func addConnection(withBookmark bookmark: Bookmark) {

    }
    
    
    public func removeConnection(_ connection: ServerConnection) {
        if let i = connections.index(of: connection) {
            connections.remove(at: i)
            
            NotificationCenter.default.post(name: .didRemoveConnection, object: connection, userInfo: nil)
        }
    }
    
    
    
    // MARK: - Bookmarks
    
    public func bookmarks() -> [Bookmark] {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Bookmark")
        
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            return []
        }
        
        let context = appDelegate.persistentContainer.viewContext
        
        do {
            let results = try context.fetch(fetchRequest)
            let bookmarks = results as! [Bookmark]
            
            return bookmarks
            
        } catch let error as NSError {
            print("Could not fetch \(error)")
        }
        
        return []
    }
    
    
    public func removeBookmark(_ bookmark:Bookmark) {
        AppDelegate.shared.persistentContainer.viewContext.delete(bookmark)
    }
    
    
//    public func connectBookmark(_ bookmark:Bookmark) {
//        // handle already connected ?
//        if let cwc = AppDelegate.windowController(forBookmark: bookmark) {
//            if let tabGroup = cwc.window?.tabGroup {
//                tabGroup.selectedWindow = cwc.window
//                return
//            }
//        }
//        
//        print("no cwc")
//        
//        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: Bundle.main)
//        if let connectController = storyboard.instantiateController(withIdentifier: "ConnectWindowController") as? NSWindowController {
//            connectController.showWindow(self)
//            
//            if let connectController = connectController.contentViewController as? ConnectController {
//                connectController.connect(withBookmark: bookmark)
//            }
//        }
//    }
    
    
    
    // MARK: - Messages
    
    public func conversations() -> [Conversation] {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Conversation")
        
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            return []
        }
        
        let context = appDelegate.persistentContainer.viewContext
        
        do {
            let results = try context.fetch(fetchRequest)
            let conversations = results as! [Conversation]
            
            return conversations
            
        } catch let error as NSError {
            print("Could not fetch \(error)")
        }
        
        return []
    }
    
    
    public func conversation(withNick nick: String, onConnection connection:ServerConnection) -> Conversation? {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Conversation")
        fetchRequest.predicate = NSPredicate(format: "nick == %@ AND uri == %@", nick, connection.URI)
        fetchRequest.fetchLimit = 1
        
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            return nil
        }
        
        let context = appDelegate.persistentContainer.viewContext
        
        do {
            let results = try context.fetch(fetchRequest)
            if let r = results.first, let conversation = results.first as? Conversation {
                return conversation
            }
            
        } catch let error as NSError {
            print("Could not fetch \(error)")
        }
        
        return nil
    }
    
    
    public func removeConversation(_ conversation:Conversation) {
        AppDelegate.shared.persistentContainer.viewContext.delete(conversation)
    }
    
    
    // MARK: -
    public func usersController(forConnection connection:ServerConnection) -> UsersController {
        var usersController:UsersController? = nil
        
        let exists = usersControllers.contains { (fc) -> Bool in
            if fc.connection == connection {
                usersController = fc
            }
            return fc.connection == connection
        }
        
        if !exists {
            usersController = UsersController(connection)
            usersControllers.append(usersController!)
        }
        
        return usersController!
    }
    
    
    public func filesController(forConnection connection:ServerConnection) -> FilesController {
        var filesController:FilesController? = nil
        
        let exists = filesControllers.contains { (fc) -> Bool in
            if fc.connection == connection {
                filesController = fc
            }
            return fc.connection == connection
        }
        
        if !exists {
            filesController = FilesController(connection)
            filesControllers.append(filesController!)
        }
        
        return filesController!
    }
    
    
    public func boardsController(forConnection connection:ServerConnection) -> BoardsController {
           var boardsController:BoardsController? = nil
           
           let exists = boardsControllers.contains { (fc) -> Bool in
               if fc.connection == connection {
                   boardsController = fc
               }
               return fc.connection == connection
           }
           
           if !exists {
               boardsController = BoardsController(connection)
               boardsControllers.append(boardsController!)
           }
           
           return boardsController!
       }
}
