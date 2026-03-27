//
//  Post.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 01/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

/// A reply post within a discussion thread on a `Board`.
///
/// Each `Post` belongs to exactly one `Thread` (identified by `thread` UUID).
/// The first post of a thread is represented by the `Thread` itself; subsequent
/// replies are stored as `Post` instances.
public class Post {
    /// Unique identifier (UUID string) for this post.
    public var uuid: String
    /// UUID of the parent `Thread` this post replies to.
    public var thread: String
    /// Body text of the post.
    public var text: String
    /// Display nick of the author at the time of posting.
    public var nick: String
    /// Login name of the author.
    public var login: String
    /// Timestamp when the post was created.
    public var postDate: Date
    /// Timestamp of the most recent edit, or `nil` if never edited.
    public var editDate: Date?
    /// Author's icon image data, if provided.
    public var icon: Data?

    /// Creates a new `Post`.
    ///
    /// - Parameters:
    ///   - uuid: Unique identifier for the post.
    ///   - thread: UUID of the parent thread.
    ///   - text: Post body text.
    ///   - nick: Author's display name.
    ///   - login: Author's login name.
    ///   - postDate: Creation timestamp.
    ///   - icon: Optional author icon image data.
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
