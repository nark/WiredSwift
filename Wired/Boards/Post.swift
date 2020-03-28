//
//  Thread.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

public class Post: ConnectionObject {
    public var uuid:String!
    public var text:String!
    public var nick:String!
    public var postDate:Date!
    public var editDate:Date!
    public var icon:NSImage!
    
    public var board:Board!
    public var thread:Thread!
    
    init(_ message: P7Message, board: Board, thread:Thread, connection: ServerConnection) {
        super.init(connection)
        
        self.board  = board
        self.thread = thread
        
        if let p = message.string(forField: "wired.board.thread") {
            self.uuid = p
        }
        
        if let p = message.string(forField: "wired.board.text") {
            self.text = p
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
        
        if let data = message.data(forField: "wired.user.icon") {
//            if let base64ImageString = data.base64EncodedData() {
//                if let data = Data(base64Encoded: base64ImageString, options: .ignoreUnknownCharacters) {
                    self.icon = NSImage(data: data)
//                }
//            }
        }
    }
}
