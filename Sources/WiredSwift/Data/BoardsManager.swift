//
//  BoardsManager.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 01/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation


/// Manages all boards, threads and posts for a Wired server.
/// Storage is in-memory; persist `boards`, `threads` and `posts`
/// externally if needed.
public class BoardsManager {

    // MARK: - Storage

    private let lock = NSLock()

    /// All boards indexed by path.
    public private(set) var boards: [String: WiredBoard] = [:]

    /// All threads indexed by UUID.
    public private(set) var threads: [String: WiredThread] = [:]

    /// All posts indexed by UUID.
    public private(set) var posts: [String: WiredPost] = [:]

    /// Maps board path -> ordered list of thread UUIDs.
    private var boardThreads: [String: [String]] = [:]

    public init() {}

    // MARK: - Boards

    /// Returns all boards readable by the given user/group, sorted by path.
    public func getBoards(forUser user: String, group: String) -> [WiredBoard] {
        return withLock {
            boards.values
                .filter { $0.canRead(user: user, group: group) }
                .sorted { $0.path < $1.path }
        }
    }

    /// Creates a new board. Returns nil if a board at that path already exists.
    @discardableResult
    public func addBoard(path: String,
                         owner: String,
                         group: String,
                         ownerRead: Bool,
                         ownerWrite: Bool,
                         groupRead: Bool,
                         groupWrite: Bool,
                         everyoneRead: Bool,
                         everyoneWrite: Bool) -> WiredBoard? {
        return withLock {
            guard boards[path] == nil else { return nil }
            let board = WiredBoard(path: path,
                                   owner: owner,
                                   group: group,
                                   ownerRead: ownerRead,
                                   ownerWrite: ownerWrite,
                                   groupRead: groupRead,
                                   groupWrite: groupWrite,
                                   everyoneRead: everyoneRead,
                                   everyoneWrite: everyoneWrite)
            boards[path] = board
            boardThreads[path] = []
            return board
        }
    }

    /// Deletes a board and all its threads and posts.
    @discardableResult
    public func deleteBoard(path: String) -> Bool {
        return withLock {
            guard boards[path] != nil else { return false }
            boards.removeValue(forKey: path)
            if let uuids = boardThreads.removeValue(forKey: path) {
                for uuid in uuids {
                    if let thread = threads.removeValue(forKey: uuid) {
                        for post in thread.posts {
                            posts.removeValue(forKey: post.uuid)
                        }
                    }
                }
            }
            return true
        }
    }

    /// Renames a board (updates path and all child thread references).
    @discardableResult
    public func renameBoard(path: String, newPath: String) -> Bool {
        return withLock {
            guard let board = boards.removeValue(forKey: path) else { return false }
            board.path = newPath
            boards[newPath] = board
            if let uuids = boardThreads.removeValue(forKey: path) {
                boardThreads[newPath] = uuids
                for uuid in uuids {
                    threads[uuid]?.board = newPath
                }
            }
            return true
        }
    }

    /// Moves a board to a new path (same as rename in flat storage).
    @discardableResult
    public func moveBoard(path: String, newPath: String) -> Bool {
        return renameBoard(path: path, newPath: newPath)
    }

    /// Returns the board info for the given path.
    public func getBoardInfo(path: String) -> WiredBoard? {
        return withLock { boards[path] }
    }

    /// Updates the permissions of an existing board.
    @discardableResult
    public func setBoardInfo(path: String,
                             owner: String,
                             group: String,
                             ownerRead: Bool,
                             ownerWrite: Bool,
                             groupRead: Bool,
                             groupWrite: Bool,
                             everyoneRead: Bool,
                             everyoneWrite: Bool) -> Bool {
        return withLock {
            guard let board = boards[path] else { return false }
            board.owner        = owner
            board.group        = group
            board.ownerRead    = ownerRead
            board.ownerWrite   = ownerWrite
            board.groupRead    = groupRead
            board.groupWrite   = groupWrite
            board.everyoneRead = everyoneRead
            board.everyoneWrite = everyoneWrite
            return true
        }
    }

