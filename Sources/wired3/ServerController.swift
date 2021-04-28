//
//  ServerController.swift
//  wired3
//
//  Created by Rafael Warnault on 16/03/2021.
//

import Foundation
import WiredSwift
import SocketSwift


let SERVER_COMPRESSION  = P7Socket.Compression.ALL
let SERVER_CIPHER       = P7Socket.CipherType.ALL
let SERVER_CHECKSUM     = P7Socket.Checksum.ALL
    



public protocol ServerDelegate: class {
    func clientDisconnected(client:Client)
    func disconnectClient(client:Client)
    
    func receiveMessage(client:Client, message:P7Message)
}


public class ServerController: ServerDelegate {
    public var port: Int = DEFAULT_PORT
    public var spec: P7Spec!
    public var isRunning:Bool = false
    public var delegates:[ServerDelegate] = []
    
    public var serverName:String = "Wired Server 3.0"
    public var serverDescription:String = "Welcome to this new Wired server"
    public var downloads:UInt32 = 0
    public var uploads:UInt32 = 0
    public var downloadSpeed:UInt32 = 0
    public var uploadSpeed:UInt32 = 0
    
    private var socket:Socket!
    private let ecdh = ECDH()
    private let group = DispatchGroup()
    
    var startTime:Date? = nil
    
    
    
    public init(port: Int, spec: P7Spec) {
       self.port = port
       self.spec = spec
        
        self.addDelegate(self)
    }
    
    public func listen() {
        self.startTime = Date()

        group.enter()
        
        do {
            self.socket = try Socket(.inet, type: .stream, protocol: .tcp)
            try self.socket.set(option: .reuseAddress, true) // set SO_REUSEADDR to 1
            try self.socket.bind(port: Port(self.port), address: nil) // bind 'localhost:8090' address to the socket
            
            DispatchQueue.global(qos: .default).async {
                self.isRunning = true
                
                self.listenThread()
                
                self.group.leave()
            }
        } catch let error {
            if let socketError = error as? Socket.Error {
                Logger.error(socketError.description)
            } else {
                Logger.error(error.localizedDescription)
            }
            
        }
        
        group.wait()
    }
    
    
    public func addDelegate(_ delegate:ServerDelegate) {
        self.delegates.append(delegate)
    }
    
    
    public func removeDelegate(_ delegate:ServerDelegate) {
        if let index = self.delegates.firstIndex(where: { (d) -> Bool in
            d === delegate
        }) {
            self.delegates.remove(at: index)
        }
    }
    
    
    
    
    // MARK: - ServerDelegate
    public func clientDisconnected(client:Client) {
        self.disconnectClient(client: client)
    }
    
    
    public func disconnectClient(client: Client) {
        App.chatsController.userLeave(client: client)
        App.clientsController.removeClient(client: client)
    }
    
    
    
    public func receiveMessage(client:Client, message:P7Message) {
        if client.state == .CONNECTED {
            if message.name != "wired.client_info" {
                Logger.error("Could not process message \(message.name!): Out of sequence")
                App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
                return
            }
        } else if client.state == .GAVE_CLIENT_INFO {
            if  message.name != "wired.user.set_nick"   &&
                message.name != "wired.user.set_status" &&
                message.name != "wired.user.set_icon"   &&
                message.name != "wired.send_login" &&
                message.name != "wired.send_ping" {
                Logger.error("Could not process message \(message.name!): Out of sequence")
                App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
                return
            }
        }
        
        self.handleMessage(client: client, message: message)
        
        // TODO: manage user idle time here
    }
    
    
    
    // MARK: -
    public func read(message:P7Message, client: Client) -> P7Message? {
        return client.socket?.readMessage()
    }
    
    @discardableResult
    public func send(message:P7Message, client: Client) -> Bool {
        if client.transfer == nil {
            return client.socket?.write(message) ?? false
        }
        
        return false
    }
    
    
    
    // MARK: -
    public func reply(client: Client, reply:P7Message, message:P7Message) {
        if let t = message.uint32(forField: "wired.transaction") {
            reply.addParameter(field: "wired.transaction", value: t)
        }
        
        _ = self.send(message: reply, client: client)
    }
    
    
    public func replyError(client: Client, error:String, message:P7Message?) {
        let reply = P7Message(withName: "wired.error", spec: client.socket!.spec)
        
        reply.addParameter(field: "wired.error.string", value: "Login failed")

        if let message = message {
            if let errorEnumValue = message.spec.errorsByName[error] {
                reply.addParameter(field: "wired.error", value: UInt32(errorEnumValue.id))
            }
            
            self.reply(client: client, reply: reply, message: message)
        } else {
            _ = self.send(message: reply, client: client)
        }
    }
    
