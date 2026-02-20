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
        App.filesController.unsubscribeAll(client: client)
        client.isSubscribedToAccounts = false
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
    public func read(message:P7Message, client: Client) throws -> P7Message {
        return try client.socket.readMessage()
    }
    
    @discardableResult
    public func send(message:P7Message, client: Client) -> Bool {
        if client.transfer == nil {
            return client.socket.write(message) ?? false
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
        let reply = P7Message(withName: "wired.error", spec: client.socket.spec)

        if let message = message {
            if let errorEnumValue = message.spec.errorsByName[error] {
                reply.addParameter(field: "wired.error", value: UInt32(errorEnumValue.id))
                reply.addParameter(field: "wired.error.string", value: errorEnumValue.name)
            }
            
            self.reply(client: client, reply: reply, message: message)
        } else {
            _ = self.send(message: reply, client: client)
        }
    }
    
    public func replyOK(client: Client, message:P7Message) {
        let reply = P7Message(withName: "wired.okay", spec: client.socket.spec)
        
        self.reply(client: client, reply: reply, message: message)
    }
    

    
    // MARK: - Private
    private func handleMessage(client:Client, message:P7Message) {
        // make sure to broadcast idle status if needed
        if client.idle && message.name != "wired.user.set_nick" && message.name != "wired.user.set_status" && message.name != "wired.user.set_icon" && message.name != "wired.user.set_idle" {
            client.idle = false
            
            self.sendUserStatus(forClient: client)
        }
        
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
        else if message.name == "wired.user.set_idle" {
            self.receiveUserSetIdle(client, message)
        }
        else if message.name == "wired.send_login" {
            if !self.receiveSendLogin(client, message) {
                // login failed
                self.disconnectClient(client: client)
            }
        }
        else if message.name == "wired.user.get_info" {
            self.receiveUserGetInfo(client, message)
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
        else if message.name == "wired.chat.decline_invitation" {
            App.chatsController.declineInvitation(message: message, client: client)
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
        else if message.name == "wired.message.send_message" {
            self.receiveMessageSendMessage(client: client, message: message)
        }
        else if message.name == "wired.message.send_broadcast" {
            self.receiveMessageSendBroadcast(client: client, message: message)
        }
        else if message.name == "wired.file.list_directory" {
            App.filesController.listDirectory(client: client, message: message)
        }
        else if message.name == "wired.file.get_info" {
            App.filesController.getInfo(client: client, message: message)
        }
        else if message.name == "wired.file.create_directory" {
            App.filesController.createDirectory(client: client, message: message)
        }
        else if message.name == "wired.file.delete" {
            App.filesController.delete(client: client, message: message)
        }
        else if message.name == "wired.file.move" {
            App.filesController.move(client: client, message: message)
        }
        else if message.name == "wired.file.set_type" {
            App.filesController.setType(client: client, message: message)
        }
        else if message.name == "wired.file.set_permissions" {
            App.filesController.setPermissions(client: client, message: message)
        }
        else if message.name == "wired.file.subscribe_directory" {
            App.filesController.subscribeDirectory(client: client, message: message)
        }
        else if message.name == "wired.file.unsubscribe_directory" {
            App.filesController.unsubscribeDirectory(client: client, message: message)
        }
        else if message.name == "wired.transfer.download_file" {
            self.receiveDownloadFile(client, message)
        }
        else if message.name == "wired.transfer.upload_file" {
            self.receiveUploadFile(client, message)
        }
        else if message.name == "wired.transfer.upload_directory" {
            self.receiveUploadDirectory(client, message)
        }
        else if message.name == "wired.settings.get_settings" {
            self.receiveGetSettings(client: client, message: message)
        }
        else if message.name == "wired.settings.set_settings" {
            self.receiveSetSettings(client: client, message: message)
        }
        else if message.name == "wired.account.list_users" {
            self.receiveAccountListUsers(client: client, message: message)
        }
        else if message.name == "wired.account.list_groups" {
            self.receiveAccountListGroups(client: client, message: message)
        }
        else if message.name == "wired.account.read_user" {
            self.receiveAccountReadUser(client: client, message: message)
        }
        else if message.name == "wired.account.read_group" {
            self.receiveAccountReadGroup(client: client, message: message)
        }
        else if message.name == "wired.account.edit_user" {
            self.receiveAccountEditUser(client: client, message: message)
        }
        else if message.name == "wired.account.edit_group" {
            self.receiveAccountEditGroup(client: client, message: message)
        }
        else if message.name == "wired.account.subscribe_accounts" {
            self.receiveAccountSubscribeAccounts(client: client, message: message)
        }
        else if message.name == "wired.account.unsubscribe_accounts" {
            self.receiveAccountUnsubscribeAccounts(client: client, message: message)
        }
        else {
            WiredSwift.Logger.warning("Message \(message.name ?? "unknow message") not implemented")
        }
    }
    
    
    
    private func receiveClientInfo(_ client:Client, _ message:P7Message) {
        client.state = .GAVE_CLIENT_INFO
                
        if let applicationName = message.string(forField: "wired.info.application.name") {
            client.applicationName = applicationName
        }
        
        if let applicationVersion = message.string(forField: "wired.info.application.version") {
            client.applicationVersion = applicationVersion
        }
        
        if let applicationBuild = message.string(forField: "wired.info.application.build") {
            client.applicationBuild = applicationBuild
        }
        
        if let osName = message.string(forField: "wired.info.os.name") {
            client.osName = osName
        }
        
        if let osVersion = message.string(forField: "wired.info.os.version") {
            client.osVersion = osVersion
        }
        
        if let arch = message.string(forField: "wired.info.arch") {
            client.arch = arch
        }
        
        if let supportsRsrc = message.bool(forField: "wired.info.supports_rsrc") {
            client.supportsRsrc = supportsRsrc
        }
                
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
    
    private func receiveUserSetIdle(_ client:Client, _ message:P7Message) {
        client.idle = true
        client.idleTime = Date()
        
        let response = P7Message(withName: "wired.okay", spec: self.spec)
        _ = self.send(message: response, client: client)
        
        // broadcast if already logged in
        if client.state == .LOGGED_IN {
            self.sendUserStatus(forClient: client)
        }
    }
    
    
    private func receiveUserGetInfo(_ fromClient:Client, _ message:P7Message) {
        if !fromClient.user!.hasPrivilege(name: "wired.account.user.get_info") {
            App.serverController.replyError(client: fromClient, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        guard let userID = message.uint32(forField: "wired.user.id") else { return }
        guard let client = App.clientsController.user(withID: userID) else { return }
        
        let response = P7Message(withName: "wired.user.info", spec: self.spec)
        
        response.addParameter(field: "wired.user.id", value: client.userID ?? "")
        response.addParameter(field: "wired.user.nick", value: client.nick ?? "")
        response.addParameter(field: "wired.user.status", value: client.status ?? "")
        response.addParameter(field: "wired.user.idle", value: client.idle)
        response.addParameter(field: "wired.user.icon", value: client.icon ?? "")
        
        response.addParameter(field: "wired.user.login", value: client.user?.username ?? "")
        response.addParameter(field: "wired.user.ip", value: client.socket.getClientIP() ?? "")
        response.addParameter(field: "wired.user.host", value: client.socket.getClientHostname() ?? "")
        response.addParameter(field: "wired.user.cipher.name", value: client.socket.cipherType.description)
        response.addParameter(field: "wired.user.cipher.bits", value: UInt32(client.socket.checksumLength(client.socket.digest.type)))
        
        if let loginTime = client.loginTime {
            response.addParameter(field: "wired.user.login_time", value: loginTime)
        }
        
        if let idleTime = client.idleTime {
            response.addParameter(field: "wired.user.idle_time", value: idleTime)
        }
        
        response.addParameter(field: "wired.info.application.name", value: client.applicationName)
        response.addParameter(field: "wired.info.application.version", value: client.applicationBuild)
        response.addParameter(field: "wired.info.application.build", value: client.applicationVersion)
        response.addParameter(field: "wired.info.os.name", value: client.osName)
        response.addParameter(field: "wired.info.os.version", value: client.osVersion)
        response.addParameter(field: "wired.info.arch", value: client.arch)
        response.addParameter(field: "wired.info.supports_rsrc", value: client.supportsRsrc)
        
        App.serverController.reply(client: fromClient,
                                   reply: response,
                                   message: message)
    }

    private func receiveMessageSendMessage(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        if !user.hasPrivilege(name: "wired.account.message.send_messages") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let recipientID = message.uint32(forField: "wired.user.id"),
              let recipient = App.clientsController.user(withID: recipientID) else {
            App.serverController.replyError(client: client, error: "wired.error.user_not_found", message: message)
            return
        }

        guard let body = message.string(forField: "wired.message.message"),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let reply = P7Message(withName: "wired.message.message", spec: self.spec)
        reply.addParameter(field: "wired.user.id", value: client.userID)
        reply.addParameter(field: "wired.message.message", value: body)

        _ = self.send(message: reply, client: recipient)
        App.serverController.replyOK(client: client, message: message)
    }

    private func receiveMessageSendBroadcast(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        if !user.hasPrivilege(name: "wired.account.message.broadcast") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let body = message.string(forField: "wired.message.broadcast"),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let broadcast = P7Message(withName: "wired.message.broadcast", spec: self.spec)
        broadcast.addParameter(field: "wired.user.id", value: client.userID)
        broadcast.addParameter(field: "wired.message.broadcast", value: body)

        App.clientsController.broadcast(message: broadcast)
        App.serverController.replyOK(client: client, message: message)
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
        
        client.loginTime = Date()
                
        App.serverController.reply(client: client, reply: accountPrivilegesMessage(for: user), message: message)
        
        return true
    }
    
    
    
    private func receiveDownloadFile(_ client:Client, _ message:P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        if !user.hasPrivilege(name: "wired.account.transfer.download_files") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        guard let path = message.string(forField: "wired.file.path") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }
        
        // file privileges
        if let privilege = FilePrivilege(path: App.filesController.real(path: path)) {
            if !user.hasPermission(toRead: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }
        
        guard let dataOffset = message.uint64(forField: "wired.transfer.data_offset"),
              let rsrcOffset = message.uint64(forField: "wired.transfer.rsrc_offset") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
                
        if let transfer = App.transfersController.download(path: path,
                                                           dataOffset: dataOffset,
                                                           rsrcOffset: rsrcOffset,
                                                           client: client, message: message) {
            client.transfer = transfer
            
            if(App.transfersController.run(transfer: transfer, client: client, message: message)) {
                client.state = .DISCONNECTED
            }
            
            client.transfer = nil
        } else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }
    
    
    
    
    private func receiveUploadFile(_ client:Client, _ message:P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard let path = message.string(forField: "wired.file.path") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }
        
        let normalizedPath = NSString(string: path).standardizingPath
        let realPath = App.filesController.real(path: normalizedPath)
        let parentPath = realPath.stringByDeletingLastPathComponent

        // file privileges
        if let privilege = App.filesController.dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !user.hasPermission(toWrite: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }
        
        // user privileges
        if let type = File.FileType.type(path: parentPath) {
            switch type {
            case .uploads, .dropbox:
                if !user.hasPrivilege(name: "wired.account.transfer.upload_files") {
                    App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                    return
                }
            default:
                if !user.hasPrivilege(name: "wired.account.transfer.upload_anywhere") {
                    App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                    return
                }
            }
        } else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }
        
        let dataSize = message.uint64(forField: "wired.transfer.data_size") ?? UInt64(0)
        let rsrcSize = message.uint64(forField: "wired.transfer.rsrc_size") ?? UInt64(0)
        
        if let transfer = App.transfersController.upload(path: normalizedPath,
                                                         dataSize: dataSize,
                                                         rsrcSize: rsrcSize,
                                                         executable: false,
                                                         client: client, message: message) {
            client.transfer = transfer
            
            do {
                try client.socket.set(interactive: false)
            } catch {
                App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
                client.state = .DISCONNECTED
                client.transfer = nil
                return
            }
                        
            if(!App.transfersController.run(transfer: transfer, client: client, message: message)) {
                App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
                client.state = .DISCONNECTED
            }
            
            client.transfer = nil
        } else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }


    private func receiveUploadDirectory(_ client:Client, _ message:P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        if !user.hasPrivilege(name: "wired.account.transfer.upload_directories") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let path = message.string(forField: "wired.file.path") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        // sanitize checks
        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let normalizedPath = NSString(string: path).standardizingPath
        let realPath = App.filesController.real(path: normalizedPath)

        // file privileges
        if let privilege = App.filesController.dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !user.hasPermission(toWrite: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }

        let parentPath = realPath.stringByDeletingLastPathComponent

        guard let parentType = File.FileType.type(path: parentPath) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if parentType == .directory && !user.hasPrivilege(name: "wired.account.transfer.upload_anywhere") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        do {
            try FileManager.default.createDirectory(atPath: realPath, withIntermediateDirectories: true, attributes: [FileAttributeKey.posixPermissions: 0o777])
        } catch {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if parentType != .directory {
            _ = File.FileType.set(type: parentType, path: realPath)
        }

        App.indexController.addIndex(forPath: realPath)
        App.filesController.notifyDirectoryChanged(path: normalizedPath.stringByDeletingLastPathComponent)
        App.serverController.replyOK(client: client, message: message)
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

    private func receiveAccountListUsers(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let users = App.usersController.users()
        let defaultDate = Date(timeIntervalSince1970: 0)

        for listedUser in users {
            guard let username = listedUser.username else { continue }

            let reply = P7Message(withName: "wired.account.user_list", spec: self.spec)
            reply.addParameter(field: "wired.account.name", value: username)
            reply.addParameter(field: "wired.account.full_name", value: listedUser.fullName ?? "")
            reply.addParameter(field: "wired.account.comment", value: listedUser.comment ?? "")
            reply.addParameter(field: "wired.account.creation_time", value: listedUser.creationTime ?? defaultDate)
            reply.addParameter(field: "wired.account.modification_time", value: listedUser.modificationTime ?? defaultDate)
            reply.addParameter(field: "wired.account.login_time", value: listedUser.loginTime ?? defaultDate)
            reply.addParameter(field: "wired.account.edited_by", value: listedUser.editedBy ?? "")
            let downloads = UInt32(clamping: Int(listedUser.downloads ?? 0))
            let downloadTransferred = UInt64(clamping: Int(listedUser.downloadTransferred ?? 0))
            let uploads = UInt32(clamping: Int(listedUser.uploads ?? 0))
            let uploadTransferred = UInt64(clamping: Int(listedUser.uploadTransferred ?? 0))

            reply.addParameter(field: "wired.account.downloads", value: downloads)
            reply.addParameter(field: "wired.account.download_transferred", value: downloadTransferred)
            reply.addParameter(field: "wired.account.uploads", value: uploads)
            reply.addParameter(field: "wired.account.upload_transferred", value: uploadTransferred)
            reply.addParameter(field: "wired.account.group", value: listedUser.group ?? "")
            reply.addParameter(field: "wired.account.groups", value: listedUser.groups?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? [])
            reply.addParameter(field: "wired.account.password", value: listedUser.password ?? "")
            reply.addParameter(field: "wired.account.color", value: UInt32(listedUser.color ?? "") ?? 0)

            self.reply(client: client, reply: reply, message: message)
        }

        let done = P7Message(withName: "wired.account.user_list.done", spec: self.spec)
        self.reply(client: client, reply: done, message: message)
    }

    private func receiveAccountListGroups(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let groups = App.usersController.groups()
        let defaultDate = Date(timeIntervalSince1970: 0)

        for listedGroup in groups {
            guard let groupName = listedGroup.name else { continue }

            let reply = P7Message(withName: "wired.account.group_list", spec: self.spec)
            reply.addParameter(field: "wired.account.name", value: groupName)
            reply.addParameter(field: "wired.account.comment", value: "")
            reply.addParameter(field: "wired.account.creation_time", value: defaultDate)
            reply.addParameter(field: "wired.account.modification_time", value: defaultDate)
            reply.addParameter(field: "wired.account.edited_by", value: "")
            reply.addParameter(field: "wired.account.color", value: UInt32(listedGroup.color ?? "") ?? 0)

            self.reply(client: client, reply: reply, message: message)
        }

        let done = P7Message(withName: "wired.account.group_list.done", spec: self.spec)
        self.reply(client: client, reply: done, message: message)
    }

    private func receiveAccountReadUser(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.read_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.userWithPrivileges(withUsername: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        let reply = accountUserMessage(for: account, name: "wired.account.user")
        self.reply(client: client, reply: reply, message: message)
    }

    private func receiveAccountReadGroup(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.read_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.groupWithPrivileges(withName: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        let reply = accountGroupMessage(for: account, name: "wired.account.group")
        self.reply(client: client, reply: reply, message: message)
    }

    private func receiveAccountEditUser(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.edit_users") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.userWithPrivileges(withUsername: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        if let newName = message.string(forField: "wired.account.new_name"), !newName.isEmpty, newName != name {
            if App.usersController.user(withUsername: newName) != nil {
                App.serverController.replyError(client: client, error: "wired.error.account_exists", message: message)
                return
            }
            account.username = newName
        }

        if let fullName = message.string(forField: "wired.account.full_name") {
            account.fullName = fullName
        }
        if let comment = message.string(forField: "wired.account.comment") {
            account.comment = comment
        }
        if let password = message.string(forField: "wired.account.password"), !password.isEmpty {
            account.password = password
        }
        if let group = message.string(forField: "wired.account.group") {
            account.group = group
        }
        if let secondaryGroups = message.stringList(forField: "wired.account.groups") {
            account.groups = secondaryGroups.joined(separator: ", ")
        }

        account.editedBy = requestingUser.username ?? ""
        account.modificationTime = Date()

        var privilegesSaved = true

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                if let value = message.bool(forField: privilege) {
                    if !App.usersController.setUserPrivilege(privilege, value: value, for: account) {
                        privilegesSaved = false
                    }
                }
            case .enum32, .uint32:
                if privilege == "wired.account.color", let value = message.uint32(forField: privilege) {
                    account.color = String(value)
                }
            default:
                break
            }
        }

        if let color = message.enumeration(forField: "wired.account.color")
            ?? message.uint32(forField: "wired.account.color") {
            account.color = String(color)
        }

        if !privilegesSaved {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        if !App.usersController.save(user: account) {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)

        let updatedName = account.username ?? name
        if updatedName != name {
            self.broadcastAccountsChangedToSubscribers()
        }

        self.reloadPrivilegesForLoggedInUsers(matchingAccountNames: [name, updatedName])
    }

    private func receiveAccountEditGroup(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.edit_groups") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.groupWithPrivileges(withName: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        if let newName = message.string(forField: "wired.account.new_name"), !newName.isEmpty, newName != name {
            if App.usersController.group(withName: newName) != nil {
                App.serverController.replyError(client: client, error: "wired.error.account_exists", message: message)
                return
            }
            account.name = newName
        }

        var privilegesSaved = true

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                if let value = message.bool(forField: privilege) {
                    if !App.usersController.setGroupPrivilege(privilege, value: value, for: account) {
                        privilegesSaved = false
                    }
                }
            case .enum32, .uint32:
                if privilege == "wired.account.color", let value = message.uint32(forField: privilege) {
                    account.color = String(value)
                }
            default:
                break
            }
        }

        if let color = message.enumeration(forField: "wired.account.color")
            ?? message.uint32(forField: "wired.account.color") {
            account.color = String(color)
        }

        if !privilegesSaved {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        if !App.usersController.save(group: account) {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)

        let updatedName = account.name ?? name
        if updatedName != name {
            self.broadcastAccountsChangedToSubscribers()
        }

        self.reloadPrivilegesForLoggedInUsers(affectedByGroups: [name, updatedName])
    }

    private func receiveAccountSubscribeAccounts(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if client.isSubscribedToAccounts {
            App.serverController.replyError(client: client, error: "wired.error.already_subscribed", message: message)
            return
        }

        client.isSubscribedToAccounts = true
        App.serverController.replyOK(client: client, message: message)
    }

    private func receiveAccountUnsubscribeAccounts(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if !client.isSubscribedToAccounts {
            App.serverController.replyError(client: client, error: "wired.error.not_subscribed", message: message)
            return
        }

        client.isSubscribedToAccounts = false
        App.serverController.replyOK(client: client, message: message)
    }

    private func accountUserMessage(for account: User, name: String) -> P7Message {
        let defaultDate = Date(timeIntervalSince1970: 0)
        let reply = P7Message(withName: name, spec: self.spec)

        reply.addParameter(field: "wired.account.name", value: account.username ?? "")
        reply.addParameter(field: "wired.account.full_name", value: account.fullName ?? "")
        reply.addParameter(field: "wired.account.comment", value: account.comment ?? "")
        reply.addParameter(field: "wired.account.password", value: account.password ?? "")
        reply.addParameter(field: "wired.account.group", value: account.group ?? "")
        reply.addParameter(field: "wired.account.groups", value: account.groups?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? [])
        reply.addParameter(field: "wired.account.creation_time", value: account.creationTime ?? defaultDate)
        reply.addParameter(field: "wired.account.modification_time", value: account.modificationTime ?? defaultDate)
        reply.addParameter(field: "wired.account.login_time", value: account.loginTime ?? defaultDate)
        reply.addParameter(field: "wired.account.edited_by", value: account.editedBy ?? "")
        reply.addParameter(field: "wired.account.downloads", value: UInt32(clamping: Int(account.downloads ?? 0)))
        reply.addParameter(field: "wired.account.uploads", value: UInt32(clamping: Int(account.uploads ?? 0)))
        reply.addParameter(field: "wired.account.download_transferred", value: UInt64(clamping: Int(account.downloadTransferred ?? 0)))
        reply.addParameter(field: "wired.account.upload_transferred", value: UInt64(clamping: Int(account.uploadTransferred ?? 0)))

        let privilegesByName = Dictionary(uniqueKeysWithValues: account.privileges.map { (($0.name ?? ""), $0.value ?? false) })

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                reply.addParameter(field: privilege, value: privilegesByName[privilege] ?? false)
            case .enum32, .uint32:
                if privilege == "wired.account.color" {
                    reply.addParameter(field: privilege, value: UInt32(account.color ?? "") ?? 0)
                } else {
                    reply.addParameter(field: privilege, value: UInt32(0))
                }
            default:
                break
            }
        }

        return reply
    }

    private func accountPrivilegesMessage(for account: User) -> P7Message {
        let reply = P7Message(withName: "wired.account.privileges", spec: self.spec)
        let privilegesByName = Dictionary(uniqueKeysWithValues: account.privileges.map { (($0.name ?? ""), $0.value ?? false) })

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                reply.addParameter(field: privilege, value: privilegesByName[privilege] ?? false)
            case .enum32, .uint32:
                if privilege == "wired.account.color" {
                    reply.addParameter(field: privilege, value: UInt32(account.color ?? "") ?? 0)
                } else {
                    reply.addParameter(field: privilege, value: UInt32(0))
                }
            default:
                break
            }
        }

        return reply
    }

    private func broadcastAccountsChangedToSubscribers() {
        let broadcast = P7Message(withName: "wired.account.accounts_changed", spec: self.spec)

        for connectedClient in App.clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard connectedClient.isSubscribedToAccounts else { continue }
            guard let user = connectedClient.user else { continue }

            if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
                connectedClient.isSubscribedToAccounts = false
                continue
            }

            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func reloadPrivilegesForLoggedInUsers(matchingAccountNames accountNames: [String]) {
        let normalizedNames = Set(accountNames.map { normalizedAccountIdentifier($0) }.filter { !$0.isEmpty })
        guard !normalizedNames.isEmpty else { return }

        for connectedClient in App.clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard let currentName = connectedClient.user?.username else { continue }
            let normalizedCurrentName = normalizedAccountIdentifier(currentName)
            guard normalizedNames.contains(normalizedCurrentName) else { continue }

            guard let refreshedUser = userWithPrivileges(matchingUsername: currentName) else { continue }

            connectedClient.user = refreshedUser

            if !refreshedUser.hasPrivilege(name: "wired.account.account.list_accounts") {
                connectedClient.isSubscribedToAccounts = false
            }

            _ = self.send(message: self.accountPrivilegesMessage(for: refreshedUser), client: connectedClient)
        }
    }

    private func reloadPrivilegesForLoggedInUsers(affectedByGroups groupNames: [String]) {
        let normalizedNames = Set(groupNames.map { normalizedAccountIdentifier($0) }.filter { !$0.isEmpty })
        guard !normalizedNames.isEmpty else { return }

        for connectedClient in App.clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard let currentUser = connectedClient.user else { continue }
            guard let username = currentUser.username else { continue }

            let currentGroups = normalizedGroupIdentifiers(for: currentUser)
            let wasInAffectedGroup = !currentGroups.isDisjoint(with: normalizedNames)
            guard wasInAffectedGroup else { continue }

            guard let refreshedUser = userWithPrivileges(matchingUsername: username) else { continue }
            connectedClient.user = refreshedUser

            if !refreshedUser.hasPrivilege(name: "wired.account.account.list_accounts") {
                connectedClient.isSubscribedToAccounts = false
            }

            _ = self.send(message: self.accountPrivilegesMessage(for: refreshedUser), client: connectedClient)
        }
    }

    private func normalizedAccountIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedGroupIdentifiers(for user: User) -> Set<String> {
        var groups = Set<String>()

        if let primary = user.group {
            let normalized = normalizedAccountIdentifier(primary)
            if !normalized.isEmpty {
                groups.insert(normalized)
            }
        }

        if let secondaryGroups = user.groups {
            for raw in secondaryGroups.split(separator: ",") {
                let normalized = normalizedAccountIdentifier(String(raw))
                if !normalized.isEmpty {
                    groups.insert(normalized)
                }
            }
        }

        return groups
    }

    private func userWithPrivileges(matchingUsername username: String) -> User? {
        if let exact = App.usersController.userWithPrivileges(withUsername: username) {
            return exact
        }

        let normalizedUsername = normalizedAccountIdentifier(username)
        guard !normalizedUsername.isEmpty else { return nil }

        for listedUser in App.usersController.users() {
            guard let listedUsername = listedUser.username else { continue }
            if normalizedAccountIdentifier(listedUsername) == normalizedUsername {
                return App.usersController.userWithPrivileges(withUsername: listedUsername)
            }
        }

        return nil
    }

    private func accountGroupMessage(for account: Group, name: String) -> P7Message {
        let defaultDate = Date(timeIntervalSince1970: 0)
        let reply = P7Message(withName: name, spec: self.spec)

        reply.addParameter(field: "wired.account.name", value: account.name ?? "")
        reply.addParameter(field: "wired.account.comment", value: "")
        reply.addParameter(field: "wired.account.creation_time", value: defaultDate)
        reply.addParameter(field: "wired.account.modification_time", value: defaultDate)
        reply.addParameter(field: "wired.account.edited_by", value: "")

        let privilegesByName = Dictionary(uniqueKeysWithValues: account.privileges.map { (($0.name ?? ""), $0.value ?? false) })

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                reply.addParameter(field: privilege, value: privilegesByName[privilege] ?? false)
            case .enum32, .uint32:
                if privilege == "wired.account.color" {
                    reply.addParameter(field: privilege, value: UInt32(account.color ?? "") ?? 0)
                } else {
                    reply.addParameter(field: privilege, value: UInt32(0))
                }
            default:
                break
            }
        }

        return reply
    }

    private func accountPrivilegesIncludingColor() -> [String] {
        var privileges = spec?.accountPrivileges ?? []

        if spec?.fieldsByName["wired.account.color"] != nil,
           !privileges.contains("wired.account.color") {
            privileges.append("wired.account.color")
        }

        return privileges
    }
    
    
    
    
    // MARK: -
    
    private func sendUserStatus(forClient client:Client) {
        for chat in App.chatsController.publicChats {
            let broadcast = P7Message(withName: "wired.chat.user_status", spec: self.spec)
            
            broadcast.addParameter(field: "wired.chat.id", value: chat.chatID)
            broadcast.addParameter(field: "wired.user.id", value: client.userID)
            broadcast.addParameter(field: "wired.user.idle", value: client.idle)
            broadcast.addParameter(field: "wired.user.nick", value: client.nick)
            broadcast.addParameter(field: "wired.user.status", value: client.status)
            broadcast.addParameter(field: "wired.user.icon", value: client.icon)
            broadcast.addParameter(field: "wired.account.color", value: client.accountColor)
            
            App.clientsController.broadcast(message: broadcast)
        }
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
            let fullPath = App.rootPath.stringByAppendingPathComponent(path: bannerPath)
            if let data = try? Data(contentsOf: URL.init(fileURLWithPath: fullPath)) {
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
            
            DispatchQueue.global(qos: .default).async {
                let p7Socket = P7Socket(socket: socket, spec: self.spec)
                
                p7Socket.ecdh = self.ecdh
                p7Socket.passwordProvider = App.usersController
                
                let userID = App.usersController.nextUserID()
                let client = Client(userID: userID, socket: p7Socket)
                
                do {
                    try p7Socket.accept(
                        compression: SERVER_COMPRESSION,
                        cipher:      SERVER_CIPHER,
                        checksum:    SERVER_CHECKSUM
                    )
                    
                    Logger.info("Accept new connection from \(p7Socket.remoteAddress ?? "unknow")")

                    App.clientsController.addClient(client: client)
                    
                    client.state = .CONNECTED
                    
                    self.clientLoop(client)
   
                } catch {
                    p7Socket.disconnect()
                }
            }
                
        } catch let error {
            if let socketError = error as? Socket.Error {
                Logger.error(socketError.description)
            } else {
                Logger.error("Socket accept error: \(error.localizedDescription)")
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
            
            do {
                let message = try client.socket.readMessage()
                
                for delegate in delegates {
                    delegate.receiveMessage(client: client, message: message)
                }
            } catch {
                for delegate in delegates {
                    delegate.clientDisconnected(client: client)
                }
                
                break
            }
        }
    }
}
