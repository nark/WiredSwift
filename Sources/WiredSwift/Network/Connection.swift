//
//  Connection.swift
//  Wired 3
//
//  Created by Rafael Warnault on 18/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation
import Dispatch

extension Notification.Name {
    /// Posted on the main queue just before a link connection begins disconnecting.
    public static let linkConnectionWillDisconnect     = Notification.Name("linkConnectionWillDisconnect")
    /// Posted on the main queue after the underlying socket has been closed.
    public static let linkConnectionDidClose           = Notification.Name("linkConnectionDidClose")
    /// Posted on the main queue after a successful reconnect.
    public static let linkConnectionDidReconnect       = Notification.Name("linkConnectionDidReconnect")
    /// Posted on the main queue when a reconnect attempt fails.
    public static let linkConnectionDidFailReconnect   = Notification.Name("linkConnectionDidFailReconnect")
}

public protocol ConnectionDelegate: class {
    func connectionDidConnect(connection: Connection)
    func connectionDidFailToConnect(connection: Connection, error: Error)
    func connectionDisconnected(connection: Connection, error: Error?)

    func connectionDidSendMessage(connection: Connection, message: P7Message)
    func connectionDidReceiveMessage(connection: Connection, message: P7Message)
    func connectionDidReceiveError(connection: Connection, message: P7Message)

    func connectionDidLogin(connection: Connection, message: P7Message)
    func connectionDidReceivePriviledges(connection: Connection, message: P7Message)
}

public protocol ClientInfoDelegate: class {
    func clientInfoApplicationName(for connection: Connection) -> String?
    func clientInfoApplicationVersion(for connection: Connection) -> String?
    func clientInfoApplicationBuild(for connection: Connection) -> String?
}

public protocol ServerInfoDelegate: class {
    func serverInfoDidChange(for connection: Connection)
}

public extension ConnectionDelegate {
    // optional delegate methods
    func connectionDidConnect(connection: Connection) { }
    func connectionDidFailToConnect(connection: Connection, error: Error) { }
    func connectionDisconnected(connection: Connection, error: Error?) { }
    func connectionDidSendMessage(connection: Connection, message: P7Message) { }
    func connectionDidLogin(connection: Connection, message: P7Message) { }
    func connectionDidReceivePriviledges(connection: Connection, message: P7Message) { }
}

public extension ClientInfoDelegate {
    // optional delegate methods
    func clientInfoApplicationName(for connection: Connection) -> String? { return nil }
    func clientInfoApplicationVersion(for connection: Connection) -> String? { return nil }
    func clientInfoApplicationBuild(for connection: Connection) -> String? { return nil }
}

public extension ServerInfoDelegate {
    // optional delegate methods
    func serverInfoDidChange(for connection: Connection) {  }
}

/// High-level Wired protocol connection that manages the login handshake, ping keepalive,
/// and delegate fan-out for a single server session.
///
/// Create a `Connection` with a `P7Spec`, optionally supply a `ConnectionDelegate`, then
/// call `connect(withUrl:)` to perform the full handshake (client-info → set-user → login).
/// Set `interactive` to `false` before connecting if you want to drive the read loop yourself.
open class Connection: NSObject {
    enum ConnectionError: Error {
        case cannotReadMessage(_ message: String?)
        case cannotSetNick
        case cannotSetStatus
        case cannotSetIcon
    }

    public var spec: P7Spec
    public var url: Url!
    public var socket: P7Socket!
    public var delegates: [ConnectionDelegate] = []
    public var clientInfoDelegate: ClientInfoDelegate?
    public var serverInfoDelegate: ServerInfoDelegate?
    /// When `true` (the default) the connection starts a background read loop after connecting.
    /// Set to `false` before calling `connect(withUrl:)` if you intend to call `readMessage()` manually.
    public var interactive: Bool = true

    /// Monotonically-increasing counter used to tag each outgoing message with a unique transaction ID.
    public var transactionCounter: UInt32 = 1

    public var userID: UInt32!
    public var userInfo: UserInfo?
    public var privileges: [String] = []

    public var nick: String     = "Swift Wired"
    public var status: String   = ""
    public var icon: String     = Wired.defaultUserIcon

    public var serverInfo: ServerInfo?

    /// SECURITY (A_009): TOFU trust handler forwarded to P7Socket during connect/reconnect.
    /// Set before calling connect(withUrl:). See P7Socket.serverTrustHandler for the signature.
    public var serverTrustHandler: ((String, Bool, Bool) -> Bool)?

    private var lastPingDate: Date!
    private var pingCheckTimer: Timer!

    private var listener: DispatchWorkItem!

