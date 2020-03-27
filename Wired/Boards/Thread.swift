//
//  Thread.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

public class Thread: ConnectionObject {
    public var uuid:String!
    public var subject:String!
    public var nick:String!
    public var replies:Int!
    public var postDate:Date!
    public var editDate:Date!
    public var lastReplyDate:Date!
    public var board:Board!
    
    init(_ message: P7Message, board: Board, connection: ServerConnection) {
        super.init(connection)
        
        self.board = board
        
        if let p = message.string(forField: "wired.board.thread") {
            self.uuid = p
        }
        
        if let p = message.string(forField: "wired.board.subject") {
            self.subject = p
        }
        
        if let p = message.string(forField: "wired.user.nick") {
            self.nick = p
        }
        
        if let p = message.date(forField: "wired.board.post_date") {
            self.postDate = p
        }
        
        if let p = message.date(forField: "wired.board.edit_date") {
            self.editDate = p
        }
        
        if let p = message.date(forField: "wired.board.latest_reply_date") {
            self.lastReplyDate = p
        }
        
        if let p = message.uint32(forField: "wired.board.replies") {
            self.replies = Int(p)
        }

    }
}
