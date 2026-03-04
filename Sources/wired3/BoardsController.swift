//
//  BoardsController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 01/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation
import WiredSwift
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)


/// Manages all boards, threads and posts for a Wired server.
/// Storage is in-memory; persist `boards`, `threads` and `posts`
/// externally if needed.
public class BoardsController {

    // MARK: - Storage

    private let lock = NSLock()
    private let databasePath: String?

    /// All boards indexed by path.
    public private(set) var boards: [String: Board] = [:]

    /// All threads indexed by UUID.
    public private(set) var threads: [String: Thread] = [:]

    /// All posts indexed by UUID.
    public private(set) var posts: [String: Post] = [:]

    /// Maps board path -> ordered list of thread UUIDs.
    private var boardThreads: [String: [String]] = [:]

    public init(databasePath: String? = nil) {
        self.databasePath = databasePath
        createTablesIfNeeded()
        loadFromDatabase()
    }
    
    private func canonicalUUID(_ uuid: String) -> String {
        uuid.lowercased()
    }
    
    // MARK: - Persistence
    
    private func withDatabase<T>(_ body: (OpaquePointer) -> T?) -> T? {
        guard let databasePath else { return nil }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        
        _ = sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
        return body(db)
    }
    
    private func createTablesIfNeeded() {
        _ = withDatabase { db in
            let sql = [
                """
                CREATE TABLE IF NOT EXISTS boards (
                  path TEXT PRIMARY KEY,
                  owner TEXT NOT NULL,
                  group_name TEXT NOT NULL,
                  owner_read INTEGER NOT NULL,
                  owner_write INTEGER NOT NULL,
                  group_read INTEGER NOT NULL,
                  group_write INTEGER NOT NULL,
                  everyone_read INTEGER NOT NULL,
                  everyone_write INTEGER NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS board_threads (
                  uuid TEXT PRIMARY KEY,
                  board_path TEXT NOT NULL,
                  subject TEXT NOT NULL,
                  text TEXT NOT NULL,
                  nick TEXT NOT NULL,
                  login TEXT NOT NULL,
                  post_date REAL NOT NULL,
                  edit_date REAL,
                  icon BLOB
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS board_posts (
                  uuid TEXT PRIMARY KEY,
                  thread_uuid TEXT NOT NULL,
                  text TEXT NOT NULL,
                  nick TEXT NOT NULL,
                  login TEXT NOT NULL,
                  post_date REAL NOT NULL,
                  edit_date REAL,
                  icon BLOB
                );
                """,
                "CREATE INDEX IF NOT EXISTS idx_board_threads_board_path ON board_threads(board_path);",
                "CREATE INDEX IF NOT EXISTS idx_board_posts_thread_uuid ON board_posts(thread_uuid);"
            ]
            
            for statement in sql where sqlite3_exec(db, statement, nil, nil, nil) != SQLITE_OK {
                return false
            }
            
            return true
        }
    }
    
