//
//  AppController.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import Configuration
import WiredSwift


public let DEFAULT_PORT = 4871
private let defaultWelcomeBoardPath = "Welcome"
private let defaultWelcomeThreadSubject = "Welcome to Wired Server 3"
private let defaultWelcomeThreadBody = "You are running Wired Server version 3.x, this is an early alpha version, you are pleased to report any issue at : https://github.com/nark/WiredSwift/issues"





public class AppController {
    var workingDirectoryPath:String
    var rootPath:String
    var configPath:String
    
    var spec:P7Spec!
    
    var serverController:ServerController!
    
    var databaseURL:URL!
    var databaseController:DatabaseController!
    var clientsController:ClientsController!
    var usersController:UsersController!
    var chatsController:ChatsController!
    var boardsController:BoardsController!
    var filesController:FilesController!
    var indexController:IndexController!
    var transfersController:TransfersController!
    
    var config:Config
    
    // MARK: - Public
    public init(specPath:String, dbPath:String, rootPath:String, configPath: String, workingDirectoryPath: String) {
        let specUrl = URL(fileURLWithPath: specPath)
        
        self.workingDirectoryPath = workingDirectoryPath
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
        } else {
            Logger.fatal("Cannot load spec file at path \(specPath)")
            exit(-1)
        }
    }
    

    
    public func start() {
        self.databaseController = DatabaseController(baseURL: self.databaseURL, spec: self.spec)

        self.clientsController = ClientsController()
        self.filesController = FilesController(rootPath: self.rootPath)
        self.usersController = UsersController(databaseController: self.databaseController)
        self.chatsController = ChatsController(databaseController: self.databaseController)
        self.boardsController = BoardsController(databasePath: self.databaseURL.path)
        self.indexController = IndexController(databaseController: self.databaseController,
                                               filesController: self.filesController)
        
        self.transfersController = TransfersController(filesController: filesController)
        
        if !self.databaseController.initDatabase() {
            Logger.error("Error while initializing database")
        }

        // Seed initial data (only on first run — no-op if data already exists)
        self.usersController.seedDefaultDataIfNeeded()
        self.chatsController.seedDefaultDataIfNeeded()

        // Legacy schema migrations (no-op on fresh GRDB databases)
        self.usersController.migrateLegacyPrivilegesSchemaIfNeeded()
        self.usersController.backfillStableIdentitiesIfNeeded()

        self.chatsController.loadChats()
        self.bootstrapDefaultContentIfNeeded()
        self.indexController.indexFiles()
        
        let port = resolvedServerPort()

        self.serverController = ServerController(port: port, spec: self.spec)
        self.serverController.listen()
    }

    private func resolvedServerPort() -> Int {
        if let value = self.config["server", "port"] as? Int, (1...65535).contains(value) {
            return value
        }

        if let raw = self.config["server", "port"] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Int(trimmed), (1...65535).contains(parsed) {
                return parsed
            }
            Logger.warning("Invalid server.port value '\(raw)'. Falling back to default port \(DEFAULT_PORT).")
            return DEFAULT_PORT
        }

        return DEFAULT_PORT
    }

    private func bootstrapDefaultContentIfNeeded() {
        if self.boardsController.getBoardInfo(path: defaultWelcomeBoardPath) == nil {
            _ = self.boardsController.addBoard(
                path: defaultWelcomeBoardPath,
                owner: "admin",
                group: "admin",
                ownerRead: true,
                ownerWrite: true,
                groupRead: true,
                groupWrite: true,
                everyoneRead: true,
                everyoneWrite: true
            )
        }

        let existingThreads = self.boardsController.getThreads(forBoard: defaultWelcomeBoardPath)
        let hasWelcomeThread = existingThreads.contains {
            $0.subject == defaultWelcomeThreadSubject && $0.text == defaultWelcomeThreadBody
        }

        if !hasWelcomeThread {
            _ = self.boardsController.addThread(
                board: defaultWelcomeBoardPath,
                subject: defaultWelcomeThreadSubject,
                text: defaultWelcomeThreadBody,
                nick: "Wired Server",
                login: "admin",
                icon: nil
            )
        }
    }
    
    
    
}