    // MARK: - Threads

    /// Returns all threads for a board in insertion order.
    public func getThreads(forBoard boardPath: String) -> [WiredThread] {
        return withLock {
            guard let uuids = boardThreads[boardPath] else { return [] }
            return uuids.compactMap { threads[$0] }
        }
    }

    /// Returns a single thread by UUID.
    public func getThread(uuid: String) -> WiredThread? {
        return withLock { threads[uuid] }
    }

    /// Creates a new thread. Returns nil if the board does not exist.
    @discardableResult
    public func addThread(board: String,
                          subject: String,
                          text: String,
                          nick: String,
                          login: String,
                          icon: Data? = nil) -> WiredThread? {
        return withLock {
            guard boards[board] != nil else { return nil }
            let uuid = UUID().uuidString.lowercased()
            let thread = WiredThread(uuid: uuid,
                                     board: board,
                                     subject: subject,
                                     text: text,
                                     nick: nick,
                                     login: login,
                                     postDate: Date(),
                                     icon: icon)
            threads[uuid] = thread
            boardThreads[board, default: []].append(uuid)
            return thread
        }
    }

    /// Edits the subject and text of an existing thread.
    @discardableResult
    public func editThread(uuid: String, subject: String, text: String) -> WiredThread? {
        return withLock {
            guard let thread = threads[uuid] else { return nil }
            thread.subject  = subject
            thread.text     = text
            thread.editDate = Date()
            return thread
        }
    }

    /// Moves a thread to another board.
    @discardableResult
    public func moveThread(uuid: String, toBoard: String) -> WiredThread? {
        return withLock {
            guard let thread = threads[uuid], boards[toBoard] != nil else { return nil }
            boardThreads[thread.board]?.removeAll { $0 == uuid }
            boardThreads[toBoard, default: []].append(uuid)
            thread.board = toBoard
            return thread
        }
    }

    /// Deletes a thread and all its posts.
    @discardableResult
    public func deleteThread(uuid: String) -> Bool {
        return withLock {
            guard let thread = threads.removeValue(forKey: uuid) else { return false }
            boardThreads[thread.board]?.removeAll { $0 == uuid }
            for post in thread.posts {
                posts.removeValue(forKey: post.uuid)
            }
            return true
        }
    }

    // MARK: - Posts

    /// Returns all posts for a thread in insertion order.
    public func getPosts(forThread threadUUID: String) -> [WiredPost] {
        return withLock { threads[threadUUID]?.posts ?? [] }
    }

    /// Adds a reply post to an existing thread.
    @discardableResult
    public func addPost(threadUUID: String,
                        text: String,
                        nick: String,
                        login: String,
                        icon: Data? = nil) -> WiredPost? {
        return withLock {
            guard let thread = threads[threadUUID] else { return nil }
            let uuid = UUID().uuidString.lowercased()
            let post = WiredPost(uuid: uuid,
                                 thread: threadUUID,
                                 text: text,
                                 nick: nick,
                                 login: login,
                                 postDate: Date(),
                                 icon: icon)
            posts[uuid] = post
            thread.posts.append(post)
            return post
        }
    }

    /// Edits the text of an existing post.
    @discardableResult
    public func editPost(uuid: String, text: String) -> WiredPost? {
        return withLock {
            guard let post = posts[uuid] else { return nil }
            post.text     = text
            post.editDate = Date()
            return post
        }
    }

    /// Deletes a post.
    @discardableResult
    public func deletePost(uuid: String) -> Bool {
        return withLock {
            guard let post = posts.removeValue(forKey: uuid) else { return false }
            threads[post.thread]?.posts.removeAll { $0.uuid == uuid }
            return true
        }
    }

    // MARK: - Protocol message handling