    /// A compact human-readable identifier for this connection in the form `login@hostname:port`.
    public var URI: String {
        "\(self.url.login)@\(self.url.hostname):\(self.url.port)"
    }

    /// Creates a connection backed by the given protocol spec.
    ///
    /// - Parameters:
    ///   - spec: The `P7Spec` that describes message types and field definitions.
    ///   - delegate: An optional initial delegate; additional delegates can be added later via `addDelegate(_:)`.
    public init(withSpec spec: P7Spec, delegate: ConnectionDelegate? = nil) {
        self.spec = spec

        super.init()

        if let d = delegate {
            self.addDelegate(d)
        }
    }

    /// Registers a delegate if it is not already in the delegate list.
    ///
    /// - Parameter delegate: The object to add as a connection delegate.
    public func addDelegate(_ delegate: ConnectionDelegate) {
        if !delegates.contains(where: { $0 === delegate }) {
            self.delegates.append(delegate)
        }
        Logger.debug("Connection \(self) addDelegate : \(delegate) \(delegates.count)")
    }

    /// Removes a previously registered delegate.
    ///
    /// - Parameter delegate: The delegate to remove. No-op if the delegate is not registered.
    public func removeDelegate(_ delegate: ConnectionDelegate) {
        if let index = delegates.firstIndex(where: { $0 === delegate }) {
            delegates.remove(at: index)
        }
        Logger.debug("Connection \(self) removeDelegate : \(delegate) \(delegates.count)")
    }

//    public func connect(withUrl url: Url, cipher:P7Socket.CipherType = .ECDH_AES256_SHA256, compression:P7Socket.Compression = .DEFLATE, checksum:P7Socket.Checksum = .SHA2_256) -> Bool {
//        self.url    = url
//        self.socket = P7Socket(hostname: self.url.hostname, port: self.url.port, spec: self.spec)
//
//        self.socket.username    = url.login
//        self.socket.password    = url.password
//
//        self.socket.cipherType  = cipher
//        self.socket.compression = compression
//        self.socket.checksum    = checksum
//
//        if !self.socket.connect() {
//            for d in self.delegates {
//                DispatchQueue.main.async {
//                    if let error = self.socket.errors.first {
//                        d.connectionDidFailToConnect(connection: self, error: error)
//                    }
//                }
//            }
//            return false
//        }
//
//        for d in self.delegates {
//            DispatchQueue.main.async {
//                d.connectionDidConnect(connection: self)
//            }
//        }
//
//        if !self.clientInfo() {
//            return false
//        }
//
//        if !self.setUser() {
//            return false
//        }
//
//        if !self.login() {
//            return false
//        }
//
//        if self.interactive == true {
//            self.listen()
//        }
//
//        self.pingCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { (timer) in
//            if let lpd = self.lastPingDate {
//                let interval = Date().timeIntervalSince(lpd)
//                if interval > 65 {
//                    Logger.error("Lost ping, server is probably down, disconnecting...")
//
//                    if self.isConnected() {
//                        self.disconnect()
//                    }
//                }
//            }
//        })
//
//        return true
//
//    }

