//
//  AppController.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift


public let DEFAULT_PORT = 4875

public class AppController : DatabaseControllerDelegate {
    var rootPath:String
    var port:Int = DEFAULT_PORT
    var bannerPath:String
    
    var spec:P7Spec!
    
    var serverController:ServerController!
    
    var databaseURL:URL!
    var databaseController:DatabaseController!
    var usersController:UsersController!
    var chatsController:ChatsController!
    var filesController:FilesController!
    var indexController:IndexController!
    var transfersController:TransfersController!
    
    
    
    // MARK: - Public
    public init(specPath:String, dbPath:String, rootPath:String, bannerPath: String, port:Int = DEFAULT_PORT) {
        let specUrl = URL(fileURLWithPath: specPath)
        
        self.rootPath = rootPath
        self.port = port
        self.bannerPath = bannerPath
        self.databaseURL = URL(fileURLWithPath: dbPath)
        
        if let spec = P7Spec(withUrl: specUrl) {
            self.spec = spec
        }
    }
    

    
    public func start() {
        self.databaseController = DatabaseController(baseURL: self.databaseURL, spec: self.spec)
        self.databaseController.delegate = self
        
        self.filesController = FilesController(rootPath: self.rootPath)
        self.usersController = UsersController(databaseController: self.databaseController)
        self.chatsController = ChatsController(databaseController: self.databaseController)
        self.indexController = IndexController(databaseController: self.databaseController,
                                               filesController: self.filesController)
        
        self.transfersController = TransfersController(filesController: filesController)
        
        if !self.databaseController.initDatabase() {
            Logger.error("Error while initializing databasse")
        }
        
        self.chatsController.loadChats()
        self.indexController.indexFiles()
        
        self.serverController = ServerController(port: self.port, spec: self.spec)
        self.serverController.listen()
    }
    
    
    
    // MARK: - DatabaseControllerDelegate
    public func createTables() {
        self.usersController.createTables()
        self.chatsController.createTables()
        self.indexController.createTables()
    }
}
