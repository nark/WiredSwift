//
//  WiredThread.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 01/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation


public class WiredThread {
    public var uuid: String
    public var board: String
    public var subject: String
    public var text: String
    public var nick: String
    public var login: String
    public var postDate: Date
    public var editDate: Date?
    public var icon: Data?

    public var posts: [WiredPost] = []

    public var replies: Int {
        return posts.count
    }

    public var latestReply: WiredPost? {
        return posts.last
    }

    public var latestReplyDate: Date? {
        return posts.last?.postDate
    }

    public var latestReplyUUID: String? {
        return posts.last?.uuid
    }

    public init(uuid: String,
                board: String,
                subject: String,
                text: String,
                nick: String,
                login: String,
                postDate: Date,
                icon: Data? = nil) {
        self.uuid     = uuid
        self.board    = board
        self.subject  = subject
        self.text     = text
        self.nick     = nick
        self.login    = login
        self.postDate = postDate
        self.icon     = icon
    }
}