    /// Opens the socket, performs the full Wired handshake, and (when `interactive` is `true`) starts the background read loop.
    ///
    /// The sequence is: TCP connect → `wired.client_info` → `wired.user.set_nick/status/icon` → `wired.send_login`.
    /// Delegates receive `connectionDidConnect` before the handshake and `connectionDidLogin` after.
    ///
    /// - Parameters:
    ///   - url: The `Url` containing hostname, port, login, and password.
    ///   - cipher: TLS cipher suite to negotiate. Defaults to ECDH + AES-256 + SHA-256.
    ///   - compression: Payload compression algorithm. Defaults to DEFLATE.
    ///   - checksum: Checksum algorithm for message integrity. Defaults to SHA-256.
    /// - Throws: Any `Error` thrown by the socket or handshake steps. Delegates also receive
    ///   `connectionDidFailToConnect` when the initial TCP connect fails.
    public func connect(withUrl url: Url, cipher: P7Socket.CipherType = .ECDH_AES256_SHA256, compression: P7Socket.Compression = .DEFLATE, checksum: P7Socket.Checksum = .SHA2_256) throws {
        self.url    = url
        self.socket = P7Socket(hostname: self.url.hostname, port: self.url.port, spec: self.spec)

        self.socket.username    = url.login
        self.socket.password    = url.password

        self.socket.cipherType  = cipher
        self.socket.compression = compression
        self.socket.checksum    = checksum
        self.socket.serverTrustHandler = self.serverTrustHandler

        do {
            try self.socket.connect()
        } catch {
            for d in self.delegates {
                DispatchQueue.main.async {
                    d.connectionDidFailToConnect(connection: self, error: error)
                }
            }

            throw error
        }

        for d in self.delegates {
            DispatchQueue.main.async {
                d.connectionDidConnect(connection: self)
            }
        }

        try self.clientInfo()
        try self.setUser()
        try self.login()

        if self.interactive == true {
            self.listen()
        }

        self.pingCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { (_) in
            if let lpd = self.lastPingDate {
                let interval = Date().timeIntervalSince(lpd)
                if interval > 65 {
                    Logger.error("Lost ping, server is probably down, disconnecting...")

                    if self.isConnected() {
                        self.disconnect()
                    }
                }
            }
        })
    }

    /// Tears down the current socket and re-runs the full connection and handshake sequence
    /// using the same URL and negotiated parameters.
    ///
    /// - Throws: Any `Error` thrown during socket reconnect or handshake.
    public func reconnect() throws {
        self.pingCheckTimer.invalidate()
        self.pingCheckTimer = nil

        let cipher      = self.socket.cipherType
        let compression = self.socket.compression
        let checksum    = self.socket.checksum

        self.socket.disconnect()

        self.socket = P7Socket(hostname: self.url.hostname, port: self.url.port, spec: self.spec)

        self.socket.username    = self.url.login
        self.socket.password    = self.url.password

        self.socket.cipherType  = cipher
        self.socket.compression = compression
        self.socket.checksum    = checksum
        self.socket.serverTrustHandler = self.serverTrustHandler

        try self.socket.connect()
        try self.clientInfo()
        try self.setUser()
        try self.login()

        if self.interactive == true {
            self.listen()
        }

        self.pingCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { (_) in
            if let lpd = self.lastPingDate {
                let interval = Date().timeIntervalSince(lpd)
                if interval > 65 {
                    Logger.error("Lost ping, server is probably down, disconnecting...")

                    if self.isConnected() {
                        self.disconnect()
                    }
                }
            }
        })
    }

    /// Closes the connection, stops the background listener, and notifies all delegates on the main queue.
    ///
    /// Idempotent — safe to call even if the socket is already `nil` or not connected.
    public func disconnect() {
        NotificationCenter.default.post(name: .linkConnectionWillDisconnect, object: self)

        self.stopListening()

        // `socket` is an IUO and may legitimately be nil in some teardown / restore scenarios
        // (e.g. when transfers are resumed after app relaunch). Make disconnect idempotent.
        if self.socket != nil {
            self.socket.disconnect()
        }

        DispatchQueue.main.async {

            NotificationCenter.default.post(name: .linkConnectionDidClose, object: self)

            for d in self.delegates {
                d.connectionDisconnected(connection: self, error: nil)
            }
        }
    }

    /// Returns `true` when the underlying socket reports it is connected.
    public func isConnected() -> Bool {
        return self.socket?.connected ?? false
    }

    /// Returns `true` if the given privilege key was granted in the server's account privileges message.
    ///
    /// - Parameter key: A Wired account privilege field name, e.g. `"wired.account.user.get_users"`.
    public func hasPrivilege(key: String) -> Bool {
        return self.privileges.contains(key)
    }

    /// Returns `true` if the account holds at least one administration-level privilege
    /// (settings, user management, log, banlist, or events).
    public func hasAdministrationPrivileges() -> Bool {
        return  self.hasPrivilege(key: "wired.account.settings.get_settings")   ||
                self.hasPrivilege(key: "wired.account.settings.set_settings")   ||
                self.hasPrivilege(key: "wired.account.user.get_users")          ||
                self.hasPrivilege(key: "wired.account.log.view_log")            ||
                self.hasPrivilege(key: "wired.account.banlist.get_bans")        ||
                self.hasPrivilege(key: "wired.account.events.view_events")
    }

    /// Stamps `message` with the next transaction ID, writes it to the socket, and notifies
    /// `connectionDidSendMessage` delegates on the main queue.
    ///
    /// - Parameter message: The `P7Message` to send. The `wired.transaction` field is set automatically.
    /// - Returns: `true` on a successful socket write; `false` when not connected or the write fails.
    @discardableResult
    public func send(message: P7Message) -> Bool {
        if self.socket.connected {
            message.addParameter(field: "wired.transaction", value: transactionCounter)

            transactionCounter += 1

            let r = self.socket.write(message)

            DispatchQueue.main.async {
                for d in self.delegates {
                    d.connectionDidSendMessage(connection: self, message: message)
                }
            }

            return r
        }
        return false
    }

    /// Reads and returns the next `P7Message` from the socket synchronously.
    ///
    /// Intended for use when `interactive` is `false` and the caller drives the read loop manually.
    ///
    /// - Returns: The next decoded `P7Message`.
    /// - Throws: Any socket or decoding error.
    public func readMessage() throws -> P7Message {
        return try self.socket.readMessage()
    }

    /// Sends a `wired.chat.join_chat` message for the specified chat room.
    ///
    /// - Parameter chatID: The numeric identifier of the chat room to join.
    /// - Returns: `true` if the message was sent successfully.
    public func joinChat(chatID: UInt32) -> Bool {
        let message = P7Message(withName: "wired.chat.join_chat", spec: self.spec)

        message.addParameter(field: "wired.chat.id", value: chatID)

        if !self.send(message: message) {
            return false
        }

        return true
    }

    private func listen() {
        self.stopListening()

        // we use a worker to ensure previous thread was terminated
        listener = DispatchWorkItem {
           while self.interactive == true && self.socket.connected == true {
               do {
                   let message = try self.socket.readMessage()

                   if self.interactive == true {
                       self.handleMessage(message)
                   }
               } catch let error {
                   if self.isConnected() {
                       print("self.socket error : \(self.socket.errors)")
                       self.disconnect()
                   }
               }
           }
        }

        DispatchQueue.global().async(execute: listener)
    }

    /// Cancels the background read loop started by `connect(withUrl:)`.
    ///
    /// After calling this method no further delegate callbacks will be triggered by incoming messages.
    public func stopListening() {
        if let l = listener {
            l.cancel()
            listener = nil
        }
    }

    internal func handleMessage(_ message: P7Message) {
        self.lastPingDate = Date()

        switch message.name {
        case "wired.send_ping":
            self.pingReply()

        case "wired.error":
            for d in self.delegates {
                DispatchQueue.main.async {
                    d.connectionDidReceiveError(connection: self, message: message)
                }
            }

        default:
            if message.name == "wired.server_info" {
                self.serverInfo = ServerInfo(message: message)

                DispatchQueue.main.async {
                    if let d = self.serverInfoDelegate {
                        d.serverInfoDidChange(for: self)
                    }
                }
            }

            for d in self.delegates {
                DispatchQueue.main.async {
                    d.connectionDidReceiveMessage(connection: self, message: message)
                }
            }
        }
    }

    internal func pingReply() {
        _ = self.send(message: P7Message(withName: "wired.ping", spec: self.spec))

        self.lastPingDate = Date()
    }

    private func setNick() throws {
        let message = P7Message(withName: "wired.user.set_nick", spec: self.spec)

        message.addParameter(field: "wired.user.nick", value: self.nick)

        try self.send(message: message)
        try self.socket.readMessage()
    }

    private func setStatus() throws {
        let message = P7Message(withName: "wired.user.set_status", spec: self.spec)

        message.addParameter(field: "wired.user.status", value: self.status)

        try self.send(message: message)
        try self.socket.readMessage()
    }

    private func setIcon() throws {
        let message = P7Message(withName: "wired.user.set_icon", spec: self.spec)

        message.addParameter(field: "wired.user.icon", value: Data(base64Encoded: self.icon, options: .ignoreUnknownCharacters))

        try self.send(message: message)
        try self.socket.readMessage()
    }

    private func setUser() throws {
        try self.setNick()
        try self.setStatus()
        try self.setIcon()
    }

    private func login() throws {
        let message = P7Message(withName: "wired.send_login", spec: self.spec)

        message.addParameter(field: "wired.user.login", value: self.url!.login)

        var password = "".sha256()

        if let pass = self.url?.password, !pass.isEmpty {
            password = self.url!.password.sha256()
        }

        message.addParameter(field: "wired.user.password", value: password)

        _ = self.send(message: message)

        let response = try self.socket.readMessage()

        if let uid = response.uint32(forField: "wired.user.id") {
            self.userID = uid
        }

        DispatchQueue.main.async {
            for d in self.delegates {
                d.connectionDidLogin(connection: self, message: response)
            }
        }

        // read account priviledges
        let privilegesMessage = try self.socket.readMessage()

        privilegesMessage.parameterKeys.forEach({ (key) in
            self.privileges.append(key)
        })

        DispatchQueue.main.async {
            for d in self.delegates {
                d.connectionDidReceivePriviledges(connection: self, message: privilegesMessage)
            }
        }
    }

    private func clientInfo() throws {
        let message = P7Message(withName: "wired.client_info", spec: self.spec)
        let applicationInfo = WiredApplicationInfo.current().overriding(
            name: self.clientInfoDelegate?.clientInfoApplicationName(for: self),
            version: self.clientInfoDelegate?.clientInfoApplicationVersion(for: self),
            build: self.clientInfoDelegate?.clientInfoApplicationBuild(for: self)
        )

        if let value = applicationInfo.name {
            message.addParameter(field: "wired.info.application.name", value: value)
        }

        if let value = applicationInfo.version {
            message.addParameter(field: "wired.info.application.version", value: value)
        }

        if let value = applicationInfo.build {
            message.addParameter(field: "wired.info.application.build", value: value)
        }

        #if os(iOS)
        message.addParameter(field: "wired.info.os.name", value: "iOS")
        #elseif os(macOS)
        message.addParameter(field: "wired.info.os.name", value: "macOS")
        #elseif os(visionOS)
        message.addParameter(field: "wired.info.os.name", value: "visionOS")
        #else
        message.addParameter(field: "wired.info.os.name", value: "Linux")
        #endif

        message.addParameter(field: "wired.info.os.version", value: ProcessInfo.processInfo.operatingSystemVersionString)
        message.addParameter(field: "wired.info.arch", value: machineArchitecture())
        message.addParameter(field: "wired.info.supports_rsrc", value: false)

        _ = self.send(message: message)

        let response = try self.socket.readMessage()

        self.serverInfo = ServerInfo(message: response)
    }

    // MARK: -

    private func machineArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)

        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }

        return machine
    }
}

