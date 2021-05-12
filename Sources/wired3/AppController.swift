//
//  AppController.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import Configuration
import WiredSwift
import NIO


public let DEFAULT_PORT = 4871





public class AppController : DatabaseControllerDelegate {
    var rootPath:String
    var configPath:String
    
    var spec:P7Spec!
    
    var serverController:ServerController!
    
    var databaseURL:URL!
    var databaseController:DatabaseController!
    var clientsController:ClientsController!
    var usersController:UsersController!
    var chatsController:ChatsController!
    var filesController:FilesController!
    var indexController:IndexController!
    var transfersController:TransfersController!
    
    var config:Config
    
    // MARK: - Public
    public init(specPath:String, dbPath:String, rootPath:String, configPath: String) {
        let specUrl = URL(fileURLWithPath: specPath)

        self.rootPath = rootPath
        self.configPath = configPath
        self.databaseURL = URL(fileURLWithPath: dbPath)
        self.config = Config(withPath: configPath)

        if !self.config.load() {
            Logger.fatal("Cannot load config file at path \(configPath)")
            exit(-1)
        }
        
        if let spec = P7Spec(withUrl: specUrl) {
            self.spec = spec
        }
    }
    

    
    public func start() {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        
        self.databaseController = DatabaseController(baseURL: self.databaseURL, spec: self.spec, eventLoopGroup: eventLoopGroup)
        self.databaseController.delegate = self
        
        self.clientsController = ClientsController()
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
        
        let port = self.config["server", "port"] as? Int
        
        self.serverController = ServerController(port: port ?? DEFAULT_PORT, spec: self.spec, eventLoopGroup: eventLoopGroup)
        self.serverController.listen()
    }
    
    
    
    // MARK: - DatabaseControllerDelegate
    public func createTables() {
        self.usersController.createTables()
        self.chatsController.createTables()
        self.indexController.createTables()
    }
}
