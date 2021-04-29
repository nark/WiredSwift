//
//  main.swift
//  Server
//
//  Created by Rafael Warnault on 19/03/2021.
//

import Foundation
import ArgumentParser
import WiredSwift

public var App:AppController!

struct Wired: ParsableCommand {
    @Flag(help: "Enable debug mode")
    var debugMode = false

    @Option(help: "Sqlite database file")
    var db: String = "\(FileManager.default.currentDirectoryPath)/wired3.db"
    
    @Option(help: "Server root files path")
    var root: String = "\(FileManager.default.currentDirectoryPath)/files/"
    
    @Option(help: "Server config file path (.ini)")
    var config: String = "config.ini"
    
    @Argument(help: "Path to XML specification file")
    var spec: String = "wired.xml"
    
    mutating func run() throws {
        App = AppController(specPath:spec, dbPath: db, rootPath: root, configPath: config)
        
        App.start()
    }
}

Wired.main()
