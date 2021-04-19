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
    func newUser(forSocket socket:P7Socket) -> User?
    func userConnected(user:User) -> Bool
    func userDisconnected(user:User)
    func receiveMessage(user:User, message:P7Message)
    func disconnectUser(user:User)
}


public class ServerController {
    public var port: Int = DEFAULT_PORT
    public var spec: P7Spec!
    public var isRunning:Bool = false
    public var delegate:ServerDelegate?
    
    private var socket:Socket!
    private let rsa = RSA(bits: RSA_KEY_BITS)
    private let group = DispatchGroup()
    
    public init(port: Int, spec: P7Spec) {
       self.port = port
       self.spec = spec
    }
    
    public func listen() {
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
            var user:User? = nil
            
            p7Socket.rsa = self.rsa
            
            if self.delegate != nil {
                if let d = self.delegate as? SocketPasswordDelegate {
                    p7Socket.passwordProvider = d
                }
            }
            
            if p7Socket.accept(compression: P7Socket.Compression.DEFLATE,
                               cipher:      P7Socket.CipherType.RSA_AES_256_SHA256,
                               checksum:    P7Socket.Checksum.SHA256) {
                
                user = self.delegate?.newUser(forSocket: p7Socket)
                
                if self.delegate != nil && user != nil {
                    if self.delegate!.userConnected(user: user!) {
                        // p7Socket.disconnect() // ?
                        DispatchQueue.global(qos: .default).async {
                            self.userLoop(user!)
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
                    if self.delegate != nil {
                        self.delegate!.userDisconnected(user: user)
                    }
                    
                    break
                }
                
                if let message = socket.readMessage() {
                    if self.delegate != nil {
                        self.delegate!.receiveMessage(user: user, message: message)
                    }
                } else {
                    if self.delegate != nil {
                        self.delegate!.userDisconnected(user: user)
                    }
                    break
                }
            }
        }
    }
}
