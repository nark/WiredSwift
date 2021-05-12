//
//  Connection.swift
//  Wired 3
//
//  Created by Rafael Warnault on 18/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation
import Dispatch
import NIO
import NIOFoundationCompat






extension Notification.Name {
    public static let linkConnectionWillDisconnect     = Notification.Name("linkConnectionWillDisconnect")
    public static let linkConnectionDidClose           = Notification.Name("linkConnectionDidClose")
    public static let linkConnectionDidReconnect       = Notification.Name("linkConnectionDidReconnect")
    public static let linkConnectionDidFailReconnect   = Notification.Name("linkConnectionDidFailReconnect")
}


public protocol ConnectionDelegate: class {
    func connectionDidConnect(connection: Connection)
    func connectionDidFailToConnect(connection: Connection, error: Error)
    func connectionDisconnected(connection: Connection, error: Error?)
    func connectionDidSendMessage(connection: Connection, message: P7Message)
    func connectionDidReceiveMessage(connection: Connection, message: P7Message)
    func connectionDidReceiveError(connection: Connection, message: P7Message)
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





open class Connection: NSObject, SocketChannelDelegate {
    public var spec:        P7Spec
    public var url:         Url!
    public var socket:      P7Socket!
    public var delegates:   [ConnectionDelegate] = []
    public var clientInfoDelegate:ClientInfoDelegate?
    public var serverInfoDelegate:ServerInfoDelegate?
    public var interactive: Bool = true
    
    public var userID: UInt32!
    public var userInfo: UserInfo?
    public var privileges:[String] = []
    
    public var nick: String     = "Swift Wired"
    public var status: String   = ""
    public var icon: String     = Wired.defaultUserIcon
    
    public var serverInfo: ServerInfo!
    
    private var lastPingDate:Date!
    private var pingCheckTimer:Timer!
    
    private var listener:DispatchWorkItem!
    
    private var group:MultiThreadedEventLoopGroup!
    private var bootstrap:ClientBootstrap!
    private var channel:Channel!
    
    private var state:ConnectState
    private var userInfoCounter:Int = 0
    
    enum ConnectState: Int, Comparable {
        case clientInfo     = 0
        case clientUser
        case clientLogin
        case clientLoggedIn
        case clientPrivileges
        
        static func < (lhs: Connection.ConnectState, rhs: Connection.ConnectState) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
    }
    
    
    
    public var URI:String {
        get {
            return "\(self.url.login)@\(self.url.hostname):\(self.url.port)"
        }
    }
    
    public init(withSpec spec: P7Spec, delegate: ConnectionDelegate? = nil) {
        self.spec = spec
        self.state = .clientInfo
        
        super.init()
        
        if let d = delegate {
            self.addDelegate(d)
        }
    }
    
    
    public func addDelegate(_ delegate:ConnectionDelegate) {
        if delegates.firstIndex(where: { $0 === delegate }) == nil {
            self.delegates.append(delegate)
        }
        Logger.debug("Connection \(self) addDelegate : \(delegate) \(delegates.count)")
    }
    
