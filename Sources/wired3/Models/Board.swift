//
//  Board.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 01/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

/// A discussion board (bulletin board) with Unix-style read/write permissions.
///
/// Boards are organised as a virtual file-system path and contain `Thread`
/// objects. Access control mirrors POSIX: separate read and write bits for
/// owner, group, and everyone.
public class Board {
    /// Virtual file-system path that uniquely identifies this board.
    public var path: String
    /// Username of the board owner.
    public var owner: String
    /// Group name associated with this board.
    public var group: String
    /// Whether the owner may read from this board.
    public var ownerRead: Bool
    /// Whether the owner may write to this board.
    public var ownerWrite: Bool
    /// Whether members of the associated group may read from this board.
    public var groupRead: Bool
    /// Whether members of the associated group may write to this board.
    public var groupWrite: Bool
    /// Whether any user may read from this board.
    public var everyoneRead: Bool
    /// Whether any user may write to this board.
    public var everyoneWrite: Bool

    /// In-memory list of threads belonging to this board.
    public var threads: [Thread] = []

    /// Creates a `Board` with explicit permission flags.
    ///
    /// - Parameters:
    ///   - path: Virtual path identifying the board.
    ///   - owner: Username of the board owner.
    ///   - group: Group name for group-level permission checks.
    ///   - ownerRead: Owner read permission; default `true`.
    ///   - ownerWrite: Owner write permission; default `true`.
    ///   - groupRead: Group read permission; default `true`.
    ///   - groupWrite: Group write permission; default `true`.
    ///   - everyoneRead: Public read permission; default `true`.
    ///   - everyoneWrite: Public write permission; default `false`.
    public init(path: String,
                owner: String = "",
                group: String = "",
                ownerRead: Bool = true,
                ownerWrite: Bool = true,
                groupRead: Bool = true,
                groupWrite: Bool = true,
                everyoneRead: Bool = true,
                everyoneWrite: Bool = false) {
        self.path         = path
        self.owner        = owner
        self.group        = group
        self.ownerRead    = ownerRead
        self.ownerWrite   = ownerWrite
        self.groupRead    = groupRead
        self.groupWrite   = groupWrite
        self.everyoneRead = everyoneRead
        self.everyoneWrite = everyoneWrite
    }

    /// The last path component of `path`, used as the human-readable board name.
    public var name: String {
        return (path as NSString).lastPathComponent
    }

    /// Returns whether the given user may read posts from this board.
    ///
    /// - Parameters:
    ///   - user: The username to test.
    ///   - group: The user's primary group name.
    /// - Returns: `true` if read access is permitted.
    public func canRead(user: String, group: String) -> Bool {
        if everyoneRead { return true }
        if owner == user && ownerRead { return true }
        if self.group == group && groupRead { return true }
        return false
    }

    /// Returns whether the given user may post to this board.
    ///
    /// - Parameters:
    ///   - user: The username to test.
    ///   - group: The user's primary group name.
    /// - Returns: `true` if write access is permitted.
    public func canWrite(user: String, group: String) -> Bool {
        if everyoneWrite { return true }
        if owner == user && ownerWrite { return true }
        if self.group == group && groupWrite { return true }
        return false
    }
}
