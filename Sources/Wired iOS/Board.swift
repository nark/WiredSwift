//
//  Board.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation
import WiredSwift_iOS
import LNZTreeView

public class Board: ConnectionObject, TreeNodeProtocol {
    public var name:String!
    public var path:String!
    
    public var readable:Bool!
    public var writable:Bool!
    
    public var boards:[Board]   = []
    
    public var threads:[BoardThread] = []
    public var threadsByUUID:[String:BoardThread] = [:]
    
    init(_ message: P7Message, connection: Connection) {
        super.init(connection)
        
        if let p = message.string(forField: "wired.board.board") {
            self.path = p
        }
        
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
    
    public func addThread(_ thread:BoardThread) {
        self.threads.append(thread)
        
        //self.threadsByUUID[thread.uuid] = thread
    }
    
    
    // MARK: - TreeNodeProtocol
    
    public var identifier: String {
        return self.path
    }
    
    public var isExpandable: Bool {
        return boards.count > 0
    }
}
