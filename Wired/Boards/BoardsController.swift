//
//  BoardsController.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let didStartLoadingBoards = Notification.Name("didStartLoadingBoards")
    
    static let didLoadBoards = Notification.Name("didLoadBoards")
    static let didLoadThreads = Notification.Name("didLoadThreads")
    static let didLoadPosts = Notification.Name("didLoadPosts")
}

public class BoardsController: ConnectionObject, ConnectionDelegate {
    public private(set) var boards:[Board] = []
    public private(set) var boardsByPath:[String:Board] = [:]
    
    public let queue = DispatchQueue(label: "fr.read-write.Wired.BoardsQueue")
    
    var loadingThread:BoardThread? = nil
    
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

        queue.async(flags: .barrier, execute: {
            board.threads = []
            
        })
        
        NotificationCenter.default.post(name: .didStartLoadingBoards, object: connection)
        
        _ = self.connection.send(message: message)
        
    }
    
    public func loadPosts(forThread thread: BoardThread) {
        let message = P7Message(withName: "wired.board.get_thread", spec: self.connection.spec)
        message.addParameter(field: "wired.board.thread", value: thread.uuid)
                
        queue.async(flags: .barrier, execute: {
            thread.posts        = []
            self.loadingThread  = thread
        })
        
        NotificationCenter.default.post(name: .didStartLoadingBoards, object: connection)
        
        _ = self.connection.send(message: message)
        
    }
    
    
    // MARK: -
    private func loadBoards() {
        let message = P7Message(withName: "wired.board.get_boards", spec: self.connection.spec)
        
        queue.async(flags: .barrier, execute: {
            self.boards = []
            self.boardsByPath = [String:Board]()
        })
        
        NotificationCenter.default.post(name: .didStartLoadingBoards, object: connection)
        
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
                
                queue.async(flags: .barrier, execute: {
                    if !board.hasParent {
                        self.boards.append(board)
                    } else {
                        if let parent = self.parentBoard(forPath: board.path) {
                            parent.boards.append(board)
                        }
                    }
                })
                
                boardsByPath[board.path] = board
            }
            else if message.name == "wired.board.board_list.done" {
                NotificationCenter.default.post(name: .didLoadBoards, object: connection)
            }
                
                
            else if message.name == "wired.board.thread_list" {
                if let path = message.string(forField: "wired.board.board") {
                    if let board = self.boardsByPath[path] {
                        queue.async(flags: .barrier, execute: {
                            let thread = BoardThread(message, board: board, connection: connection as! ServerConnection)
                            board.addThread(thread)
                        })
                    }
                }
            }
            else if message.name == "wired.board.thread_list.done" {
                NotificationCenter.default.post(name: .didLoadThreads, object: connection)
            }
            
            
            else if message.name == "wired.board.post_list" || message.name == "wired.board.thread" {
                if let thread = self.loadingThread {
                    let post = Post(message, board: thread.board, thread: thread, connection: connection as! ServerConnection)
                    
                    queue.async(flags: .barrier, execute: {
                        if thread.posts.isEmpty {
                            post.nick = thread.nick
                        }
                        
                        thread.posts.append(post)
                    })
                }
            }
            else if message.name == "wired.board.post_list.done" {
                queue.async(flags: .barrier, execute: {
                    self.loadingThread = nil
                })
                                
                NotificationCenter.default.post(name: .didLoadPosts, object: connection)
            }
        }
    }
    
    public func connectionDidReceiveError(connection: Connection, message: P7Message) {
        //semaphore.signal()
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
