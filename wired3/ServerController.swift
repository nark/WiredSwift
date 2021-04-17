//
//  Server.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 16/03/2021.
//

import Foundation
import WiredSwift
import SocketSwift


public protocol ServerDelegate: class {
    func userConnected(withSocket socket:P7Socket) -> User?
    func userDisconnected(user:User)
    func disconnectUser(user:User)
    
    func receiveMessage(user:User, message:P7Message)
}


public class ServerController: ServerDelegate {
    public var port: Int = DEFAULT_PORT
    public var spec: P7Spec!
    public var isRunning:Bool = false
    public var delegates:[ServerDelegate] = []
    
    private var socket:Socket!
    private let rsa = RSA(bits: RSA_KEY_BITS)
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
    public func userConnected(withSocket socket:P7Socket) -> User? {
        guard let user = App.usersController.user(withUsername: socket.username) else {
            WiredSwift.Logger.warning("Username not found \(socket.username)")
            
            return nil
        }
        
        user.socket = socket
        user.userID = App.usersController.nextUserID()
        
        print("NEW USER \(user.userID)")
                
        App.usersController.addUser(user: user)
        
        return user
    }
    
    
    public func userDisconnected(user:User) {
        self.disconnectUser(user: user)
    }
    
    
    public func disconnectUser(user: User) {
        App.chatsController.userLeave(user: user)
        App.usersController.removeUser(user: user)
    }
    
    
    
    public func receiveMessage(user:User, message:P7Message) {
        if user.state == .CONNECTED {
            if message.name != "wired.client_info" {
                Logger.error("Could not process message \(message.name!): Out of sequence")
                App.usersController.replyError(user: user, error: "wired.error.message_out_of_sequence", message: message)
                return
            }
        } else if user.state == .GAVE_CLIENT_INFO {
            if  message.name != "wired.user.set_nick"   &&
                message.name != "wired.user.set_status" &&
                message.name != "wired.user.set_icon"   &&
                message.name != "wired.send_login" &&
                message.name != "wired.send_ping" {
                Logger.error("Could not process message \(message.name!): Out of sequence")
                App.usersController.replyError(user: user, error: "wired.error.message_out_of_sequence", message: message)
                return
            }
        }
        
        self.handleMessage(user: user, message: message)
        
        // TODO: manage user idle time here
    }
    
    

    
    // MARK: - Private
    private func handleMessage(user:User, message:P7Message) {
        if message.name == "wired.client_info" {
            self.receiveClientInfo(user, message)
        }
        else if message.name == "wired.user.set_nick" {
            self.receiveUserSetNick(user, message)
        }
        else if message.name == "wired.user.set_status" {
            self.receiveUserSetStatus(user, message)
        }
        else if message.name == "wired.user.set_icon" {
            self.receiveUserSetIcon(user, message)
        }
        else if message.name == "wired.send_login" {
            if !self.receiveSendLogin(user, message) {
                // login failed
                self.disconnectUser(user: user)
            }
        }
        else if message.name == "wired.chat.get_chats" {
            App.chatsController.getChats(user: user)
        }
        else if message.name == "wired.chat.create_public_chat" {
            App.chatsController.createPublicChat(message: message, user: user)
        }
        else if message.name == "wired.chat.create_chat" {
            App.chatsController.createPrivateChat(message: message, user: user)
        }
        else if message.name == "wired.chat.invite_user" {
            App.chatsController.inviteUser(message: message, user: user)
        }
        else if message.name == "wired.chat.send_say" {
            App.chatsController.receiveChatSay(user, message)
        }
        else if message.name == "wired.chat.send_me" {
            App.chatsController.receiveChatMe(user, message)
        }
        else if message.name == "wired.chat.join_chat" {
            App.chatsController.userJoin(message: message, user: user)
        }
        else if message.name == "wired.chat.leave_chat" {
            App.chatsController.userLeave(message: message, user: user)
        }
        else if message.name == "wired.chat.set_topic" {
            App.chatsController.setTopic(message: message, user: user)
        }
        else if message.name == "wired.chat.kick_user" {
            //App.chatsController.kickUser(user: user, message: message)
        }
        else if message.name == "wired.file.list_directory" {
            App.filesController.listDirectory(user: user, message: message)
        }
        else if message.name == "wired.transfer.download_file" {
            self.receiveDownloadFile(user, message)
        }
        else if message.name == "wired.transfer.upload_file" {
            self.receiveUploadFile(user, message)
        }
        else {
            WiredSwift.Logger.warning("Message \(message.name ?? "unknow message") not implemented")
        }
    }
    
    
    
