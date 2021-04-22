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

    @Option(name: .shortAndLong, help: "Server listening port")
    var port: Int = 4871
    
    @Option(help: "Sqlite database file")
    var db: String = "\(FileManager.default.currentDirectoryPath)/wired3.db"
    
    @Option(help: "Server root files path")
    var root: String = "\(FileManager.default.currentDirectoryPath)/files/"
    
    @Option(help: "Server banner path")
    var banner: String = "\(FileManager.default.currentDirectoryPath)/banner.png"
    
    @Argument(help: "Path to XML specification file")
    var spec: String
    
    mutating func run() throws {
        App = AppController(specPath:spec, dbPath: db, rootPath: root, bannerPath: banner, port: port)
        
        App.start()
    }
}

Wired.main()