    /// Handles an incoming P7Message from a client.
    /// Returns an array of reply messages to send back (in order).
    public func handle(message: P7Message,
                        user: String,
                        group: String,
                        nick: String,
                        icon: Data?) -> [P7Message] {
        switch message.name {

        case "wired.board.get_boards":
            return replyBoards(forUser: user, group: group, spec: message.spec)

        case "wired.board.get_threads":
            guard let boardPath = message.string(forField: "wired.board.board") else { return [] }
            return replyThreads(forBoard: boardPath, user: user, group: group, spec: message.spec)

        case "wired.board.get_thread":
            guard let uuid = message.uuid(forField: "wired.board.thread") else { return [] }
            return replyThread(uuid: uuid, spec: message.spec)

        case "wired.board.add_board":
            return handleAddBoard(message: message, user: user, group: group, spec: message.spec)

        case "wired.board.delete_board":
            return handleDeleteBoard(message: message, spec: message.spec)

        case "wired.board.rename_board":
            return handleRenameBoard(message: message, spec: message.spec)

        case "wired.board.move_board":
            return handleMoveBoard(message: message, spec: message.spec)

        case "wired.board.get_board_info":
            return handleGetBoardInfo(message: message, spec: message.spec)

        case "wired.board.set_board_info":
            return handleSetBoardInfo(message: message, spec: message.spec)

        case "wired.board.add_thread":
            return handleAddThread(message: message, user: user, group: group,
                                   nick: nick, icon: icon, spec: message.spec)

        case "wired.board.edit_thread":
            return handleEditThread(message: message, spec: message.spec)

        case "wired.board.move_thread":
            return handleMoveThread(message: message, spec: message.spec)

        case "wired.board.delete_thread":
            return handleDeleteThread(message: message, spec: message.spec)

        case "wired.board.add_post":
            return handleAddPost(message: message, user: user, nick: nick,
                                 icon: icon, spec: message.spec)

        case "wired.board.edit_post":
            return handleEditPost(message: message, spec: message.spec)

        case "wired.board.delete_post":
            return handleDeletePost(message: message, spec: message.spec)

        default:
            return []
        }
    }

    // MARK: - Reply builders

    private func replyBoards(forUser user: String, group: String, spec: P7Spec) -> [P7Message] {
        var messages: [P7Message] = []
        for board in getBoards(forUser: user, group: group) {
            let m = P7Message(withName: "wired.board.board_list", spec: spec)
            m.addParameter(field: "wired.board.board",    value: board.path)
            m.addParameter(field: "wired.board.readable", value: board.canRead(user: user, group: group))
            m.addParameter(field: "wired.board.writable", value: board.canWrite(user: user, group: group))
            messages.append(m)
        }
        messages.append(P7Message(withName: "wired.board.board_list.done", spec: spec))
        return messages
    }

    private func replyThreads(forBoard boardPath: String, user: String, group: String, spec: P7Spec) -> [P7Message] {
        var messages: [P7Message] = []
        for thread in getThreads(forBoard: boardPath) {
            let m = P7Message(withName: "wired.board.thread_list", spec: spec)
            m.addParameter(field: "wired.board.board",             value: thread.board)
            m.addParameter(field: "wired.board.thread",            value: thread.uuid)
            m.addParameter(field: "wired.board.subject",           value: thread.subject)
            m.addParameter(field: "wired.user.nick",               value: thread.nick)
            m.addParameter(field: "wired.board.post_date",         value: thread.postDate)
            m.addParameter(field: "wired.board.replies",           value: UInt32(thread.replies))
            m.addParameter(field: "wired.board.own_thread",        value: thread.login == user)
            if let editDate = thread.editDate {
                m.addParameter(field: "wired.board.edit_date", value: editDate)
            }
            if let latestUUID = thread.latestReplyUUID {
                m.addParameter(field: "wired.board.latest_reply", value: latestUUID)
            }
            if let latestDate = thread.latestReplyDate {
                m.addParameter(field: "wired.board.latest_reply_date", value: latestDate)
            }
            messages.append(m)
        }
        messages.append(P7Message(withName: "wired.board.thread_list.done", spec: spec))
        return messages
    }

