//
//  Server.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 16/03/2021.
//

import Foundation
import SocketSwift

let DEFAULT_PORT = 4875
let RSA_KEY_BITS = 2048


public class User {
    public enum State:UInt32 {
        case CONNECTED           = 0
        case DISCONNECTED        = 1
    }
    
    public var username:String?
    public var socket:P7Socket?
    public var state:State = .DISCONNECTED
    public var ip:String?
    public var host:String?
    
    public init(_ socket:P7Socket) {
        self.socket = socket
        self.state  = .CONNECTED
        //self.ip = self.socket
    }
}

public protocol ServerDelegate: class {
    func userForSocket(socket:P7Socket) -> User?
    func userConnected(user:User)
    func userDisconnected(user:User)
}


public class Server {
    public var port: Int = DEFAULT_PORT
    public var spec: P7Spec!
    public var isRunning:Bool = false
    private var socket:Socket!
    private let rsa = RSA(bits: RSA_KEY_BITS)
    private let group = DispatchGroup()
    public var delegate:ServerDelegate?
    
    public var users:[User] = []

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
            Logger.info("Server listening on port \(self.port)")
            try self.socket.listen()
            
            Logger.info("Server accepts new connections...")
        
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
                user = self.delegate?.userForSocket(socket: p7Socket)
            }
            
            if p7Socket.accept(compression: P7Socket.Compression.DEFLATE,
                               cipher:      P7Socket.CipherType.RSA_AES_256_SHA1,
                               checksum:    P7Socket.Checksum.SHA1) {

                if self.delegate != nil && user != nil {
                    self.delegate?.userConnected(user: user!)
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
}
