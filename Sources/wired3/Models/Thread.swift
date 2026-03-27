//
//  Thread.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 01/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

/// An opening post (thread) within a `Board`, potentially containing reply `Post` objects.
///
/// The thread itself holds the subject line and the body of the first message.
/// Reply posts are stored in the `posts` array. Computed properties derive
/// summary information from the reply list.
public class Thread {
    /// Unique identifier (UUID string) for this thread.
    public var uuid: String
    /// Path of the `Board` this thread belongs to.
    public var board: String
    /// Subject / title of the thread.
    public var subject: String
    /// Body text of the opening post.
    public var text: String
    /// Display nick of the thread author at creation time.
    public var nick: String
    /// Login name of the thread author.
    public var login: String
    /// Timestamp when the thread was created.
    public var postDate: Date
    /// Timestamp of the most recent edit to the opening post, or `nil`.
    public var editDate: Date?
    /// Author's icon image data, if provided.
    public var icon: Data?

    /// Reply posts in chronological order.
    public var posts: [Post] = []

    /// The number of reply posts in this thread.
    public var replies: Int {
        return posts.count
    }

    /// The most recent reply post, or `nil` if there are no replies.
    public var latestReply: Post? {
        return posts.last
    }

    /// The creation date of the most recent reply, or `nil` if there are no replies.
    public var latestReplyDate: Date? {
        return posts.last?.postDate
    }

    /// The UUID of the most recent reply post, or `nil` if there are no replies.
    public var latestReplyUUID: String? {
        return posts.last?.uuid
    }

    /// Creates a new `Thread` (opening post).
    ///
    /// - Parameters:
    ///   - uuid: Unique identifier for this thread.
    ///   - board: Path of the board the thread belongs to.
    ///   - subject: Thread subject line.
    ///   - text: Body text of the opening post.
    ///   - nick: Author's display name.
    ///   - login: Author's login name.
    ///   - postDate: Thread creation timestamp.
    ///   - icon: Optional author icon image data.
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
