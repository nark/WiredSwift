//
//  WiredPost.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 01/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation


public class WiredPost {
    public var uuid: String
    public var thread: String
    public var text: String
    public var nick: String
    public var login: String
    public var postDate: Date
    public var editDate: Date?
    public var icon: Data?

    public init(uuid: String,
                thread: String,
                text: String,
                nick: String,
                login: String,
                postDate: Date,
                icon: Data? = nil) {
        self.uuid     = uuid
        self.thread   = thread
        self.text     = text
        self.nick     = nick
        self.login    = login
        self.postDate = postDate
        self.icon     = icon
    }
}