    private func replyThread(uuid: String, spec: P7Spec) -> [P7Message] {
        guard let thread = getThread(uuid: uuid) else { return [] }
        var messages: [P7Message] = []

        // First message: the thread itself
        let tm = P7Message(withName: "wired.board.thread", spec: spec)
        tm.addParameter(field: "wired.board.thread", value: thread.uuid)
        tm.addParameter(field: "wired.board.text",   value: thread.text)
        tm.addParameter(field: "wired.user.icon",    value: thread.icon ?? Data())
        messages.append(tm)

        // Subsequent messages: the replies
        for post in getPosts(forThread: uuid) {
            let pm = P7Message(withName: "wired.board.post_list", spec: spec)
            pm.addParameter(field: "wired.board.thread",    value: post.thread)
            pm.addParameter(field: "wired.board.post",      value: post.uuid)
            pm.addParameter(field: "wired.board.text",      value: post.text)
            pm.addParameter(field: "wired.user.nick",       value: post.nick)
            pm.addParameter(field: "wired.user.icon",       value: post.icon ?? Data())
            pm.addParameter(field: "wired.board.post_date", value: post.postDate)
            pm.addParameter(field: "wired.board.own_post",  value: false)
            if let editDate = post.editDate {
                pm.addParameter(field: "wired.board.edit_date", value: editDate)
            }
            messages.append(pm)
        }

        let done = P7Message(withName: "wired.board.post_list.done", spec: spec)
        done.addParameter(field: "wired.board.thread", value: uuid)
        messages.append(done)
        return messages
    }

    // MARK: - Command handlers (return broadcast messages)

    private func handleAddBoard(message: P7Message, user: String, group: String, spec: P7Spec) -> [P7Message] {
        guard
            let path = message.string(forField: "wired.board.board"),
            let owner = message.string(forField: "wired.board.owner"),
            let ownerRead = message.bool(forField: "wired.board.owner.read"),
            let ownerWrite = message.bool(forField: "wired.board.owner.write"),
            let grp = message.string(forField: "wired.board.group"),
            let groupRead = message.bool(forField: "wired.board.group.read"),
            let groupWrite = message.bool(forField: "wired.board.group.write"),
            let everyoneRead = message.bool(forField: "wired.board.everyone.read"),
            let everyoneWrite = message.bool(forField: "wired.board.everyone.write")
        else { return [] }

        guard let board = addBoard(path: path, owner: owner, group: grp,
                                   ownerRead: ownerRead, ownerWrite: ownerWrite,
                                   groupRead: groupRead, groupWrite: groupWrite,
                                   everyoneRead: everyoneRead, everyoneWrite: everyoneWrite)
        else { return [] }

        let broadcast = P7Message(withName: "wired.board.board_added", spec: spec)
        broadcast.addParameter(field: "wired.board.board",    value: board.path)
        broadcast.addParameter(field: "wired.board.readable", value: board.canRead(user: user, group: group))
        broadcast.addParameter(field: "wired.board.writable", value: board.canWrite(user: user, group: group))
        return [broadcast]
    }

    private func handleDeleteBoard(message: P7Message, spec: P7Spec) -> [P7Message] {
        guard let path = message.string(forField: "wired.board.board") else { return [] }
        guard deleteBoard(path: path) else { return [] }

        let broadcast = P7Message(withName: "wired.board.board_deleted", spec: spec)
        broadcast.addParameter(field: "wired.board.board", value: path)
        return [broadcast]
    }

    private func handleRenameBoard(message: P7Message, spec: P7Spec) -> [P7Message] {
        guard
            let path    = message.string(forField: "wired.board.board"),
            let newPath = message.string(forField: "wired.board.new_board")
        else { return [] }
        guard renameBoard(path: path, newPath: newPath) else { return [] }

        let broadcast = P7Message(withName: "wired.board.board_renamed", spec: spec)
        broadcast.addParameter(field: "wired.board.board",     value: path)
        broadcast.addParameter(field: "wired.board.new_board", value: newPath)
        return [broadcast]
    }

    private func handleMoveBoard(message: P7Message, spec: P7Spec) -> [P7Message] {
        guard
            let path    = message.string(forField: "wired.board.board"),
            let newPath = message.string(forField: "wired.board.new_board")
        else { return [] }
        guard moveBoard(path: path, newPath: newPath) else { return [] }

        let broadcast = P7Message(withName: "wired.board.board_moved", spec: spec)
        broadcast.addParameter(field: "wired.board.board",     value: path)
        broadcast.addParameter(field: "wired.board.new_board", value: newPath)
        return [broadcast]
    }

