//
//  BoardsController.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let didLoadBoards = Notification.Name("didLoadBoards")
}

public class BoardsController: ConnectionObject, ConnectionDelegate {
    public private(set) var boards:[Board] = []
    
    public override init(_ connection: ServerConnection) {
        super.init(connection)
        
        self.connection.addDelegate(self)
    }
    
    
    public func loadBoard(withPath path:String? = "/") {
        if path == "/" {
            self.loadBoards()
        } else {
            
        }
    }
    
    
    // MARK: -
    private func loadBoards() {
        let message = P7Message(withName: "wired.board.get_boards", spec: self.connection.spec)
        
        _ = self.connection.send(message: message)
    }
    
    // MARK: -
    
    public func connectionDidConnect(connection: Connection) {
        
    }
    
    public func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    public func connectionDisconnected(connection: Connection, error: Error?) {
        
    }
    
    public func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if connection == self.connection {
            if message.name == "wired.board.board_list" {
                let board = Board(message, connection: connection as! ServerConnection)
                
                if !board.hasParent {
                    boards.append(board)
                } else {
                    if let parent = self.parentBoard(forPath: board.path) {
                        parent.boards.append(board)
                    }
                }
            }
            else if message.name == "wired.board.board_list.done" {
                NotificationCenter.default.post(name: .didLoadBoards, object: connection)
            }
        }
    }
    
    public func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
    
    
    // MARK: -
    
    private func parentBoard(forPath path:String) -> Board? {
        for parent in self.boards {
            let parentPath = (path as NSString).deletingLastPathComponent
            if parent.path == parentPath {
                return parent
            }
        }
        return nil
    }
}
