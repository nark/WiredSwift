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
let SERVER_CIPHER       = P7Socket.CipherType.SECURE_ONLY
let SERVER_CHECKSUM     = P7Socket.Checksum.SECURE_ONLY
    

public protocol ServerDelegate: class {
    func clientDisconnected(client:Client)
    func disconnectClient(client:Client)
    
    func receiveMessage(client:Client, message:P7Message)
}


public class Client {
    public enum State:UInt32 {
        case CONNECTED          = 0
        case GAVE_CLIENT_INFO
        case LOGGED_IN
        case DISCONNECTED
    }
    
    public var ip:String?
    public var host:String?
    public var nick:String?
    public var status:String?
    public var icon:Data?
    public var state:State = .DISCONNECTED
    
    public var userID:UInt32
    public var user:User?
    public var socket:P7Socket!
    
    public init(userID:UInt32, socket: P7Socket) {
        self.userID = userID
        self.socket = socket
    }
}


public class ServerController: ServerDelegate {
    public var port: Int = DEFAULT_PORT
    public var spec: P7Spec!
    public var isRunning:Bool = false
    public var delegates:[ServerDelegate] = []
    
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
                App.usersController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
                return
            }
        } else if client.state == .GAVE_CLIENT_INFO {
            if  message.name != "wired.user.set_nick"   &&
                message.name != "wired.user.set_status" &&
                message.name != "wired.user.set_icon"   &&
                message.name != "wired.send_login" &&
                message.name != "wired.send_ping" {
                Logger.error("Could not process message \(message.name!): Out of sequence")
                App.usersController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
                return
            }
        }
        
        self.handleMessage(client: client, message: message)
        
        // TODO: manage user idle time here
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
            App.chatsController.getChats(client: client)
        }
        else if message.name == "wired.chat.create_public_chat" {
            App.chatsController.createPublicChat(message: message, client: client)
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
        else {
            WiredSwift.Logger.warning("Message \(message.name ?? "unknow message") not implemented")
        }
    }
    
    
    
    private func receiveClientInfo(_ client:Client, _ message:P7Message) {
        client.state = .GAVE_CLIENT_INFO
        
        let response = P7Message(withName: "wired.server_info", spec: self.spec)
        
        response.addParameter(field: "wired.info.application.name", value: "Wired Server")
        response.addParameter(field: "wired.info.application.version", value: "3.0")
        response.addParameter(field: "wired.info.application.build", value: "alpha")
        
        #if os(iOS)
        response.addParameter(field: "wired.info.os.name", value: "iOS")
        #elseif os(macOS)
        response.addParameter(field: "wired.info.os.name", value: "macOS")
        #else
        response.addParameter(field: "wired.info.os.name", value: "Linux")
        #endif
        
        response.addParameter(field: "wired.info.os.version", value: ProcessInfo.processInfo.operatingSystemVersionString)
        
        #if os(iOS)
        response.addParameter(field: "wired.info.arch", value: "armv7")
        #elseif os(macOS)
        response.addParameter(field: "wired.info.arch", value: "x86_64")
        #else
        response.addParameter(field: "wired.info.arch", value: "x86_64")
        #endif
        
        
        response.addParameter(field: "wired.info.supports_rsrc", value: false)
        response.addParameter(field: "wired.info.name", value: "Wired Server 3.0")
        response.addParameter(field: "wired.info.description", value: "Welcome to my Wired Server")
        
        if let data = try? Data(contentsOf: URL.init(fileURLWithPath: App.bannerPath)) {
            response.addParameter(field: "wired.info.banner", value: data)
        }
        
        response.addParameter(field: "wired.info.downloads", value: UInt32(0))
        response.addParameter(field: "wired.info.uploads", value: UInt32(0))
        response.addParameter(field: "wired.info.download_speed", value: UInt32(0))
        response.addParameter(field: "wired.info.upload_speed", value: UInt32(0))
        response.addParameter(field: "wired.info.start_time", value: self.startTime)
        response.addParameter(field: "wired.info.files.count", value: App.indexController.totalFilesCount)
        response.addParameter(field: "wired.info.files.size", value: App.indexController.totalFilesSize)
                
        App.usersController.reply(client: client, reply: response, message: message)
        
        
    }
    
    
    private func receiveUserSetNick(_ client:Client, _ message:P7Message) {
        if let nick = message.string(forField: "wired.user.nick") {
            client.nick = nick
        }
                
        let response = P7Message(withName: "wired.okay", spec: self.spec)
        
        App.usersController.reply(client: client, reply: response, message: message)
        
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
        _ = client.socket?.write(response)
        
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
        _ = client.socket?.write(response)
        
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
            App.usersController.reply(client: client, reply: reply, message: message)
            
            Logger.error("Login failed for user '\(login)'")
            
            return false
        }
        
        client.user     = user
        client.state    = .LOGGED_IN
        
        let response = P7Message(withName: "wired.login", spec: self.spec)
        
        response.addParameter(field: "wired.user.id", value: client.userID)
        
        App.usersController.reply(client: client, reply: response, message: message)
        
        let response2 = P7Message(withName: "wired.account.privileges", spec: self.spec)
        
        for field in spec.accountPrivileges! {
            if user.hasPrivilege(name: field) {
                response2.addParameter(field: field, value: UInt32(1))
            }
        }
        
        App.usersController.reply(client: client, reply: response2, message: message)
        
        return true
    }
    
    
    
    private func receiveDownloadFile(_ client:Client, _ message:P7Message) {
        if client.user!.hasPrivilege(name: "wired.account.transfer.download_files") {
            App.usersController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        guard let path = message.string(forField: "wired.file.path") else {
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.usersController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }
        
        // file privileges
        if let privilege = FilePrivilege(path: App.filesController.real(path: path)) {
            if client.user!.hasPermission(toRead: privilege) {
                App.usersController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }
        
        let dataOffset = message.uint64(forField: "wired.transfer.data_offset")
        let rsrcOffset = message.uint64(forField: "wired.transfer.rsrc_offset")
                
        if let transfer = App.transfersController.download(path: path,
                                                           dataOffset: dataOffset!,
                                                           rsrcOffset: rsrcOffset!,
                                                           client: client, message: message) {
            client.user!.transfer = transfer
            
            if(App.transfersController.run(transfer: transfer, client: client, message: message)) {
                client.state = .DISCONNECTED
            }
        }
    }
    
    
    
    
    private func receiveUploadFile(_ client:Client, _ message:P7Message) {
        if client.user!.hasPrivilege(name: "wired.account.transfer.upload_files") {
            App.usersController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        guard let path = message.string(forField: "wired.file.path") else {
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.usersController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }
        
        let realPath = App.filesController.real(path: path)
        let parentPath = realPath.stringByDeletingLastPathComponent
        
        // file privileges
        if let privilege = FilePrivilege(path: realPath) {
            if client.user!.hasPermission(toWrite: privilege) {
                App.usersController.replyError(client: client, error: "wired.error.permission_denied", message: message)
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
            client.user!.transfer = transfer
            
            if(!App.transfersController.run(transfer: transfer, client: client, message: message)) {
                client.state = .DISCONNECTED
            }
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
                                
                Logger.debug("Accept new connection from \(p7Socket.clientAddress() ?? "unknow")")

                App.clientsController.addClient(client: client)
                
                client.state = .CONNECTED
                
                DispatchQueue.global(qos: .default).async {
                    self.clientLoop(client)
                }
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
            
            if client.socket.isInteractive() {
                if let message = client.socket.readMessage() {
                    for delegate in delegates {
                        delegate.receiveMessage(client: client, message: message)
                    }
                } else {
                    for delegate in delegates {
                        delegate.clientDisconnected(client: client)
                    }
                    break
                }
            }
        }
    }
}
