//
//  Board.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

public class Board: ConnectionObject {
    public var name:String!
    public var path:String!
    
    public var readable:Bool!
    public var writable:Bool!
    
    public var boards:[Board]   = []
    public var threads:[Thread] = []
    
    init(_ message: P7Message, connection: ServerConnection) {
        super.init(connection)
        
        if let p = message.string(forField: "wired.board.board") {
            self.path = p
        }
        
        print(self.path)
        
        self.name = (self.path as NSString).lastPathComponent
        
        if let r = message.bool(forField: "wired.board.readable") {
            self.readable = r
        }
        if let w = message.bool(forField: "wired.board.writable") {
            self.writable = w
        }
    }
    
    public var hasParent:Bool {
        return self.path.split(separator: "/").count > 1
    }
}
