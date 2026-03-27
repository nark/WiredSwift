//
//  Board.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 01/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

public class Board {
    public var path: String
    public var owner: String
    public var group: String
    public var ownerRead: Bool
    public var ownerWrite: Bool
    public var groupRead: Bool
    public var groupWrite: Bool
    public var everyoneRead: Bool
    public var everyoneWrite: Bool

    public var threads: [Thread] = []

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

    public var name: String {
        return (path as NSString).lastPathComponent
    }

    public func canRead(user: String, group: String) -> Bool {
        if everyoneRead { return true }
        if owner == user && ownerRead { return true }
        if self.group == group && groupRead { return true }
        return false
    }

    public func canWrite(user: String, group: String) -> Bool {
        if everyoneWrite { return true }
        if owner == user && ownerWrite { return true }
        if self.group == group && groupWrite { return true }
        return false
    }
}