/// Strongly-typed network errors that the P7 socket layer can surface instead of raw `errno` values.
public enum NetworkError: Error, Equatable {

    // MARK: - DNS / Address resolution

    case dnsFailure(host: String, code: Int32)
    case invalidAddress(host: String)
    case unsupportedAddressFamily

    // MARK: - Connection lifecycle

    case connectionRefused(host: String, port: Int)
    case connectionTimedOut(host: String, port: Int)
    case hostUnreachable(host: String)
    case networkUnreachable
    case connectionReset
    case connectionAborted
    case alreadyConnected
    case notConnected

    // MARK: - Socket state

    case socketClosed
    case socketNotOpen
    case brokenPipe
    case shutdown

    // MARK: - IO

    case readFailed(errno: Int32)
    case writeFailed(errno: Int32)
    case interrupted

    // MARK: - TLS / Security (si tu ajoutes TLS plus tard)

    case tlsHandshakeFailed
    case tlsInvalidCertificate
    case tlsCertificateExpired

    // MARK: - Timeout / Flow

    case readTimedOut
    case writeTimedOut

    // MARK: - Resource / System

    case noFileDescriptors
    case noMemory
    case permissionDenied

    // MARK: - Application / Protocol

    case invalidResponse
    case protocolViolation(reason: String)
    case payloadTooLarge