    private func receiveClientInfo(_ user:User, _ message:P7Message) {
        user.state = .GAVE_CLIENT_INFO
        
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
                
        App.usersController.reply(user: user, reply: response, message: message)
        
        
    }
    
    
    private func receiveUserSetNick(_ user:User, _ message:P7Message) {
        if let nick = message.string(forField: "wired.user.nick") {
            user.nick = nick
        }
                
        let response = P7Message(withName: "wired.okay", spec: self.spec)
        
        App.usersController.reply(user: user, reply: response, message: message)
        
        // broadcast if already logged in
        if user.state == .LOGGED_IN {
            self.sendUserStatus(forUser: user)
        }
    }
    
    
    private func receiveUserSetStatus(_ user:User, _ message:P7Message) {
        if let status = message.string(forField: "wired.user.status") {
            user.status = status
        }
        
        let response = P7Message(withName: "wired.okay", spec: self.spec)
        _ = user.socket?.write(response)
        
        // broadcast if already logged in
        if user.state == .LOGGED_IN {
            self.sendUserStatus(forUser: user)
        }
    }
    
    
    private func receiveUserSetIcon(_ user:User, _ message:P7Message) {
        if let icon = message.data(forField: "wired.user.icon") {
            user.icon = icon
        }
        
        let response = P7Message(withName: "wired.okay", spec: self.spec)
        _ = user.socket?.write(response)
        
        // broadcast if already logged in
        if user.state == .LOGGED_IN {
            self.sendUserStatus(forUser: user)
        }
    }
    
    
    private func receiveSendLogin(_ user:User, _ message:P7Message) -> Bool {
        guard let password = message.string(forField: "wired.user.password") else {
            return false
        }
        
        if password != App.usersController.passwordForUsername(username: user.username!) {
            let reply = P7Message(withName: "wired.error", spec: user.socket!.spec)
            reply.addParameter(field: "wired.error.string", value: "Login failed")
            reply.addParameter(field: "wired.error", value: 4)
            App.usersController.reply(user: user, reply: reply, message: message)
            
            Logger.error("Login failed for user \(user.username!)")
            
            return false
        }
        
        user.state = .LOGGED_IN
        
        let response = P7Message(withName: "wired.login", spec: self.spec)
        
        response.addParameter(field: "wired.user.id", value: user.userID)
        
        App.usersController.reply(user: user, reply: response, message: message)
        
        let response2 = P7Message(withName: "wired.account.privileges", spec: self.spec)
        
        for field in spec.accountPrivileges! {
            if user.hasPrivilege(name: field) {
                response2.addParameter(field: field, value: UInt32(1))
            }
        }
        
        App.usersController.reply(user: user, reply: response2, message: message)
        
        return true
    }
    
    
    
