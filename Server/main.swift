//
//  main.swift
//  Server
//
//  Created by Rafael Warnault on 19/03/2021.
//

import Foundation
import WiredSwift
import GRDB

public class WiredServer : ServerDelegate, SocketPasswordDelegate {
    var server:Server!
    var dbPool:DatabasePool!
    var connectedUsers:[String:User] = [:]
    var userID:UInt32 = 0
    

    init() {
        let path = "/Users/nark/wired3.db"
        
        do {
            self.dbPool = try DatabasePool(path: path)
            
            self.createTables()
        } catch {
            Logger.error("Cannot open database file")
        }
    }
    
    
    // MARK: -
    func createTables() {
        do {
            try dbPool.write { db in
                try db.execute(sql: """
                    CREATE TABLE users (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name TEXT NOT NULL,
                        password TEXT NOT NULL)
                    """)
                
                try db.execute(
                    sql: "INSERT INTO users (name, password) VALUES (?, ?)",
                    arguments: ["guest", "".sha1()])
                
                try db.execute(
                    sql: "INSERT INTO users (name, password) VALUES (?, ?)",
                    arguments: ["admin", "admin".sha1()])
            }
        } catch { }
    }
    
    
    // MARK: -
    public func userForSocket(socket: P7Socket) -> User? {
        userID += 1
        return User(socket, userID: userID)
    }
    
    public func userConnected(user: User) {
        if let username = user.socket?.username {
            user.username = username
            self.connectedUsers[username] = user
            
            WiredSwift.Logger.info("Connected users: \(connectedUsers)")
            
            self.userLoop(user)
        } else {
            WiredSwift.Logger.info("Username not found")
        }
    }
    
    public func userDisconnected(user:User) {
        if let username = user.socket?.username {
            user.socket?.disconnect()
            
            self.connectedUsers[username] = nil
            
            WiredSwift.Logger.info("Connected users: \(connectedUsers)")
        }
    }
    
    
    
    // MARK: -
    
    public func passwordForUsername(username: String) -> String? {
        var password:String? = nil
        
        do {
            try dbPool.read { db in
                if let row = try Row.fetchOne(db, sql: "SELECT * FROM users WHERE name = ?", arguments: [username]) {
                    password = row["password"]
                }
            }
        } catch {  }
        
        return password
    }
    

    
    // MARK: -
    func start() {
        let specURL = URL(string: "https://wired.read-write.fr/wired.xml")!

        guard let spec = P7Spec(withUrl: specURL) else {
            exit(-111)
        }

        self.server = Server(port: 4871, spec: spec)
        self.server.delegate = self
        self.server.listen()
    }
    
    
    func userLoop(_ user:User) {
        while true {
            if let socket = user.socket {
                if socket.connected == false {
                    self.userDisconnected(user: user)
                    break
                }
                
                if let message = socket.readMessage() {
                    print(message.xml())
                    self.receiveMessage(user, message)
                } else {
                    self.userDisconnected(user: user)
                    break
                }
            }
        }
    }
    
    func receiveMessage(_ user:User, _ message:P7Message) {
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
        else {
            WiredSwift.Logger.warning("Message \(message.name ?? "unknow message") not implemented")
        }
    }
    
    
    func receiveClientInfo(_ user:User, _ message:P7Message) {
        let response = P7Message(withName: "wired.server_info", spec: self.server.spec)
        
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
        response.addParameter(field: "wired.info.start_time", value: Date())
        response.addParameter(field: "wired.info.files.count", value: UInt64(0))
        response.addParameter(field: "wired.info.files.size", value: UInt64(0))
                
        _ = user.socket?.write(response)
    }
    
    func receiveUserSetNick(_ user:User, _ message:P7Message) {
        let response = P7Message(withName: "wired.okay", spec: self.server.spec)
        _ = user.socket?.write(response)
    }
    
    func receiveUserSetStatus(_ user:User, _ message:P7Message) {
        let response = P7Message(withName: "wired.okay", spec: self.server.spec)
        _ = user.socket?.write(response)
    }
    
    func receiveUserSetIcon(_ user:User, _ message:P7Message) {
        let response = P7Message(withName: "wired.okay", spec: self.server.spec)
        _ = user.socket?.write(response)
    }
    
    func receiveSendLogin(_ user:User, _ message:P7Message) {
        let response = P7Message(withName: "wired.login", spec: self.server.spec)
        
        response.addParameter(field: "wired.user.id", value: user.userID)
        
        _ = user.socket?.write(response)
        
        let response2 = P7Message(withName: "wired.account.privileges", spec: self.server.spec)
        
        _ = user.socket?.write(response2)
    }
}



let server = WiredServer()
server.start()
