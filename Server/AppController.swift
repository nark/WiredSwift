//
//  WiredServer.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift


public let DEFAULT_PORT = 4875
public let RSA_KEY_BITS = 2048


public class AppController : ServerDelegate, SocketPasswordDelegate {
    var port:Int = DEFAULT_PORT
    
    var serverController:ServerController!
    
    var databaseController:DatabaseController!
    var usersController:UsersController!
    var chatsController:ChatsController!
    
    
    // MARK: - Public
    public init(dbPath:String, port:Int = DEFAULT_PORT) {
        let url = URL(fileURLWithPath: dbPath)
        
        self.port = port

        self.databaseController = DatabaseController(baseURL: url)
        self.usersController = UsersController()
        self.chatsController = ChatsController()
    }
    

    
    public func start() {
        let specURL = URL(string: "https://wired.read-write.fr/wired.xml")!
        
        guard let spec = P7Spec(withUrl: specURL) else {
            exit(-111)
        }

        self.serverController = ServerController(port: self.port, spec: spec)
        self.serverController.delegate = self
        self.serverController.listen()
    }
    
    
    
    
    
    // MARK: - ServerDelegate
    public func newUser(forSocket socket: P7Socket) -> User? {
        return User(socket, userID: self.usersController.nextUserID())
    }
    
    
    public func userConnected(user: User) -> Bool {
        if let username = user.socket?.username {
            user.username = username
            
            self.usersController.addUser(user: user)
            
            return true
        } else {
            WiredSwift.Logger.warning("Username not found")
        }
        
        return false
    }
    
    
    public func userDisconnected(user:User) {
        self.usersController.removeUser(user: user)
    }
    
    
    public func disconnectUser(user: User) {
        self.usersController.removeUser(user: user)
    }
    
    
    public func receiveMessage(user:User, message:P7Message) {
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
            self.receiveSendLogin(user, message)
        }
            else if message.name == "wired.chat.send_say" {
                self.receiveChatSay(user, message)

            }
        else if message.name == "wired.chat.join_chat" {
            if  let chatID = message.uint32(forField: "wired.chat.id"),
                let transactionID = message.uint32(forField: "wired.transaction"){
                self.chatsController.userJoin(chatID: chatID, user: user, transactionID: transactionID)
            }
        }
        else if message.name == "wired.chat.leave_chat" {
            if let chatID = message.uint32(forField: "wired.chat.id") {
                self.chatsController.userLeave(chatID: chatID, user: user)
            }
        }
        else {
            WiredSwift.Logger.warning("Message \(message.name ?? "unknow message") not implemented")
        }
    }
    
    
    
    // MARK: - SocketPasswordDelegate
    public func passwordForUsername(username: String) -> String? {
        return self.databaseController.passwordForUsername(username: username)
    }
    
    
    
    // MARK: - Private
    private func receiveClientInfo(_ user:User, _ message:P7Message) {
        let response = P7Message(withName: "wired.server_info", spec: self.serverController.spec)
        
        response.addParameter(field: "wired.info.application.name", value: "Wired 3.0")
        response.addParameter(field: "wired.info.application.version", value: "0.1")
        response.addParameter(field: "wired.info.application.build", value: "0")
        response.addParameter(field: "wired.info.os.name", value: "MacOS")
        response.addParameter(field: "wired.info.os.version", value: "10.15")
        response.addParameter(field: "wired.info.arch", value: "x86_64")
        
        response.addParameter(field: "wired.info.supports_rsrc", value: false)
        response.addParameter(field: "wired.info.name", value: "Noded Server")
        response.addParameter(field: "wired.info.description", value: "Welcome to my node")
        //response.addParameter(field: "wired.info.banner", value: Data())
        
        response.addParameter(field: "wired.info.downloads", value: UInt32(0))
        response.addParameter(field: "wired.info.uploads", value: UInt32(0))
        response.addParameter(field: "wired.info.download_speed", value: UInt32(0))
        response.addParameter(field: "wired.info.upload_speed", value: UInt32(0))
        //response.addParameter(field: "wired.info.start_time", value: Date())
        response.addParameter(field: "wired.info.files.count", value: UInt64(0))
        response.addParameter(field: "wired.info.files.size", value: UInt64(0))
                
        _ = user.socket?.write(response)
    }
    
    
    private func receiveUserSetNick(_ user:User, _ message:P7Message) {
        if let nick = message.string(forField: "wired.user.nick") {
            user.nick = nick
        }
                
        let response = P7Message(withName: "wired.okay", spec: self.serverController.spec)
        
        _ = user.socket?.write(response)
    }
    
    
    private func receiveUserSetStatus(_ user:User, _ message:P7Message) {
        if let status = message.string(forField: "wired.user.status") {
            user.status = status
        }
        
        let response = P7Message(withName: "wired.okay", spec: self.serverController.spec)
        _ = user.socket?.write(response)
    }
    
    
    private func receiveUserSetIcon(_ user:User, _ message:P7Message) {
        if let icon = message.data(forField: "wired.user.icon") {
            user.icon = icon
        }
        
        let response = P7Message(withName: "wired.okay", spec: self.serverController.spec)
        _ = user.socket?.write(response)
    }
    
    
    private func receiveSendLogin(_ user:User, _ message:P7Message) {
        let response = P7Message(withName: "wired.login", spec: self.serverController.spec)
        
        response.addParameter(field: "wired.user.id", value: user.userID)
        
        _ = user.socket?.write(response)
        
        let response2 = P7Message(withName: "wired.account.privileges", spec: self.serverController.spec)
        
        _ = user.socket?.write(response2)
    }
    
    
    private func receiveChatSay(_ user:User, _ message:P7Message) {
        for (userID, u) in self.usersController.connectedUsers {
            //if u.userID != user.userID {
                u.socket?.write(message)
            //}
        }
        
//        let response = P7Message(withName: "wired.okay", spec: self.server.spec)
//        _ = user.socket?.write(response)
    }
}