    private func loadFromDatabase() {
        guard databasePath != nil else { return }
        
        _ = withDatabase { db in
            var loadedBoards: [String: Board] = [:]
            var loadedBoardThreads: [String: [String]] = [:]
            var loadedThreads: [String: Thread] = [:]
            var loadedPosts: [String: Post] = [:]
            
            var boardStatement: OpaquePointer?
            let boardQuery = """
                SELECT path, owner, group_name, owner_read, owner_write, group_read, group_write, everyone_read, everyone_write
                FROM boards
                ORDER BY path ASC;
                """
            if sqlite3_prepare_v2(db, boardQuery, -1, &boardStatement, nil) == SQLITE_OK, let boardStatement {
                while sqlite3_step(boardStatement) == SQLITE_ROW {
                    guard let pathC = sqlite3_column_text(boardStatement, 0),
                          let ownerC = sqlite3_column_text(boardStatement, 1),
                          let groupC = sqlite3_column_text(boardStatement, 2) else { continue }
                    
                    let path = String(cString: pathC)
                    let board = Board(
                        path: path,
                        owner: String(cString: ownerC),
                        group: String(cString: groupC),
                        ownerRead: sqlite3_column_int(boardStatement, 3) != 0,
                        ownerWrite: sqlite3_column_int(boardStatement, 4) != 0,
                        groupRead: sqlite3_column_int(boardStatement, 5) != 0,
                        groupWrite: sqlite3_column_int(boardStatement, 6) != 0,
                        everyoneRead: sqlite3_column_int(boardStatement, 7) != 0,
                        everyoneWrite: sqlite3_column_int(boardStatement, 8) != 0
                    )
                    loadedBoards[path] = board
                    loadedBoardThreads[path] = []
                }
            }
            sqlite3_finalize(boardStatement)
            
            var threadStatement: OpaquePointer?
            let threadQuery = """
                SELECT uuid, board_path, subject, text, nick, login, post_date, edit_date, icon
                FROM board_threads
                ORDER BY post_date ASC;
                """
            if sqlite3_prepare_v2(db, threadQuery, -1, &threadStatement, nil) == SQLITE_OK, let threadStatement {
                while sqlite3_step(threadStatement) == SQLITE_ROW {
                    guard let uuidC = sqlite3_column_text(threadStatement, 0),
                          let boardC = sqlite3_column_text(threadStatement, 1),
                          let subjectC = sqlite3_column_text(threadStatement, 2),
                          let textC = sqlite3_column_text(threadStatement, 3),
                          let nickC = sqlite3_column_text(threadStatement, 4),
                          let loginC = sqlite3_column_text(threadStatement, 5) else { continue }
                    
                    let uuid = canonicalUUID(String(cString: uuidC))
                    let boardPath = String(cString: boardC)
                    let thread = Thread(
                        uuid: uuid,
                        board: boardPath,
                        subject: String(cString: subjectC),
                        text: String(cString: textC),
                        nick: String(cString: nickC),
                        login: String(cString: loginC),
                        postDate: Date(timeIntervalSince1970: sqlite3_column_double(threadStatement, 6)),
                        icon: dataColumn(statement: threadStatement, index: 8)
                    )
                    if sqlite3_column_type(threadStatement, 7) != SQLITE_NULL {
                        thread.editDate = Date(timeIntervalSince1970: sqlite3_column_double(threadStatement, 7))
                    }
                    
                    loadedThreads[uuid] = thread
                    loadedBoardThreads[boardPath, default: []].append(uuid)
                }
            }
            sqlite3_finalize(threadStatement)
            
            var postStatement: OpaquePointer?
            let postQuery = """
                SELECT uuid, thread_uuid, text, nick, login, post_date, edit_date, icon
                FROM board_posts
                ORDER BY post_date ASC;
                """
            if sqlite3_prepare_v2(db, postQuery, -1, &postStatement, nil) == SQLITE_OK, let postStatement {
                while sqlite3_step(postStatement) == SQLITE_ROW {
                    guard let uuidC = sqlite3_column_text(postStatement, 0),
                          let threadC = sqlite3_column_text(postStatement, 1),
                          let textC = sqlite3_column_text(postStatement, 2),
                          let nickC = sqlite3_column_text(postStatement, 3),
                          let loginC = sqlite3_column_text(postStatement, 4) else { continue }
                    
                    let uuid = canonicalUUID(String(cString: uuidC))
                    let threadUUID = canonicalUUID(String(cString: threadC))
                    let post = Post(
                        uuid: uuid,
                        thread: threadUUID,
                        text: String(cString: textC),
                        nick: String(cString: nickC),
                        login: String(cString: loginC),
                        postDate: Date(timeIntervalSince1970: sqlite3_column_double(postStatement, 5)),
                        icon: dataColumn(statement: postStatement, index: 7)
                    )
                    if sqlite3_column_type(postStatement, 6) != SQLITE_NULL {
                        post.editDate = Date(timeIntervalSince1970: sqlite3_column_double(postStatement, 6))
                    }
                    
                    loadedPosts[uuid] = post
                }
            }
            sqlite3_finalize(postStatement)
            
            self.withLock {
                self.boards = loadedBoards
                self.boardThreads = loadedBoardThreads
                self.threads = loadedThreads
                self.posts = loadedPosts
                
                for post in loadedPosts.values {
                    self.threads[post.thread]?.posts.append(post)
                }
            }
            
            return true
        }
    }
    
