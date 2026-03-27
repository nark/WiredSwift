//
//  UserInfo.swift
//  Wired 3
//
//  Created by Rafael Warnault on 20/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation

/// Represents a connected Wired user, populated from `wired.user.user_list`
/// or `wired.chat.user_join` P7 messages.
public class UserInfo: CustomStringConvertible {
    public var userID: UInt32!
    public var idle: Bool!

    public var nick: String!
    public var status: String!
    public var icon: Data!
    public var color: UInt32!

    private var message: P7Message!

    /// A short human-readable representation in the form `"<id>:<nick>"`.
    public var description: String {
        return "\(self.userID!):\(self.nick!)"
    }

    /// Creates a `UserInfo` by extracting all `wired.user.*` fields from `message`.
    ///
    /// - Parameter message: A decoded `wired.user.user_list` or `wired.chat.user_join` P7 message.
    public init(message: P7Message) {
        self.message = message

        self.update(withMessage: message)
    }

    /// Updates all stored fields from a new P7 message (e.g. `wired.user.status`
    /// change or `wired.chat.user_join` re-broadcast).
    ///
    /// - Parameter message: The P7 message carrying updated user fields.
    public func update(withMessage message: P7Message) {
        if let v = message.uint32(forField: "wired.user.id") {
            self.userID = v
        }

        if let v = message.bool(forField: "wired.user.idle") {
            self.idle = v
        }

        if let v = message.string(forField: "wired.user.nick") {
            self.nick = v
        }

        if let v = message.string(forField: "wired.user.status") {
            self.status = v
        }

        if let v = message.data(forField: "wired.user.icon") {
            self.icon = v
        }

        if let v = message.enumeration(forField: "wired.account.color") {
            self.color = v
        }
    }
}