    public func replyOK(client: Client, message:P7Message) {
        let reply = P7Message(withName: "wired.okay", spec: client.socket!.spec)
        
        self.reply(client: client, reply: reply, message: message)
    }
    

    
    // MARK: - Private
    private func handleMessage(client:Client, message:P7Message) {
        if message.name == "wired.client_info" {
            self.receiveClientInfo(client, message)
        }
        else if message.name == "wired.user.set_nick" {
            self.receiveUserSetNick(client, message)
        }
        else if message.name == "wired.user.set_status" {
            self.receiveUserSetStatus(client, message)
        }
        else if message.name == "wired.user.set_icon" {
            self.receiveUserSetIcon(client, message)
        }
        else if message.name == "wired.send_login" {
            if !self.receiveSendLogin(client, message) {
                // login failed
                self.disconnectClient(client: client)
            }
        }
        else if message.name == "wired.chat.get_chats" {
            App.chatsController.getChats(message: message, client: client)
        }
        else if message.name == "wired.chat.create_public_chat" {
            App.chatsController.createPublicChat(message: message, client: client)
        }
        else if message.name == "wired.chat.delete_public_chat" {
            App.chatsController.deletePublicChat(message: message, client: client)
        }
        else if message.name == "wired.chat.create_chat" {
            App.chatsController.createPrivateChat(message: message, client: client)
        }
        else if message.name == "wired.chat.invite_user" {
            App.chatsController.inviteUser(message: message, client: client)
        }
        else if message.name == "wired.chat.send_say" {
            App.chatsController.receiveChatSay(client, message)
        }
        else if message.name == "wired.chat.send_me" {
            App.chatsController.receiveChatMe(client, message)
        }
        else if message.name == "wired.chat.join_chat" {
            App.chatsController.userJoin(message: message, client: client)
        }
        else if message.name == "wired.chat.leave_chat" {
            App.chatsController.userLeave(message: message, client: client)
        }
        else if message.name == "wired.chat.set_topic" {
            App.chatsController.setTopic(message: message, client: client)
        }
        else if message.name == "wired.chat.kick_user" {
            //App.chatsController.kickUser(user: user, message: message)
        }
        else if message.name == "wired.file.list_directory" {
            App.filesController.listDirectory(client: client, message: message)
        }
        else if message.name == "wired.file.delete" {
            App.filesController.delete(client: client, message: message)
        }
        else if message.name == "wired.transfer.download_file" {
            self.receiveDownloadFile(client, message)
        }
        else if message.name == "wired.transfer.upload_file" {
            self.receiveUploadFile(client, message)
        }
        else if message.name == "wired.settings.get_settings" {
            self.receiveGetSettings(client: client, message: message)
        }
            else if message.name == "wired.settings.set_settings" {
                self.receiveSetSettings(client: client, message: message)
            }
        else {
            WiredSwift.Logger.warning("Message \(message.name ?? "unknow message") not implemented")
        }
    }
    
    
    
    private func receiveClientInfo(_ client:Client, _ message:P7Message) {
        client.state = .GAVE_CLIENT_INFO
                
        App.serverController.reply(client: client,
                                   reply: self.serverInfoMessage(),
                                   message: message)
    }
    
    
    private func receiveUserSetNick(_ client:Client, _ message:P7Message) {
        if let nick = message.string(forField: "wired.user.nick") {
            client.nick = nick
        }
                
        let response = P7Message(withName: "wired.okay", spec: self.spec)
        
        App.serverController.reply(client: client, reply: response, message: message)
        
        // broadcast if already logged in
        if client.state == .LOGGED_IN && client.user != nil {
            self.sendUserStatus(forClient: client)
        }
    }
    
    
    private func receiveUserSetStatus(_ client:Client, _ message:P7Message) {
        if let status = message.string(forField: "wired.user.status") {
            client.status = status
        }
        
        let response = P7Message(withName: "wired.okay", spec: self.spec)
        _ = self.send(message: response, client: client)
        
        // broadcast if already logged in
        if client.state == .LOGGED_IN && client.user != nil {
            self.sendUserStatus(forClient: client)
        }
    }
    
    
    private func receiveUserSetIcon(_ client:Client, _ message:P7Message) {
        if let icon = message.data(forField: "wired.user.icon") {
            client.icon = icon
        }
        
        let response = P7Message(withName: "wired.okay", spec: self.spec)
        _ = self.send(message: response, client: client)
        
        // broadcast if already logged in
        if client.state == .LOGGED_IN {
            self.sendUserStatus(forClient: client)
        }
    }
    
    
    private func receiveSendLogin(_ client:Client, _ message:P7Message) -> Bool {
        guard let login = message.string(forField: "wired.user.login") else {
            return false
        }
        
        guard let password = message.string(forField: "wired.user.password") else {
            return false
        }
        
        guard let user = App.usersController.user(withUsername: login, password: password) else {
            let reply = P7Message(withName: "wired.error", spec: message.spec)
            reply.addParameter(field: "wired.error.string", value: "Login failed")
            reply.addParameter(field: "wired.error", value: UInt32(4
            ))
            App.serverController.reply(client: client, reply: reply, message: message)
            
            Logger.error("Login failed for user '\(login)'")
            
            return false
        }
        
        client.user     = user
        client.state    = .LOGGED_IN
        
        let response = P7Message(withName: "wired.login", spec: self.spec)
        
        response.addParameter(field: "wired.user.id", value: client.userID)
        
        App.serverController.reply(client: client, reply: response, message: message)
        
        let response2 = P7Message(withName: "wired.account.privileges", spec: self.spec)
                
        for field in spec.accountPrivileges! {
            if user.hasPrivilege(name: field) {
                response2.addParameter(field: field, value: UInt32(1))
            }
        }
                
        App.serverController.reply(client: client, reply: response2, message: message)
        
        return true
    }
    
    
    