    private func handleGetBoardInfo(message: P7Message, spec: P7Spec) -> [P7Message] {
        guard
            let path  = message.string(forField: "wired.board.board"),
            let board = getBoardInfo(path: path)
        else { return [] }

        let reply = P7Message(withName: "wired.board.board_info", spec: spec)
        reply.addParameter(field: "wired.board.board",          value: board.path)
        reply.addParameter(field: "wired.board.owner",          value: board.owner)
        reply.addParameter(field: "wired.board.owner.read",     value: board.ownerRead)
        reply.addParameter(field: "wired.board.owner.write",    value: board.ownerWrite)
        reply.addParameter(field: "wired.board.group",          value: board.group)
        reply.addParameter(field: "wired.board.group.read",     value: board.groupRead)
        reply.addParameter(field: "wired.board.group.write",    value: board.groupWrite)
        reply.addParameter(field: "wired.board.everyone.read",  value: board.everyoneRead)
        reply.addParameter(field: "wired.board.everyone.write", value: board.everyoneWrite)
        return [reply]
    }

    private func handleSetBoardInfo(message: P7Message, spec: P7Spec) -> [P7Message] {
        guard
            let path         = message.string(forField: "wired.board.board"),
            let owner        = message.string(forField: "wired.board.owner"),
            let ownerRead    = message.bool(forField: "wired.board.owner.read"),
            let ownerWrite   = message.bool(forField: "wired.board.owner.write"),
            let grp          = message.string(forField: "wired.board.group"),
            let groupRead    = message.bool(forField: "wired.board.group.read"),
            let groupWrite   = message.bool(forField: "wired.board.group.write"),
            let everyoneRead = message.bool(forField: "wired.board.everyone.read"),
            let everyoneWrite = message.bool(forField: "wired.board.everyone.write")
        else { return [] }

        guard setBoardInfo(path: path, owner: owner, group: grp,
                           ownerRead: ownerRead, ownerWrite: ownerWrite,
                           groupRead: groupRead, groupWrite: groupWrite,
                           everyoneRead: everyoneRead, everyoneWrite: everyoneWrite),
              let board = getBoardInfo(path: path)
        else { return [] }

        let broadcast = P7Message(withName: "wired.board.board_info_changed", spec: spec)
        broadcast.addParameter(field: "wired.board.board",    value: board.path)
        broadcast.addParameter(field: "wired.board.readable", value: board.everyoneRead)
        broadcast.addParameter(field: "wired.board.writable", value: board.everyoneWrite)
        return [broadcast]
    }

    private func handleAddThread(message: P7Message, user: String, group: String,
                                 nick: String, icon: Data?, spec: P7Spec) -> [P7Message] {
        guard
            let boardPath = message.string(forField: "wired.board.board"),
            let subject   = message.string(forField: "wired.board.subject"),
            let text      = message.string(forField: "wired.board.text")
        else { return [] }

        guard let board = getBoardInfo(path: boardPath),
              board.canWrite(user: user, group: group) else { return [] }

        guard let thread = addThread(board: boardPath, subject: subject, text: text,
                                     nick: nick, login: user, icon: icon)
        else { return [] }

        let broadcast = P7Message(withName: "wired.board.thread_added", spec: spec)
        broadcast.addParameter(field: "wired.board.board",      value: thread.board)
        broadcast.addParameter(field: "wired.board.thread",     value: thread.uuid)
        broadcast.addParameter(field: "wired.board.subject",    value: thread.subject)
        broadcast.addParameter(field: "wired.user.nick",        value: thread.nick)
        broadcast.addParameter(field: "wired.user.icon",        value: icon ?? Data())
        broadcast.addParameter(field: "wired.board.post_date",  value: thread.postDate)
        broadcast.addParameter(field: "wired.board.replies",    value: UInt32(0))
        broadcast.addParameter(field: "wired.board.own_thread", value: true)
        return [broadcast]
    }