    private func receiveDownloadFile(_ user:User, _ message:P7Message) {
        if !user.hasPrivilege(name: "wired.account.transfer.download_files") {
            App.usersController.replyError(user: user, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        guard let path = message.string(forField: "wired.file.path") else {
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.usersController.replyError(user: user, error: "wired.error.file_not_found", message: message)
            return
        }
        
        // file privileges
        if let privilege = FilePrivilege(path: App.filesController.real(path: path)) {
            if !user.hasPermission(toRead: privilege) {
                App.usersController.replyError(user: user, error: "wired.error.permission_denied", message: message)
                return
            }
        }
        
        let dataOffset = message.uint64(forField: "wired.transfer.data_offset")
        let rsrcOffset = message.uint64(forField: "wired.transfer.rsrc_offset")
                
        if let transfer = App.transfersController.download(path: path,
                                                        dataOffset: dataOffset!,
                                                        rsrcOffset: rsrcOffset!,
                                                        user: user, message: message) {
            user.transfer = transfer
            
            if(App.transfersController.run(transfer: transfer, user: user, message: message)) {
                user.state = .DISCONNECTED
            }
        }
    }
    
    
    
    
    private func receiveUploadFile(_ user:User, _ message:P7Message) {
        if !user.hasPrivilege(name: "wired.account.transfer.upload_files") {
            App.usersController.replyError(user: user, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        guard let path = message.string(forField: "wired.file.path") else {
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.usersController.replyError(user: user, error: "wired.error.file_not_found", message: message)
            return
        }
        
        let realPath = App.filesController.real(path: path)
        let parentPath = realPath.stringByDeletingLastPathComponent
        
        // file privileges
        if let privilege = FilePrivilege(path: realPath) {
            if !user.hasPermission(toWrite: privilege) {
                App.usersController.replyError(user: user, error: "wired.error.permission_denied", message: message)
                return
            }
        }
        
        // user privileges
        if let type = File.FileType.type(path: parentPath) {
            switch type {
                case .directory:    if !user.hasPrivilege(name: "wired.account.transfer.upload_files")      { return }; break
                case .uploads:      if !user.hasPrivilege(name: "wired.account.transfer.upload_anywhere")   { return }; break
                default:            if !user.hasPrivilege(name: "wired.account.transfer.upload_anywhere")   { return }; break
            }
        }
        
        let dataSize = message.uint64(forField: "wired.transfer.data_size") ?? UInt64(0)
        let rsrcSize = message.uint64(forField: "wired.transfer.rsrc_size") ?? UInt64(0)
        
        if let transfer = App.transfersController.upload(path: path,
                                                        dataSize: dataSize,
                                                        rsrcSize: rsrcSize,
                                                        executable: false,
                                                        user: user, message: message) {
            user.transfer = transfer
            
            if(!App.transfersController.run(transfer: transfer, user: user, message: message)) {
                user.state = .DISCONNECTED
            }
        }
    }
    
    
    // MARK: -
    
    private func sendUserStatus(forUser user:User) {
        let broadcast = P7Message(withName: "wired.chat.user_status", spec: self.spec)
        
        broadcast.addParameter(field: "wired.chat.id", value: App.chatsController.publicChat.chatID)
        broadcast.addParameter(field: "wired.user.id", value: user.userID)
        broadcast.addParameter(field: "wired.user.idle", value: false)
        broadcast.addParameter(field: "wired.user.nick", value: user.nick)
        broadcast.addParameter(field: "wired.user.status", value: user.status)
        broadcast.addParameter(field: "wired.user.icon", value: user.icon)
        broadcast.addParameter(field: "wired.account.color", value: UInt32(0))
        
        App.usersController.broadcast(message: broadcast)
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
            
            p7Socket.rsa = self.rsa
            p7Socket.passwordProvider = App.usersController
            
            if p7Socket.accept(compression: P7Socket.Compression.DEFLATE,
                               cipher:      P7Socket.CipherType.RSA_AES_256_SHA256,
                               checksum:    P7Socket.Checksum.SHA256) {
                
                Logger.debug("Accept new connection from \(p7Socket.clientAddress() ?? "unknow") with ciper : \(P7Socket.CipherType.RSA_AES_256_SHA256)")
                                
                for delegate in delegates {
                    if let user = delegate.userConnected(withSocket: p7Socket) {
                        DispatchQueue.global(qos: .default).async {
                            self.userLoop(user)
                        }
                    }
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
    
    
    private func userLoop(_ user:User) {
        while self.isRunning {
            if let socket = user.socket {
                if socket.connected == false {
                    user.state = .DISCONNECTED
                    
                    for delegate in delegates {
                        delegate.userDisconnected(user: user)
                    }
                    break
                }
                
                if socket.isInteractive() {
                    if let message = socket.readMessage() {
                        for delegate in delegates {
                            delegate.receiveMessage(user: user, message: message)
                        }
                    } else {
                        for delegate in delegates {
                            delegate.userDisconnected(user: user)
                        }
                        break
                    }
                }
            }
        }
    }
}