    private func dataColumn(statement: OpaquePointer, index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    // MARK: - Boards

    /// Returns all boards readable by the given user/group, sorted by path.
    public func getBoards(forUser user: String, group: String) -> [Board] {
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
                         everyoneWrite: Bool) -> Board? {
        return withLock {
            guard boards[path] == nil else { return nil }
            if let persisted = withDatabase({ db -> Bool? in
                var statement: OpaquePointer?
                let sql = """
                    INSERT INTO boards(path, owner, group_name, owner_read, owner_write, group_read, group_write, everyone_read, everyone_write)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, owner, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, group, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(statement, 4, ownerRead ? 1 : 0)
                sqlite3_bind_int(statement, 5, ownerWrite ? 1 : 0)
                sqlite3_bind_int(statement, 6, groupRead ? 1 : 0)
                sqlite3_bind_int(statement, 7, groupWrite ? 1 : 0)
                sqlite3_bind_int(statement, 8, everyoneRead ? 1 : 0)
                sqlite3_bind_int(statement, 9, everyoneWrite ? 1 : 0)
                return sqlite3_step(statement) == SQLITE_DONE
            }), !persisted {
                return nil
            }
            
            let board = Board(path: path,
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
            if let persisted = withDatabase({ db -> Bool? in
                guard sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else { return false }
                defer { _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil) }
                
                var postsStatement: OpaquePointer?
                let deletePosts = """
                    DELETE FROM board_posts WHERE thread_uuid IN (
                        SELECT uuid FROM board_threads WHERE board_path = ?
                    );
                    """
                guard sqlite3_prepare_v2(db, deletePosts, -1, &postsStatement, nil) == SQLITE_OK, let postsStatement else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                sqlite3_bind_text(postsStatement, 1, path, -1, SQLITE_TRANSIENT)
                let postsOK = sqlite3_step(postsStatement) == SQLITE_DONE
                sqlite3_finalize(postsStatement)
                guard postsOK else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                
                var threadsStatement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "DELETE FROM board_threads WHERE board_path = ?;", -1, &threadsStatement, nil) == SQLITE_OK, let threadsStatement else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                sqlite3_bind_text(threadsStatement, 1, path, -1, SQLITE_TRANSIENT)
                let threadsOK = sqlite3_step(threadsStatement) == SQLITE_DONE
                sqlite3_finalize(threadsStatement)
                guard threadsOK else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                
                var boardStatement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "DELETE FROM boards WHERE path = ?;", -1, &boardStatement, nil) == SQLITE_OK, let boardStatement else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                sqlite3_bind_text(boardStatement, 1, path, -1, SQLITE_TRANSIENT)
                let boardOK = sqlite3_step(boardStatement) == SQLITE_DONE
                sqlite3_finalize(boardStatement)
                guard boardOK else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                
                return true
            }), !persisted {
                return false
            }
            
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
            if let persisted = withDatabase({ db -> Bool? in
                guard sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else { return false }
                defer { _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil) }
                
                var boardStatement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "UPDATE boards SET path = ? WHERE path = ?;", -1, &boardStatement, nil) == SQLITE_OK, let boardStatement else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                sqlite3_bind_text(boardStatement, 1, newPath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(boardStatement, 2, path, -1, SQLITE_TRANSIENT)
                let boardOK = sqlite3_step(boardStatement) == SQLITE_DONE
                sqlite3_finalize(boardStatement)
                guard boardOK else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                
                var threadsStatement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "UPDATE board_threads SET board_path = ? WHERE board_path = ?;", -1, &threadsStatement, nil) == SQLITE_OK, let threadsStatement else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                sqlite3_bind_text(threadsStatement, 1, newPath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(threadsStatement, 2, path, -1, SQLITE_TRANSIENT)
                let threadsOK = sqlite3_step(threadsStatement) == SQLITE_DONE
                sqlite3_finalize(threadsStatement)
                guard threadsOK else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                
                return true
            }), !persisted {
                boards[path] = board
                return false
            }
            
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
    public func getBoardInfo(path: String) -> Board? {
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
            if let persisted = withDatabase({ db -> Bool? in
                var statement: OpaquePointer?
                let sql = """
                    UPDATE boards
                    SET owner = ?, group_name = ?, owner_read = ?, owner_write = ?, group_read = ?, group_write = ?, everyone_read = ?, everyone_write = ?
                    WHERE path = ?;
                    """
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, owner, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, group, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(statement, 3, ownerRead ? 1 : 0)
                sqlite3_bind_int(statement, 4, ownerWrite ? 1 : 0)
                sqlite3_bind_int(statement, 5, groupRead ? 1 : 0)
                sqlite3_bind_int(statement, 6, groupWrite ? 1 : 0)
                sqlite3_bind_int(statement, 7, everyoneRead ? 1 : 0)
                sqlite3_bind_int(statement, 8, everyoneWrite ? 1 : 0)
                sqlite3_bind_text(statement, 9, path, -1, SQLITE_TRANSIENT)
                return sqlite3_step(statement) == SQLITE_DONE
            }), !persisted {
                return false
            }
            
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
    public func getThreads(forBoard boardPath: String) -> [Thread] {
        return withLock {
            guard let uuids = boardThreads[boardPath] else { return [] }
            return uuids.compactMap { threads[$0] }
        }
    }

    /// Returns a single thread by UUID.
    public func getThread(uuid: String) -> Thread? {
        return withLock { threads[canonicalUUID(uuid)] }
    }

    /// Creates a new thread. Returns nil if the board does not exist.
    @discardableResult
    public func addThread(board: String,
                          subject: String,
                          text: String,
                          nick: String,
                          login: String,
                          icon: Data? = nil) -> Thread? {
        return withLock {
            guard boards[board] != nil else { return nil }
            let uuid = UUID().uuidString.lowercased()
            let thread = Thread(uuid: uuid,
                                     board: board,
                                     subject: subject,
                                     text: text,
                                     nick: nick,
                                     login: login,
                                     postDate: Date(),
                                     icon: icon)
            if let persisted = withDatabase({ db -> Bool? in
                var statement: OpaquePointer?
                let sql = """
                    INSERT INTO board_threads(uuid, board_path, subject, text, nick, login, post_date, edit_date, icon)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, thread.uuid, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, thread.board, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, thread.subject, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, thread.text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 5, thread.nick, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 6, thread.login, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(statement, 7, thread.postDate.timeIntervalSince1970)
                sqlite3_bind_null(statement, 8)
                if let icon = thread.icon {
                    icon.withUnsafeBytes { rawBuffer in
                        if let base = rawBuffer.baseAddress {
                            sqlite3_bind_blob(statement, 9, base, Int32(icon.count), SQLITE_TRANSIENT)
                        } else {
                            sqlite3_bind_null(statement, 9)
                        }
                    }
                } else {
                    sqlite3_bind_null(statement, 9)
                }
                return sqlite3_step(statement) == SQLITE_DONE
            }), !persisted {
                return nil
            }
            
            threads[uuid] = thread
            boardThreads[board, default: []].append(uuid)
            return thread
        }
    }

    /// Edits the subject and text of an existing thread.
    @discardableResult
    public func editThread(uuid: String, subject: String, text: String) -> Thread? {
        return withLock {
            let key = canonicalUUID(uuid)
            guard let thread = threads[key] else { return nil }
            thread.subject  = subject
            thread.text     = text
            thread.editDate = Date()
            if let persisted = withDatabase({ db -> Bool? in
                var statement: OpaquePointer?
                let sql = "UPDATE board_threads SET subject = ?, text = ?, edit_date = ? WHERE uuid = ?;"
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, thread.subject, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, thread.text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(statement, 3, thread.editDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
                sqlite3_bind_text(statement, 4, key, -1, SQLITE_TRANSIENT)
                return sqlite3_step(statement) == SQLITE_DONE
            }), !persisted {
                return nil
            }
            return thread
        }
    }

    /// Moves a thread to another board.
    @discardableResult
    public func moveThread(uuid: String, toBoard: String) -> Thread? {
        return withLock {
            let key = canonicalUUID(uuid)
            guard let thread = threads[key], boards[toBoard] != nil else { return nil }
            boardThreads[thread.board]?.removeAll { $0 == key }
            boardThreads[toBoard, default: []].append(key)
            thread.board = toBoard
            if let persisted = withDatabase({ db -> Bool? in
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "UPDATE board_threads SET board_path = ? WHERE uuid = ?;", -1, &statement, nil) == SQLITE_OK, let statement else { return false }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, toBoard, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, key, -1, SQLITE_TRANSIENT)
                return sqlite3_step(statement) == SQLITE_DONE
            }), !persisted {
                return nil
            }
            return thread
        }
    }

