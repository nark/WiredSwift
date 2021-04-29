//
//  ServerController.swift
//  wired3
//
//  Created by Rafael Warnault on 16/03/2021.
//

import Foundation
import WiredSwift
import NIO



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
    
    struct Configuration {
        var host           : String?         = nil // will use localhost IP 0.0.0.0
        var port           : Int             = DEFAULT_PORT // Daytime is TCP/UDP 13, which is protected
        var backlog        : Int             = 256
        var eventLoopGroup : EventLoopGroup? = nil
    }
    
    let configuration  : Configuration
    let eventLoopGroup : EventLoopGroup
    var serverChannel  : Channel?
    
    var startTime:Date? = nil
    
    
    
    public init(port: Int, spec: P7Spec) {
        self.port = port
        self.spec = spec
        
        if let string = App.config["server", "name"] as? String {
            self.serverName = string
        }
        
        if let string = App.config["server", "description"] as? String {
            self.serverDescription = string
        }
        
        if let number = App.config["transfers", "downloads"] as? UInt32 {
            self.downloads = number
        }
        
        if let number = App.config["transfers", "uploads"] as? UInt32 {
            self.uploads = number
        }
        
        if let number = App.config["transfers", "downloadSpeed"] as? UInt32 {
            self.uploadSpeed = number
        }
        
        if let number = App.config["transfers", "uploadSpeed"] as? UInt32 {
            self.uploadSpeed = number
        }
        
        self.configuration  = Configuration(host: nil, port: port, backlog: 256, eventLoopGroup: MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount))
        self.eventLoopGroup = configuration.eventLoopGroup
               ?? MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            
        self.addDelegate(self)
    }
    
    
    public func listen() {
        self.startTime = Date()

        self.listenChannels()
        
        do    { try serverChannel?.closeFuture.wait() }
        catch { print("[!] ERROR: Failed to wait on server:", error) }
        
//        do {
//            self.socket = try Socket(.inet, type: .stream, protocol: .tcp)
//            try self.socket.set(option: .reuseAddress, true) // set SO_REUSEADDR to 1
//            try self.socket.bind(port: Port(self.port), address: nil) // bind 'localhost:8090' address to the socket
//
//            DispatchQueue.global(qos: .default).async {
//                self.isRunning = true
//
//                self.listenThread()
//            }
//        } catch let error {
//            if let socketError = error as? Socket.Error {
//                Logger.error(socketError.description)
//            } else {
//                Logger.error(error.localizedDescription)
//            }
//
//        }
        
    }
    
    
    
    
    // MARK : -
    
    func listenChannels() {
        let bootstrap = makeBootstrap()
        do {
            let address : SocketAddress
        
            if let host = configuration.host {
                address = try SocketAddress.init(ipAddress: host, port: configuration.port)
            }
            else {
                var addr = sockaddr_in()
                addr.sin_port = in_port_t(configuration.port).bigEndian
                address = SocketAddress(addr, host: "*")
            }
        
            serverChannel = try bootstrap.bind(to: address).wait()
        
            if let addr = serverChannel?.localAddress {
                print("[+] Server running on:", addr)
            }
            else {
                print("[!] ERROR: server reported no local address?")
            }
        }
        catch let error as NIO.IOError {
            print("[!] ERROR: failed to start server, errno:",
                  error.errnoCode, "\n",
                  error.localizedDescription)
        }
        catch {
            print("[!] ERROR: failed to start server:", type(of:error), error)
        }
    }
    
    
    func makeBootstrap() -> ServerBootstrap {
        let reuseAddrOpt = ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),
                                                 SO_REUSEADDR)
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog,
                                 value: Int32(configuration.backlog))
            .serverChannelOption(reuseAddrOpt, value: 1)
        
            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(ClientHandler(self.spec))
            }
        
            // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY),
                                value: 1)
            .childChannelOption(reuseAddrOpt, value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
    
        return bootstrap
    }
    
    
    
    // MARK: -
    
    
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
        
        if let bannerPath = App.config["server", "banner"] as? String {
            if let data = try? Data(contentsOf: URL.init(fileURLWithPath: bannerPath)) {
                response.addParameter(field: "wired.info.banner", value: data)
            }
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
                App.config["server", "name"] = serverName
                changed = true
            }
        }
        
        if let serverDescription = message.string(forField: "wired.info.description") {
            if self.serverDescription != serverDescription {
                self.serverDescription = serverDescription
                App.config["server", "description"] = serverDescription
                changed = true
            }
        }
        
        if let bannerPath = App.config["server", "banner"] as? String {
            if let bannerData = message.data(forField: "wired.info.banner") {
                try? bannerData.write(to: URL(fileURLWithPath: bannerPath))
                changed = true
            }
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
        
        if let bannerPath = App.config["server", "banner"] as? String {
            if let data = try? Data(contentsOf: URL.init(fileURLWithPath: bannerPath)) {
                message.addParameter(field: "wired.info.banner", value: data)
            }
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
//    private func listenThread() {
//        do {
//            Logger.info("Server listening on port \(self.port)...")
//            try self.socket.listen()
//
//            while self.isRunning {
//                self.acceptThread()
//            }
//
//        } catch let error {
//            if let socketError = error as? Socket.Error {
//                Logger.error(socketError.description)
//            } else {
//                Logger.error(error.localizedDescription)
//            }
//        }
//    }
//
//
//    private func acceptThread() {
//        do {
//            let socket = try self.socket.accept()
//
//            DispatchQueue.global(qos: .default).async {
//                let p7Socket = P7Socket(socket: socket, spec: self.spec)
//
//                p7Socket.ecdh = self.ecdh
//                p7Socket.passwordProvider = App.usersController
//
//                let userID = App.usersController.nextUserID()
//                let client = Client(userID: userID, socket: p7Socket)
//
//                if p7Socket.accept(compression: SERVER_COMPRESSION,
//                                   cipher:      SERVER_CIPHER,
//                                   checksum:    SERVER_CHECKSUM) {
//
//                    Logger.info("Accept new connection from \(p7Socket.remoteAddress ?? "unknow")")
//
//                    App.clientsController.addClient(client: client)
//
//                    client.state = .CONNECTED
//
//                    self.clientLoop(client)
//                }
//                else {
//                    p7Socket.disconnect()
//                }
//            }
//
//        } catch let error {
//            if let socketError = error as? Socket.Error {
//                Logger.error(socketError.description)
//            } else {
//                Logger.error("Socket accept error: \(error.localizedDescription)")
//            }
//        }
//    }
//
//
//    private func clientLoop(_ client:Client) {
//        while self.isRunning {
//            if client.socket.connected == false {
//                client.state = .DISCONNECTED
//
//                for delegate in delegates {
//                    delegate.clientDisconnected(client: client)
//                }
//                break
//            }
//
//            if !client.socket.isInteractive() {
//                break
//            }
//
//            Logger.debug("ClientLoop \(client.userID) before readMessage() interactive: \(client.socket.isInteractive())")
//
//            if let message = client.socket.readMessage() {
//                for delegate in delegates {
//                    delegate.receiveMessage(client: client, message: message)
//                }
//            }
//            else {
//                for delegate in delegates {
//                    delegate.clientDisconnected(client: client)
//                }
//                break
//            }
//        }
//    }
}



final class ClientHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    // All access to channels is guarded by channelsSyncQueue.
    private let channelsSyncQueue = DispatchQueue(label: "channelsQueue")
    private var channels: [ObjectIdentifier: Channel] = [:]
    private var spec: P7Spec!
    private let ecdh = ECDH()
    
    private var socket:P7Socket!
    
    init(_ spec:P7Spec) {
        self.spec = spec
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        let remoteAddress = context.remoteAddress!
        let channel = context.channel

        print("remoteAddress \(remoteAddress)")
        
//        socket = P7Socket(channel: channel, context: context, spec: self.spec)
//
//        socket.ecdh = self.ecdh
//        socket.passwordProvider = App.usersController
//
//        let userID = App.usersController.nextUserID()
//        let client = Client(userID: userID, socket: socket)
//
//        if socket.accept(compression: SERVER_COMPRESSION,
//                           cipher:      SERVER_CIPHER,
//                           checksum:    SERVER_CHECKSUM) {
//
//            Logger.info("Accept new connection from \(socket.remoteAddress ?? "unknow")")
//
//            App.clientsController.addClient(client: client)
//
//            client.state = .CONNECTED
//
//            //self.clientLoop(client)
//        }
//        else {
//            socket.disconnect()
//        }
        
//        self.channelsSyncQueue.async {
//            // broadcast the message to all the connected clients except the one that just became active.
//            self.writeToAll(channels: self.channels, allocator: channel.allocator, message: "(ChatServer) - New client connected with address: \(remoteAddress)\n")
//
//            self.channels[ObjectIdentifier(channel)] = channel
//        }
//
//        var buffer = channel.allocator.buffer(capacity: 64)
//        buffer.writeString("(ChatServer) - Welcome to: \(context.localAddress!)\n")
//        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
    }
    
    public func channelInactive(context: ChannelHandlerContext) {
        let channel = context.channel
        self.channelsSyncQueue.async {
            if self.channels.removeValue(forKey: ObjectIdentifier(channel)) != nil {
                // Broadcast the message to all the connected clients except the one that just was disconnected.
                self.writeToAll(channels: self.channels, allocator: channel.allocator, message: "(ChatServer) - Client disconnected\n")
            }
        }
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let id = ObjectIdentifier(context.channel)
        var read = self.unwrapInboundIn(data)
        
        self.channelsSyncQueue.sync {
            var data = Data(buffer: read)
            data = data.dropFirst(4)
            
            
            print(data.toHex())
            
            
            let message = P7Message(withData: data, spec: self.spec)
            
            print("message : \(message)")
        }

        // 64 should be good enough for the ipaddress
//        var buffer = context.channel.allocator.buffer(capacity: read.readableBytes + 64)
//        buffer.writeString("(\(context.remoteAddress!)) - ")
//        buffer.writeBuffer(&read)
//        self.channelsSyncQueue.async {
//            // broadcast the message to all the connected clients except the one that wrote it.
//            self.writeToAll(channels: self.channels.filter { id != $0.key }, buffer: buffer)
//        }
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)

        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        context.close(promise: nil)
    }

    private func writeToAll(channels: [ObjectIdentifier: Channel], allocator: ByteBufferAllocator, message: String) {
        let buffer =  allocator.buffer(string: message)
        self.writeToAll(channels: channels, buffer: buffer)
    }

    private func writeToAll(channels: [ObjectIdentifier: Channel], buffer: ByteBuffer) {
        channels.forEach { $0.value.writeAndFlush(buffer, promise: nil) }
    }
}