    private func receiveDownloadFile(_ client:Client, _ message:P7Message) {
        if !client.user!.hasPrivilege(name: "wired.account.transfer.download_files") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        guard let path = message.string(forField: "wired.file.path") else {
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }
        
        // file privileges
        if let privilege = FilePrivilege(path: App.filesController.real(path: path)) {
            if !client.user!.hasPermission(toRead: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }
        
        let dataOffset = message.uint64(forField: "wired.transfer.data_offset")
        let rsrcOffset = message.uint64(forField: "wired.transfer.rsrc_offset")
                
        if let transfer = App.transfersController.download(path: path,
                                                           dataOffset: dataOffset!,
                                                           rsrcOffset: rsrcOffset!,
                                                           client: client, message: message) {
            client.transfer = transfer
            
            if(App.transfersController.run(transfer: transfer, client: client, message: message)) {
                client.state = .DISCONNECTED
            }
            
            client.transfer = nil
        }
    }
    
    
    
    
    private func receiveUploadFile(_ client:Client, _ message:P7Message) {
        if !client.user!.hasPrivilege(name: "wired.account.transfer.upload_files") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        guard let path = message.string(forField: "wired.file.path") else {
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }
        
        let realPath = App.filesController.real(path: path)
        let parentPath = realPath.stringByDeletingLastPathComponent
        
        // file privileges
        if let privilege = FilePrivilege(path: realPath) {
            if !client.user!.hasPermission(toWrite: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }
        
        // user privileges
        if let type = File.FileType.type(path: parentPath) {
            switch type {
                case .directory:    if !client.user!.hasPrivilege(name: "wired.account.transfer.upload_files")      { return }; break
                case .uploads:      if !client.user!.hasPrivilege(name: "wired.account.transfer.upload_anywhere")   { return }; break
                default:            if !client.user!.hasPrivilege(name: "wired.account.transfer.upload_anywhere")   { return }; break
            }
        }
        
        let dataSize = message.uint64(forField: "wired.transfer.data_size") ?? UInt64(0)
        let rsrcSize = message.uint64(forField: "wired.transfer.rsrc_size") ?? UInt64(0)
        
        if let transfer = App.transfersController.upload(path: path,
                                                         dataSize: dataSize,
                                                         rsrcSize: rsrcSize,
                                                         executable: false,
                                                         client: client, message: message) {
            client.transfer = transfer
            
            client.socket.set(interactive: false)
                        
            if(!App.transfersController.run(transfer: transfer, client: client, message: message)) {
                client.state = .DISCONNECTED
            }
            
            client.transfer = nil
        }
    }
    
    
    
    
    // MARK: -
    
    private func receiveGetSettings(client:Client, message:P7Message) {
        if !client.user!.hasPrivilege(name: "wired.account.settings.get_settings") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        let response = P7Message(withName: "wired.settings.settings", spec: message.spec)
        response.addParameter(field: "wired.info.name", value: self.serverName)
        response.addParameter(field: "wired.info.description", value: self.serverDescription)
        
        if let data = try? Data(contentsOf: URL.init(fileURLWithPath: App.bannerPath)) {
            response.addParameter(field: "wired.info.banner", value: data)
        }
        
        response.addParameter(field: "wired.info.downloads", value: self.downloads)
        response.addParameter(field: "wired.info.uploads", value: self.uploads)
        response.addParameter(field: "wired.info.download_speed", value: self.downloadSpeed)
        response.addParameter(field: "wired.info.upload_speed", value: self.uploadSpeed)
        
        // TODO: add tracker here
        
        self.reply(client: client, reply: response, message: message)
    }
    
    
    private func receiveSetSettings(client:Client, message:P7Message) {
        var changed = false
        
        if !client.user!.hasPrivilege(name: "wired.account.settings.set_settings") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        if let serverName = message.string(forField: "wired.info.name") {
            if self.serverName != serverName {
                self.serverName = serverName
                changed = true
            }
        }
        
        if let serverDescription = message.string(forField: "wired.info.description") {
            if self.serverDescription != serverDescription {
                self.serverDescription = serverDescription
                changed = true
            }
        }
        
        if let bannerData = message.data(forField: "wired.info.banner") {
            try? bannerData.write(to: URL(fileURLWithPath: App.bannerPath))
            changed = true
        }
        
        if changed {
            App.clientsController.broadcast(message: self.serverInfoMessage())
        }
    }
    
    
    
    
    // MARK: -
    
    private func sendUserStatus(forClient client:Client) {
        let broadcast = P7Message(withName: "wired.chat.user_status", spec: self.spec)
        
        broadcast.addParameter(field: "wired.chat.id", value: App.chatsController.publicChat.chatID)
        broadcast.addParameter(field: "wired.user.id", value: client.userID)
        broadcast.addParameter(field: "wired.user.idle", value: false)
        broadcast.addParameter(field: "wired.user.nick", value: client.nick)
        broadcast.addParameter(field: "wired.user.status", value: client.status)
        broadcast.addParameter(field: "wired.user.icon", value: client.icon)
        broadcast.addParameter(field: "wired.account.color", value: UInt32(0))
        
        App.clientsController.broadcast(message: broadcast)
    }
    
    
    private func serverInfoMessage() -> P7Message {
        let message = P7Message(withName: "wired.server_info", spec: self.spec)
        
        message.addParameter(field: "wired.info.application.name", value: "Wired Server")
        message.addParameter(field: "wired.info.application.version", value: "3.0")
        message.addParameter(field: "wired.info.application.build", value: "alpha")
        
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
        message.addParameter(field: "wired.info.name", value: self.serverName)
        message.addParameter(field: "wired.info.description", value: self.serverDescription)
        
        if let data = try? Data(contentsOf: URL.init(fileURLWithPath: App.bannerPath)) {
            message.addParameter(field: "wired.info.banner", value: data)
        }
        
        message.addParameter(field: "wired.info.downloads", value: self.downloads)
        message.addParameter(field: "wired.info.uploads", value: self.uploads)
        message.addParameter(field: "wired.info.download_speed", value: self.downloadSpeed)
        message.addParameter(field: "wired.info.upload_speed", value: self.uploadSpeed)
        message.addParameter(field: "wired.info.start_time", value: self.startTime)
        message.addParameter(field: "wired.info.files.count", value: App.indexController.totalFilesCount)
        message.addParameter(field: "wired.info.files.size", value: App.indexController.totalFilesSize)
        
        return message
    }
    
    
    
    
    // MARK: -
    private func listenThread() {
        do {
            Logger.info("Server listening on port \(self.port)...")
            try self.socket.listen()
                    
            while self.isRunning {
                self.acceptThread()
            }
    
        } catch let error {
            if let socketError = error as? Socket.Error {
                Logger.error(socketError.description)
            } else {
                Logger.error(error.localizedDescription)
            }
        }
    }
    
    
    private func acceptThread() {
        do {
            let socket = try self.socket.accept()
            
            let p7Socket = P7Socket(socket: socket, spec: self.spec)
            
            p7Socket.ecdh = self.ecdh
            p7Socket.passwordProvider = App.usersController
            
            let userID = App.usersController.nextUserID()
            let client = Client(userID: userID, socket: p7Socket)
            
            if p7Socket.accept(compression: SERVER_COMPRESSION,
                               cipher:      SERVER_CIPHER,
                               checksum:    SERVER_CHECKSUM) {
                                
                Logger.info("Accept new connection from \(p7Socket.remoteAddress ?? "unknow")")

                App.clientsController.addClient(client: client)
                
                client.state = .CONNECTED
                
                DispatchQueue.global(qos: .default).async {
                    self.clientLoop(client)
                }
            }
            else {
                p7Socket.disconnect()
            }            
                
        } catch let error {
            if let socketError = error as? Socket.Error {
                Logger.error(socketError.description)
            } else {
                Logger.error(error.localizedDescription)
            }
        }
    }
    
    
    private func clientLoop(_ client:Client) {
        while self.isRunning {
            if client.socket.connected == false {
                client.state = .DISCONNECTED
                
                for delegate in delegates {
                    delegate.clientDisconnected(client: client)
                }
                break
            }
            
            if !client.socket.isInteractive() {
                break
            }
            
            Logger.debug("ClientLoop \(client.userID) before readMessage() interactive: \(client.socket.isInteractive())")
            
            if let message = client.socket.readMessage() {
                for delegate in delegates {
                    delegate.receiveMessage(client: client, message: message)
                }
            }
            else {
                for delegate in delegates {
                    delegate.clientDisconnected(client: client)
                }
                break
            }
        }
    }
}