    /// Deletes a thread and all its posts.
    @discardableResult
    public func deleteThread(uuid: String) -> Bool {
        return withLock {
            let key = canonicalUUID(uuid)
            if let persisted = withDatabase({ db -> Bool? in
                guard sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else { return false }
                defer { _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil) }
                
                var postsStatement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "DELETE FROM board_posts WHERE thread_uuid = ?;", -1, &postsStatement, nil) == SQLITE_OK, let postsStatement else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                sqlite3_bind_text(postsStatement, 1, key, -1, SQLITE_TRANSIENT)
                let postsOK = sqlite3_step(postsStatement) == SQLITE_DONE
                sqlite3_finalize(postsStatement)
                guard postsOK else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                
                var threadStatement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "DELETE FROM board_threads WHERE uuid = ?;", -1, &threadStatement, nil) == SQLITE_OK, let threadStatement else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                sqlite3_bind_text(threadStatement, 1, key, -1, SQLITE_TRANSIENT)
                let threadOK = sqlite3_step(threadStatement) == SQLITE_DONE
                sqlite3_finalize(threadStatement)
                guard threadOK else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                
                return true
            }), !persisted {
                return false
            }
            
            guard let thread = threads.removeValue(forKey: key) else { return false }
            boardThreads[thread.board]?.removeAll { $0 == key }
            for post in thread.posts {
                posts.removeValue(forKey: post.uuid)
            }
            return true
        }
    }

    // MARK: - Posts

    /// Returns all posts for a thread in insertion order.
    public func getPosts(forThread threadUUID: String) -> [Post] {
        return withLock { threads[canonicalUUID(threadUUID)]?.posts ?? [] }
    }

    /// Adds a reply post to an existing thread.
    @discardableResult
    public func addPost(threadUUID: String,
                        text: String,
                        nick: String,
                        login: String,
                        icon: Data? = nil) -> Post? {
        return withLock {
            let threadKey = canonicalUUID(threadUUID)
            guard let thread = threads[threadKey] else { return nil }
            let uuid = UUID().uuidString.lowercased()
            let post = Post(uuid: uuid,
                                 thread: threadKey,
                                 text: text,
                                 nick: nick,
                                 login: login,
                                 postDate: Date(),
                                 icon: icon)
            if let persisted = withDatabase({ db -> Bool? in
                var statement: OpaquePointer?
                let sql = """
                    INSERT INTO board_posts(uuid, thread_uuid, text, nick, login, post_date, edit_date, icon)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?);
                    """
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, post.uuid, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, post.thread, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, post.text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, post.nick, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 5, post.login, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(statement, 6, post.postDate.timeIntervalSince1970)
                sqlite3_bind_null(statement, 7)
                if let icon = post.icon {
                    icon.withUnsafeBytes { rawBuffer in
                        if let base = rawBuffer.baseAddress {
                            sqlite3_bind_blob(statement, 8, base, Int32(icon.count), SQLITE_TRANSIENT)
                        } else {
                            sqlite3_bind_null(statement, 8)
                        }
                    }
                } else {
                    sqlite3_bind_null(statement, 8)
                }
                return sqlite3_step(statement) == SQLITE_DONE
            }), !persisted {
                return nil
            }
            
            posts[uuid] = post
            thread.posts.append(post)
            return post
        }
    }

    /// Edits the text of an existing post.
    @discardableResult
    public func editPost(uuid: String, text: String) -> Post? {
        return withLock {
            guard let post = posts[canonicalUUID(uuid)] else { return nil }
            post.text     = text
            post.editDate = Date()
            threads[post.thread]?.editDate = post.editDate
            if let persisted = withDatabase({ db -> Bool? in
                guard sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else { return false }
                defer { _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil) }

                var postStatement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "UPDATE board_posts SET text = ?, edit_date = ? WHERE uuid = ?;", -1, &postStatement, nil) == SQLITE_OK, let postStatement else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                sqlite3_bind_text(postStatement, 1, post.text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(postStatement, 2, post.editDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
                sqlite3_bind_text(postStatement, 3, post.uuid, -1, SQLITE_TRANSIENT)
                let postOK = sqlite3_step(postStatement) == SQLITE_DONE
                sqlite3_finalize(postStatement)
                guard postOK else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }

                var threadStatement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "UPDATE board_threads SET edit_date = ? WHERE uuid = ?;", -1, &threadStatement, nil) == SQLITE_OK, let threadStatement else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }
                sqlite3_bind_double(threadStatement, 1, post.editDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
                sqlite3_bind_text(threadStatement, 2, post.thread, -1, SQLITE_TRANSIENT)
                let threadOK = sqlite3_step(threadStatement) == SQLITE_DONE
                sqlite3_finalize(threadStatement)
                guard threadOK else {
                    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                    return false
                }

                return true
            }), !persisted {
                return nil
            }
            return post
        }
    }

    /// Deletes a post.
    @discardableResult
    public func deletePost(uuid: String) -> Bool {
        return withLock {
            let key = canonicalUUID(uuid)
            if let persisted = withDatabase({ db -> Bool? in
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "DELETE FROM board_posts WHERE uuid = ?;", -1, &statement, nil) == SQLITE_OK, let statement else { return false }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
                return sqlite3_step(statement) == SQLITE_DONE
            }), !persisted {
                return false
            }
            guard let post = posts.removeValue(forKey: key) else { return false }
            threads[post.thread]?.posts.removeAll { $0.uuid == key }
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