    // MARK: - Fallback

    case unknown(errno: Int32)
}

extension NetworkError {

    static func fromErrno(
        _ errno: Int32,
        host: String,
        port: Int
    ) -> NetworkError {

        switch errno {

        // Connection
        case ECONNREFUSED:
            return .connectionRefused(host: host, port: port)

        case ETIMEDOUT:
            return .connectionTimedOut(host: host, port: port)

        case ENETUNREACH:
            return .networkUnreachable

        case EHOSTUNREACH:
            return .hostUnreachable(host: host)

        case ECONNRESET:
            return .connectionReset

        case ECONNABORTED:
            return .connectionAborted

        case EISCONN:
            return .alreadyConnected

        case ENOTCONN:
            return .notConnected

        // IO
        case EPIPE:
            return .brokenPipe

        case EINTR:
            return .interrupted

        // Permissions / resources
        case EACCES:
            return .permissionDenied

        case EMFILE, ENFILE:
            return .noFileDescriptors

        case ENOMEM:
            return .noMemory

        // Fallback
        default:
            return .unknown(errno: errno)
        }
    }
}

extension NetworkError: LocalizedError {

    public var errorDescription: String? {
        switch self {

        case .dnsFailure(let host, _):
            return "DNS resolution failed for \(host)"

        case .connectionRefused(let host, let port):
            return "Connection refused by \(host):\(port)"

        case .connectionTimedOut(let host, let port):
            return "Connection to \(host):\(port) timed out"

        case .hostUnreachable(let host):
            return "Host \(host) is unreachable"

        case .networkUnreachable:
            return "Network is unreachable"

        case .brokenPipe:
            return "Connection closed by peer"

        case .permissionDenied:
            return "Permission denied"

        case .notConnected:
            return "Socket is not connected"

        case .unknown(let errno):
            return "Unknown network error (errno \(errno))"

        default:
            return "Network error"
        }
    }
}
