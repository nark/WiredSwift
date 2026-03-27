//
//  Client.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 24/04/2021.
//

import Foundation
import WiredSwift

/// Represents an active client TCP session connected to the Wired server.
///
/// A `Client` is created when a new connection is accepted and is torn down
/// when the connection closes. It tracks authentication state, the associated
/// `User` account, the underlying `P7Socket`, and any ongoing file `Transfer`.
public class Client {
    /// Authentication and lifecycle state for a connected client session.
    public enum State: UInt32 {
        /// TCP connection accepted; no handshake messages exchanged yet.
        case CONNECTED          = 0
        /// Client has sent its `wired.client_info` message.
        case GAVE_CLIENT_INFO
        /// Login completed; client is fully authenticated.
        case LOGGED_IN
        /// Connection has been closed.
        case DISCONNECTED
    }

    public var ip: String?
    public var host: String?
    public var nick: String?
    public var status: String?
    public var icon: Data?
    public var idle: Bool = false
    public var idleTime: Date?
    public var loginTime: Date?
    public var state: State = .DISCONNECTED

    public var userID: UInt32
    public var user: User?
    public var socket: P7Socket
    public var transfer: Transfer?
    public var isSubscribedToAccounts: Bool = false
    public var isSubscribedToBoards: Bool = false
    public var isSubscribedToEvents: Bool = false
    public var isSubscribedToLog: Bool = false
    /// The numeric color value of the user's account, or `0` if not set.
    ///
    /// Derived from `user.color`; used to tint the user's name in the client UI.
    public var accountColor: UInt32 {
        UInt32(user?.color ?? "") ?? 0
    }

    public var applicationName = ""
    public var applicationVersion = ""
    public var applicationBuild = ""
    public var osName = ""
    public var osVersion = ""
    public var arch = ""
    public var supportsRsrc = false

    /// Creates a new `Client` for an incoming connection.
    ///
    /// - Parameters:
    ///   - userID: Server-assigned numeric identifier unique to this session.
    ///   - socket: The authenticated P7 socket wrapping the TCP connection.
    public init(userID: UInt32, socket: P7Socket) {
        self.userID = userID
        self.socket = socket
    }
}
