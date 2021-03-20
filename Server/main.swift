//
//  main.swift
//  Server
//
//  Created by Rafael Warnault on 19/03/2021.
//

import Foundation
import ArgumentParser
import WiredSwift


struct Wired: ParsableCommand {
    @Flag(help: "Enable debug mode")
    var debugMode = false

    
    @Option(name: .shortAndLong, help: "Server listening port")
    var port: Int = 4871

    
    @Option(help: "Sqlite database file")
    var dbPath: String = "\(FileManager.default.currentDirectoryPath)/wired3.db"

    
    mutating func run() throws {
        let appController = AppController(dbPath: dbPath, port: port)
        
        appController.start()
    }
}

Wired.main()
