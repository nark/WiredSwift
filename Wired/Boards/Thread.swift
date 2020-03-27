//
//  Thread.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

public class Thread: ConnectionObject {
    public var subject:String!
    public var nick:String!
    
    public var board:Board!
    
    init(_ message: P7Message, board: Board, connection: ServerConnection) {
        super.init(connection)
        
        self.board = board
        
        if let p = message.string(forField: "wired.board.subject") {
            self.subject = p
        }
        
        if let p = message.string(forField: "wired.user.nick") {
            self.nick = p
        }

    }
}
