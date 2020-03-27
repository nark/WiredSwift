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
    static let didLoadThreads = Notification.Name("didLoadThreads")
    static let didLoadPosts = Notification.Name("didLoadPosts")
}

public class BoardsController: ConnectionObject, ConnectionDelegate {
    public private(set) var boards:[Board] = []
    public private(set) var boardsByPath:[String:Board] = [:]
    
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
    
    public func loadThreads(forBoard board: Board) {
        let message = P7Message(withName: "wired.board.get_threads", spec: self.connection.spec)
        message.addParameter(field: "wired.board.board", value: board.path)
        
        board.threads = []
        
        _ = self.connection.send(message: message)
        
    }
    
    public func loadPosts(forThread thread: Thread) {
        let message = P7Message(withName: "wired.board.get_thread", spec: self.connection.spec)
        message.addParameter(field: "wired.board.thread", value: thread.uuid)
        
        thread.posts = []
        
        _ = self.connection.send(message: message)
        
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
                
                boardsByPath[board.path] = board
            }
            else if message.name == "wired.board.board_list.done" {
                NotificationCenter.default.post(name: .didLoadBoards, object: connection)
            }
                
                
            else if message.name == "wired.board.thread_list" {
                if let path = message.string(forField: "wired.board.board") {
                    if let board = self.boardsByPath[path] {
                        let thread = Thread(message, board: board, connection: connection as! ServerConnection)
                        board.addThread(thread)
                    }
                }
            }
            else if message.name == "wired.board.thread_list.done" {
                NotificationCenter.default.post(name: .didLoadThreads, object: connection)
            }
            
            
            else if message.name == "wired.board.post_list" {
                if let path = message.string(forField: "wired.board.board") {
                    if let board = self.boardsByPath[path] {
                        if let uuid = message.string(forField: "wired.board.thread") {
                            if let thread = board.threadsByUUID[uuid] {
                                let post = Post(message, board: board, thread: thread, connection: connection as! ServerConnection)
                                print(post)
                                thread.posts.append(post)
                            }
                        }
                    }
                }
            }
            else if message.name == "wired.board.post_list.done" {
                NotificationCenter.default.post(name: .didLoadThreads, object: connection)
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