    private func handleEditThread(message: P7Message, spec: P7Spec) -> [P7Message] {
        guard
            let uuid    = message.uuid(forField: "wired.board.thread"),
            let subject = message.string(forField: "wired.board.subject"),
            let text    = message.string(forField: "wired.board.text")
        else { return [] }
        guard let thread = editThread(uuid: uuid, subject: subject, text: text) else { return [] }

        let broadcast = P7Message(withName: "wired.board.thread_changed", spec: spec)
        broadcast.addParameter(field: "wired.board.thread",  value: thread.uuid)
        broadcast.addParameter(field: "wired.board.subject", value: thread.subject)
        broadcast.addParameter(field: "wired.board.replies", value: UInt32(thread.replies))
        if let editDate = thread.editDate {
            broadcast.addParameter(field: "wired.board.edit_date", value: editDate)
        }
        if let latestDate = thread.latestReplyDate {
            broadcast.addParameter(field: "wired.board.latest_reply_date", value: latestDate)
        }
        return [broadcast]
    }

    private func handleMoveThread(message: P7Message, spec: P7Spec) -> [P7Message] {
        guard
            let uuid    = message.uuid(forField: "wired.board.thread"),
            let toBoard = message.string(forField: "wired.board.new_board")
        else { return [] }
        guard let thread = moveThread(uuid: uuid, toBoard: toBoard) else { return [] }

        let broadcast = P7Message(withName: "wired.board.thread_moved", spec: spec)
        broadcast.addParameter(field: "wired.board.thread",    value: thread.uuid)
        broadcast.addParameter(field: "wired.board.new_board", value: thread.board)
        return [broadcast]
    }

    private func handleDeleteThread(message: P7Message, spec: P7Spec) -> [P7Message] {
        guard let uuid = message.uuid(forField: "wired.board.thread") else { return [] }
        guard deleteThread(uuid: uuid) else { return [] }

        let broadcast = P7Message(withName: "wired.board.thread_deleted", spec: spec)
        broadcast.addParameter(field: "wired.board.thread", value: uuid)
        return [broadcast]
    }

    private func handleAddPost(message: P7Message, user: String,
                               nick: String, icon: Data?, spec: P7Spec) -> [P7Message] {
        guard
            let threadUUID = message.uuid(forField: "wired.board.thread"),
            let text       = message.string(forField: "wired.board.text")
        else { return [] }
        guard let post = addPost(threadUUID: threadUUID, text: text,
                                 nick: nick, login: user, icon: icon)
        else { return [] }

        // The thread_changed broadcast informs subscribed clients of the new reply count
        guard let thread = getThread(uuid: threadUUID) else { return [] }
        let broadcast = P7Message(withName: "wired.board.thread_changed", spec: spec)
        broadcast.addParameter(field: "wired.board.thread",            value: thread.uuid)
        broadcast.addParameter(field: "wired.board.subject",           value: thread.subject)
        broadcast.addParameter(field: "wired.board.replies",           value: UInt32(thread.replies))
        broadcast.addParameter(field: "wired.board.latest_reply",      value: post.uuid)
        broadcast.addParameter(field: "wired.board.latest_reply_date", value: post.postDate)
        return [broadcast]
    }

    private func handleEditPost(message: P7Message, spec: P7Spec) -> [P7Message] {
        guard
            let uuid = message.uuid(forField: "wired.board.post"),
            let text = message.string(forField: "wired.board.text")
        else { return [] }
        guard editPost(uuid: uuid, text: text) != nil else { return [] }
        // No broadcast defined in spec for post edits; server may send ok
        return []
    }

    private func handleDeletePost(message: P7Message, spec: P7Spec) -> [P7Message] {
        guard let uuid = message.uuid(forField: "wired.board.post") else { return [] }
        guard deletePost(uuid: uuid) else { return [] }
        // No specific broadcast for individual post deletion; thread_changed covers count updates
        return []
    }

    // MARK: - Helpers

    private func withLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }
}