    public func removeDelegate(_ delegate:ConnectionDelegate) {
        if let index = delegates.firstIndex(where: { $0 === delegate }) {
            delegates.remove(at: index)
        }
        Logger.debug("Connection \(self) removeDelegate : \(delegate) \(delegates.count)")
    }
    
    
    public func connect(withUrl url: Url, cipher:CipherType = .ECDH_AES256_SHA256, compression:Compression = .DEFLATE, checksum:Checksum = .SHA2_256) -> Bool {
        self.url    = url
        self.socket = P7Socket(spec: self.spec, originator: Originator.Client)

        self.socket.username    = url.login
        self.socket.password    = url.password

        self.socket.cipherType  = cipher
        self.socket.compression = compression
        self.socket.checksum    = checksum
        self.socket.channelDelegate = self
        
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(P7MessageDecoder(withSocket: self.socket)),
                    self.socket
                ])
            }
        
        guard let channel = try? bootstrap.connect(host: self.url.hostname, port: self.url.port).wait() else {
            for d in self.delegates {
                DispatchQueue.main.async {
                    if let error = self.socket.errors.first {
                        d.connectionDidFailToConnect(connection: self, error: error)
                    }
                }
            }
            return false
        }
        
        self.channel = channel
        
        let promise = channel.eventLoop.makePromise(of: Channel.self)

        self.socket.handshake(promise: promise).whenSuccess({ (channel) in
            if self.state == .clientInfo {
                _ = self.clientInfo()
            }
        })
                
        try! channel.closeFuture.wait()
        
        return true
    }
    
    
    public func reconnect() -> Bool {
        // disconnect/clean
        if self.pingCheckTimer != nil {
            self.pingCheckTimer.invalidate()
            self.pingCheckTimer = nil
        }

        let cipher      = self.socket.cipherType
        let compression = self.socket.compression
        let checksum    = self.socket.checksum

        self.socket.disconnect()
        self.state = .clientInfo
        
        // connect
        self.socket = P7Socket(spec: self.spec, originator: Originator.Client)

        self.socket.username    = url.login
        self.socket.password    = url.password

        self.socket.cipherType  = cipher
        self.socket.compression = compression
        self.socket.checksum    = checksum
        self.socket.channelDelegate = self
        
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(P7MessageDecoder(withSocket: self.socket)),
                    self.socket
                ])
            }
        
        guard let channel = try? bootstrap.connect(host: self.url.hostname, port: self.url.port).wait() else {
            for d in self.delegates {
                DispatchQueue.main.async {
                    if let error = self.socket.errors.first {
                        d.connectionDidFailToConnect(connection: self, error: error)
                    }
                }
            }
            return false
        }
        
        self.channel = channel
        
        let promise = channel.eventLoop.makePromise(of: Channel.self)

        self.socket.handshake(promise: promise).whenSuccess({ (channel) in
            if self.state == .clientInfo {
                _ = self.clientInfo()
            }
        })
                
        try! channel.closeFuture.wait()
                
        return true
    }
    
    
    public func disconnect() {
        self.socket.disconnect()
        
        NotificationCenter.default.post(name: .linkConnectionWillDisconnect, object: self)
        
        defer {
            try! group.syncShutdownGracefully()
        }
 
        DispatchQueue.main.async {
            
            NotificationCenter.default.post(name: .linkConnectionDidClose, object: self)
        
            for d in self.delegates {
                d.connectionDisconnected(connection: self, error: nil)
            }
        }
    }
    
    
    public func isConnected() -> Bool {
        return self.socket.connected
    }
    
    
    
    // MARK: -
    public func channelConnected(socket: P7Socket, channel: Channel) {
        
    }
    
    public func channelDisconnected(socket: P7Socket, channel: Channel) {
        
    }
    
    public func channelAuthenticated(socket: P7Socket, channel: Channel) {
        
    }
    
    public func channelAuthenticationFailed(socket: P7Socket, channel: Channel) {
        
    }
    
    public func channelReceiveMessage(message: P7Message, socket: P7Socket, channel: Channel) {
        self.handleMessage(message)
    }
    
    
    
    
    
    
    
    
    
    // MARK: -
    
    public func hasPrivilege(key:String) -> Bool {
        return self.privileges.firstIndex(of: key) != nil ? true : false
    }
    
    
    public func hasAdministrationPrivileges() -> Bool {
        return  self.hasPrivilege(key: "wired.account.settings.get_settings")   ||
                self.hasPrivilege(key: "wired.account.settings.set_settings")   ||
                self.hasPrivilege(key: "wired.account.user.get_users")          ||
                self.hasPrivilege(key: "wired.account.log.view_log")            ||
                self.hasPrivilege(key: "wired.account.banlist.get_bans")        ||
                self.hasPrivilege(key: "wired.account.events.view_events")
    }
    
    
    @discardableResult
    public func send(message:P7Message) -> Bool {
        if self.socket.connected {
            let r = self.socket.write(message, channel: self.channel)
            
            DispatchQueue.main.async {
                for d in self.delegates {
                    d.connectionDidSendMessage(connection: self, message: message)
                }
            }
            
            return r
        }
        return false
    }
    
    
    public func readMessage() -> P7Message? {
        if self.socket.connected {
            return self.socket.readMessage()
        }
        return nil
    }

    
    
    
    public func joinChat(chatID: UInt32) -> Bool  {
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
           while (self.interactive == true && self.socket.connected == true) {
               if let message = self.socket.readMessage() {
                    if self.interactive == true {
                        self.handleMessage(message)
                    }
               } else {
                    if self.isConnected() {
                        print("self.socket error : \(self.socket.errors)")
                        self.disconnect()
                    }
               }
           }
        }
        
        DispatchQueue.global().async(execute: listener)
    }
    
    
    public func stopListening() {
        if let l = listener {
            l.cancel()
            listener = nil
        }
    }
    
    
    
    internal func handleMessage(_ message:P7Message) {
        if self.state < .clientPrivileges {
            switch self.state {
            case .clientInfo:
                if message.name == "wired.server_info" {
                    self.serverInfo = ServerInfo(message: message)
                    self.state = .clientUser
                    
                    _ = self.setUser()
                }
            case .clientUser:
                if message.name == "wired.okay" {
                    self.userInfoCounter += 1
                    
                    if self.userInfoCounter == 3 {
                        self.state = .clientLogin
                        
                        _ = self.login()
                        
                        self.userInfoCounter = 0
                    }
                }
            case .clientLogin:
                if message.name == "wired.login" {
                    if let uid = message.uint32(forField: "wired.user.id") {
                        self.userID = uid
                        self.state  = .clientLoggedIn
                    }
                }
            default:
                if message.name == "wired.account.privileges" && self.state == .clientLoggedIn {
                    message.parameterKeys.forEach({ (key) in
                        self.privileges.append(key)
                    })
                    
                    self.state = .clientPrivileges
                    
                    for d in self.delegates {
                        DispatchQueue.main.async {
                            d.connectionDidConnect(connection: self)
                        }
                    }
                }
            }

        } else {
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
    }
    
    
    
    internal func pingReply() {
        _ = self.send(message: P7Message(withName: "wired.ping", spec: self.spec))
        
        self.lastPingDate = Date()
    }

    
    
    private func setNick() -> Bool {
        let message = P7Message(withName: "wired.user.set_nick", spec: self.spec)
        
        message.addParameter(field: "wired.user.nick", value: self.nick)
        
        return self.send(message: message)
    }
    
    
    private func setStatus() -> Bool {
        let message = P7Message(withName: "wired.user.set_status", spec: self.spec)
        
        message.addParameter(field: "wired.user.status", value: self.status)
        
        return self.send(message: message)
    }
    
    
    private func setIcon() -> Bool {
        let message = P7Message(withName: "wired.user.set_icon", spec: self.spec)
        
        message.addParameter(field: "wired.user.icon", value: Data(base64Encoded: self.icon, options: .ignoreUnknownCharacters))
        
        return self.send(message: message)
    }
    
    
    
    private func setUser() -> Bool {
        var ok = false
        
        ok = self.setNick()
        ok = self.setStatus()
        ok = self.setIcon()
        
        return ok
    }
    
    
    private func login() -> Bool  {
        let message = P7Message(withName: "wired.send_login", spec: self.spec)
        
        message.addParameter(field: "wired.user.login", value: self.url!.login)
        
        var password = "".sha256()
        
        if self.url?.password != nil && self.url?.password != "" {
            password = self.url!.password.sha256()
        }
                
        message.addParameter(field: "wired.user.password", value: password)
                                
        return self.send(message: message)
    }
    
    
    private func clientInfo() -> Bool {
        let message = P7Message(withName: "wired.client_info", spec: self.spec)
        message.addParameter(field: "wired.info.application.name", value: "Wired Client")
        
        if let value = self.clientInfoDelegate?.clientInfoApplicationName(for: self) {
            message.addParameter(field: "wired.info.application.name", value: value)
        }
        
        message.addParameter(field: "wired.info.application.version", value: "3.0")
        if let value = self.clientInfoDelegate?.clientInfoApplicationVersion(for: self) {
            message.addParameter(field: "wired.info.application.version", value: value)
        }
        
        message.addParameter(field: "wired.info.application.build", value: "alpha")
        if let value = self.clientInfoDelegate?.clientInfoApplicationBuild(for: self) {
            message.addParameter(field: "wired.info.application.build", value: value)
        }
        
        
        #if os(iOS)
        message.addParameter(field: "wired.info.os.name", value: "iOS")
        #elseif os(macOS)
        message.addParameter(field: "wired.info.os.name", value: "macOS")
        #else
        message.addParameter(field: "wired.info.os.name", value: "Linux")
        #endif
        
        message.addParameter(field: "wired.info.os.version", value: ProcessInfo.processInfo.operatingSystemVersionString)
        
        #if os(iOS)
        message.addParameter(field: "wired.info.arch", value: "armv7")
        #elseif os(macOS)
        message.addParameter(field: "wired.info.arch", value: "x86_64")
        #else
        message.addParameter(field: "wired.info.arch", value: "x86_64")
        #endif
        
        message.addParameter(field: "wired.info.supports_rsrc", value: false)
                        
        return self.send(message: message)
    }
}
