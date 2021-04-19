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




open class Connection: NSObject {
    public var spec:        P7Spec
    public var url:         Url!
    public var socket:      P7Socket!
    public var delegates:   [ConnectionDelegate] = []
    public var clientInfoDelegate:ClientInfoDelegate?
    public var interactive: Bool = true
    
    public var userID: UInt32!
    public var userInfo: UserInfo?
    
    public var nick: String     = "Swift Wired"
    public var status: String   = ""
    public var icon: String     = Wired.defaultUserIcon
    
    public var serverInfo: ServerInfo!
    
    private var lastPingDate:Date!
    private var pingCheckTimer:Timer!
    
    private var listener:DispatchWorkItem!
    
    public var URI:String {
        get {
            return "\(self.url.login)@\(self.url.hostname):\(self.url.port)"
        }
    }
    
    public init(withSpec spec: P7Spec, delegate: ConnectionDelegate? = nil) {
        self.spec = spec
        
        super.init()
        
        if let d = delegate {
            self.addDelegate(d)
        }
    }
    
    
    public func addDelegate(_ delegate:ConnectionDelegate) {
        if delegates.firstIndex(where: { $0 === delegate }) == nil {
            self.delegates.append(delegate)
        }
        print("addDelegate : \(delegate) \(delegates.count)")
    }
    
    public func removeDelegate(_ delegate:ConnectionDelegate) {
        if let index = delegates.firstIndex(where: { $0 === delegate }) {
            delegates.remove(at: index)
        }
        print("removeDelegate : \(delegate) \(delegates.count)")
    }
    
    
    public func connect(withUrl url: Url, cipher:P7Socket.CipherType = .ECDH_CHACHA20_SHA256, compression:P7Socket.Compression = .DEFLATE, checksum:P7Socket.Checksum = .SHA3_256) -> Bool {
        self.url    = url
        
        self.socket = P7Socket(hostname: self.url.hostname, port: self.url.port, spec: self.spec)
        
        self.socket.username    = url.login
        self.socket.password    = url.password
        
        self.socket.cipherType  = cipher
        self.socket.compression = compression
        self.socket.checksum    = checksum

        if !self.socket.connect() {
            return false
        }
        
        for d in self.delegates {
            DispatchQueue.main.async {
                d.connectionDidConnect(connection: self)
            }
        }
        
        if !self.clientInfo() {
            return false
        }
        
        if !self.setUser() {
            return false
        }
        
        if !self.login() {
            return false
        }
        
        if self.interactive == true {
            self.listen()
        }
        
        self.pingCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { (timer) in
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
        
        return true

    }
    
    
    public func reconnect() -> Bool {
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
        self.socket.compression = compression // TODO: Gzip deflate still not implemented
        self.socket.checksum    = checksum
                
        if !self.socket.connect() {
            return false
        }
        
        if !self.clientInfo() {
            return false
        }
        
        if !self.setUser() {
            return false
        }
        
        if !self.login() {
            return false
        }
        
        if self.interactive == true {
            self.listen()
        }
        
        self.pingCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { (timer) in
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
        
        return true
    }
    
    
    public func disconnect() {
        NotificationCenter.default.post(name: .linkConnectionWillDisconnect, object: self)
        
        self.stopListening()
        self.socket.disconnect()
 
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
    
    
    public func send(message:P7Message) -> Bool {
        if self.socket.connected {
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

    
    
    private func setNick() -> Bool {
        let message = P7Message(withName: "wired.user.set_nick", spec: self.spec)
        
        message.addParameter(field: "wired.user.nick", value: self.nick)
        
        if !self.send(message: message) {
            return false
        }
        
        if self.socket.readMessage() == nil {
            return false
        }
        
        return true
    }
    
    
    private func setStatus() -> Bool {
        let message = P7Message(withName: "wired.user.set_status", spec: self.spec)
        
        message.addParameter(field: "wired.user.status", value: self.status)
        
        if !self.send(message: message) {
            return false
        }
        
        if self.socket.readMessage() == nil {
            return false
        }
        
        return true
    }
    
    
    private func setIcon() -> Bool {
        let message = P7Message(withName: "wired.user.set_icon", spec: self.spec)
        
        message.addParameter(field: "wired.user.icon", value: Data(base64Encoded: self.icon, options: .ignoreUnknownCharacters))
        
        if !self.send(message: message) {
            return false
        }
        
        if self.socket.readMessage() == nil {
            return false
        }
        
        return true
    }
    
    
    
    private func setUser() -> Bool {
        if !self.setNick() {
            return false
        }
        
        if !self.setStatus() {
            return false
        }
        
        if !self.setIcon() {
            return false
        }
        
        return true
    }
    
    
    private func login() -> Bool  {
        let message = P7Message(withName: "wired.send_login", spec: self.spec)
        
        message.addParameter(field: "wired.user.login", value: self.url!.login)
        
        var password = "".sha256()
        
        if self.url?.password != nil && self.url?.password != "" {
            password = self.url!.password.sha256()
        }
                
        message.addParameter(field: "wired.user.password", value: password)
        
        _ = self.send(message: message)
                
        guard let response = self.socket.readMessage() else {
            return false
        }
        
        if let uid = response.uint32(forField: "wired.user.id") {
            self.userID = uid
        }
        
        // read account priviledges
        _ = self.socket.readMessage()

        return true
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
        
        _ = self.send(message: message)
                
        guard let response = self.socket.readMessage() else {
            print("no response ?")
            return false
        }
                        
        self.serverInfo = ServerInfo(message: response)
        
        return true
    }
    
    
    // MARK: -

    
}
