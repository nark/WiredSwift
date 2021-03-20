//
//  main.swift
//  Server
//
//  Created by Rafael Warnault on 19/03/2021.
//

import Foundation
import WiredSwift

public class TestServer : ServerDelegate, SocketPasswordDelegate {
    
    var server:Server!
    var userPasswords:[String:String] = [:]
    var connectedUsers:[String:User] = [:]

    init() {
        self.userPasswords["guest"] = "".sha1()
        self.userPasswords["admin"] = "admin".sha1()
    }
    
    
    // MARK: -
    public func userForSocket(socket: P7Socket) -> User? {
        return User(socket)
    }
    
    public func userConnected(user: User) {
        if let username = user.socket?.username {
            user.username = username
            self.connectedUsers[username] = user
            
            Logger.info("Connected users: \(connectedUsers)")
            
            self.userLoop(user)
        } else {
            Logger.info("Username not found")
        }
    }
    
    public func userDisconnected(user:User) {
        if let username = user.socket?.username {
            user.socket?.disconnect()
            
            self.connectedUsers[username] = nil
            
            Logger.info("Connected users: \(connectedUsers)")
        }
    }
    
    
    
    // MARK: -
    
    public func passwordForUsername(username: String) -> String? {
        return self.userPasswords[username]
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
                    print("Disconnected?")
                    self.userDisconnected(user: user)
                    break
                }
            }
        }
    }
    
    func receiveMessage(_ user:User, _ message:P7Message) {
        if message.name == "wired.client_info" {
            let response = P7Message(withName: "wired.server_info", spec: self.server.spec)
            
            response.addParameter(field: "wired.info.application.name", value: "Noded")
            response.addParameter(field: "wired.info.application.version", value: "0.1")
            response.addParameter(field: "wired.info.application.build", value: "0x0")
            response.addParameter(field: "wired.info.os.name", value: "MacOS")
            response.addParameter(field: "wired.info.os.version", value: "10.15")
            response.addParameter(field: "wired.info.arch", value: "x86_64")
            response.addParameter(field: "wired.info.supports_rsrc", value: false)
            response.addParameter(field: "wired.info.name", value: "Noded Server")
            response.addParameter(field: "wired.info.description", value: "Welcome to my node")
            response.addParameter(field: "wired.info.banner", value: Data())
            response.addParameter(field: "wired.info.downloads", value: UInt32(0))
            response.addParameter(field: "wired.info.ulpoads", value: UInt32(0))
            response.addParameter(field: "wired.info.download_speed", value: UInt32(0))
            response.addParameter(field: "wired.info.upload_speed", value: UInt32(0))
            response.addParameter(field: "wired.info.start_time", value: Date())
            response.addParameter(field: "wired.info.files.count", value: UInt64(0))
            response.addParameter(field: "wired.info.files.size", value: UInt64(0))
            
            user.socket?.write(response)
        }
    }
}



let server = TestServer()
server.start()
