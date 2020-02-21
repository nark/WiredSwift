//
//  Socket.swift
//  Wired 3
//
//  Created by Rafael Warnault on 18/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation
import SocketSwift
import CryptorRSA
import CryptoSwift
import CommonCrypto



public class P7Socket: NSObject {
    public enum Serialization:Int {
        case XML            = 0
        case BINARY         = 1
    }
    
    public enum Compression:UInt32 {
        case NONE           = 999
        case DEFLATE        = 0
    }
    
    public enum Checksum:Int {
        case NONE           = 999
        case SHA1           = 0
        case SHA256         = 1
    }
    
    public enum CipherType:UInt32 {
        case NONE           = 999
        case RSA_AES_128    = 0
        case RSA_AES_192    = 1
        case RSA_AES_256    = 2
        case RSA_BF_128     = 3
        case RSA_3DES_192   = 4
    }
    
    
    public var hostname: String!
    public var port: Int!
    public var spec: P7Spec!
    public var username: String = "guest"
    public var password: String!
    public var serialization: Serialization = .BINARY
    public var compression: Compression = .NONE
    public var cipherType: CipherType = .RSA_AES_256
    public var checksum: Checksum = .NONE
    public var sslCipher: P7Cipher!
    public var timeout: Int = 10
    public var errors: [Error] = []
    
    public var compressionEnabled: Bool = false
    public var compressionConfigured: Bool = false
    
    public var encryptionEnabled: Bool = false
    public var checksumEnabled: Bool = false
    
    public var localCompatibilityCheck: Bool = false
    public var remoteCompatibilityCheck: Bool = false
    
    public var remoteVersion: String!
    public var remoteName: String!
    
    public var connected: Bool = false
    
    private var socket: Socket!
    private var publicKey: String!
    
    public init(hostname: String, port: Int, spec: P7Spec) {
        self.hostname = hostname
        self.port = port
        self.spec = spec
    }

    
    public func connect(withHadshake handshake: Bool = true) -> Bool {
        do {
            self.socket = try Socket(.inet, type: .stream, protocol: .tcp)
            
            try socket.set(option: .receiveTimeout, TimeValue(seconds: 10, milliseconds: 0, microseconds: 0))
            try socket.set(option: .sendTimeout, TimeValue(seconds: 10, milliseconds: 0, microseconds: 0))
            try socket.set(option: .receiveBufferSize, 327680)
            
            let addr = try! socket.addresses(for: self.hostname, port: Port(self.port)).first!
            try self.socket.connect(address: addr)
            
            self.connected = true
            
            if handshake {
                if !self.connectHandshake() {
                    Logger.error("Handshake failed")
                    return false
                }
                
                if self.compression != .NONE {
                    self.configureCompression()
                }
                
                if self.checksum != .NONE {
                    self.configureChecksum()
                }
                
                if self.cipherType != .NONE {
                    if !self.connectKeyExchange() {
                        Logger.error("Key Exchange failed")
                        return false
                    }
                }
                
                if self.remoteCompatibilityCheck {
                    if !self.sendCompatibilityCheck() {
                        Logger.error("Remote Compatibility Check failed")
                        return false
                    }
                }
                
                if self.localCompatibilityCheck {
                    if !self.receiveCompatibilityCheck() {
                        Logger.error("Local Compatibility Check failed")
                        return false
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
        
        return true
    }
    
    
    
    public func disconnect() {
        self.socket.close()
    }
    
    
    public func write(_ message: P7Message) -> Bool {
        //usleep(100000)
        
        do {
            if self.serialization == .XML {
                let xml = message.xml()
                
                if let xmlData = xml.data(using: .utf8) {
                    try self.socket.write(xmlData.bytes)
                }
            }
            else if self.serialization == .BINARY {
                var messageData = message.bin()
                var lengthData = Data()
                lengthData.append(uint32: UInt32(messageData.count))
                
                Logger.debug("WRITE [\(self.hash)]: \(message.name!)")
                
                if self.compressionEnabled {
                    
                }
                
                if self.encryptionEnabled {
                    guard let encryptedMessageData = self.sslCipher.encrypt(data: messageData) else {
                        Logger.error("Cannot encrypt data")
                        return false
                    }
                    
                    messageData = encryptedMessageData
                    
                    lengthData = Data()
                    lengthData.append(uint32: UInt32(messageData.count))
                }
                
                try self.socket.write(lengthData.bytes)
                try self.socket.write(messageData.bytes)
            }
            
        } catch let error {
            if let socketError = error as? Socket.Error {
                Logger.error(socketError.description)
            } else {
                Logger.error(error.localizedDescription)
            }
        }
        
        return true
    }
    
    
    
    private func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int, timeout:TimeInterval = 1.0) -> Int {
        while let available = try? socket.wait(for: .read, timeout: timeout) {
            guard available else { continue } // timeout happend, try again
            
            let n = try? socket.read(buffer, size: len)
            
            return n ?? 0
        }
        
        return 0
    }
    
    
    
    public func readMessage() -> P7Message? {
        // hack to handle remote connection for now
        usleep(200000)
        
        var messageData = Data()
        var lengthBuffer = [Byte](repeating: 0, count: 4)
        var bytesRead = self.read(&lengthBuffer, maxLength: 4)

        if bytesRead > 0 {
            if self.serialization == .XML {
                if let xml = String(bytes: messageData, encoding: .utf8) {
                    let message = P7Message(withXML: xml, spec: self.spec)

                    return message
                }
            }
            else if self.serialization == .BINARY {
                if bytesRead >= 4 {
                    let messageLength = Data(lengthBuffer).uint32.bigEndian
                    
                    var messageBuffer = [Byte](repeating: 0, count: Int(messageLength))
                    bytesRead = self.read(&messageBuffer, maxLength: Int(messageLength))
                    
                    messageData = Data(messageBuffer)
                    
                    // data to message object
                    if messageData.count > 0 {
                        // decryption
                        if self.encryptionEnabled {
                            guard let decryptedMessageData = self.sslCipher.decrypt(data: messageData) else {
                                Logger.error("Cannot decrypt data")
                                return nil
                            }
                            messageData = decryptedMessageData
                        }
                        
                        print(messageData.toHex())
                        
                        // init response message
                        let message = P7Message(withData: messageData, spec: self.spec)
                        
                        Logger.debug("READ [\(self.hash)]: \(message.name!)")
                        
                        return message
                    }
                }
                else {
                    Logger.error("Nothing read, abort")
                }
            }
        }
        
        return nil
    }
    
    
    
    public func readOOB(_ data: Data, timeout:TimeInterval = 1.0) -> Int {
        var messageData = Data()
        var lengthBuffer = [Byte](repeating: 0, count: 4)
        var bytesRead = self.read(&lengthBuffer, maxLength: 4)

        if bytesRead >= 4 {
            let messageLength = Data(lengthBuffer).uint32.bigEndian
            
            print("messageLength : \(messageLength)")
            
            var messageBuffer = [Byte](repeating: 0, count: Int(messageLength))
            bytesRead = self.read(&messageBuffer, maxLength: Int(messageLength))
            
            messageData = Data(messageBuffer)
            
            // data to message object
            if messageData.count > 0 {
                // decryption
                if self.encryptionEnabled {
                    guard let decryptedMessageData = self.sslCipher.decrypt(data: messageData) else {
                        Logger.error("Cannot decrypt data")
                        return -1
                    }
                    messageData = decryptedMessageData
                }
                
                print(messageData.toHex())
                
                return messageData.count
            }
        }
        else {
            Logger.error("Nothing read, abort")
        }
        
        return -1
    }
    
    
    
    
    private func connectHandshake() -> Bool {
        var message = P7Message(withName: "p7.handshake.client_handshake", spec: self.spec)
        message.addParameter(field: "p7.handshake.version", value: "1.0")
        message.addParameter(field: "p7.handshake.protocol.name", value: "Wired")
        message.addParameter(field: "p7.handshake.protocol.version", value: "2.0b55")
        
        // handshake settings
        if self.serialization == .BINARY {
            if self.cipherType != .NONE {
                message.addParameter(field: "p7.handshake.encryption", value: self.cipherType.rawValue)
            }
            
            if self.compression != .NONE {
                message.addParameter(field: "p7.handshake.compression", value: self.compression.rawValue)
            }
        }
        
        _ = self.write(message)
        
        guard let response = self.readMessage() else {
            Logger.error("Handshake Failed: Should Receive Message: p7.handshake.server_handshake")
            return false
        }
        
        if response.name != "p7.handshake.server_handshake" {
            Logger.error("Handshake Failed: Unexpected message \(response.name!) instead of p7.handshake.server_handshake")
        }
        
        guard let p7Version = response.string(forField: "p7.handshake.version") else {
            Logger.error("Handshake Failed: Built-in protocol version field is missing (p7.handshake.version)")
            return false
        }
        
        if p7Version != spec.builtinProtocolVersion {
            Logger.error("Handshake Failed: Local version is \(p7Version) but remote version is \(spec.builtinProtocolVersion!)")
            return false
        }
        
        self.remoteName = response.string(forField: "p7.handshake.protocol.name")
        self.remoteVersion = response.string(forField: "p7.handshake.protocol.version")
        
        self.localCompatibilityCheck = !spec.isCompatibleWithProtocol(withName: self.remoteName, version: self.remoteVersion)
        
        if self.serialization == .BINARY {
            if let comp = response.enumeration(forField: "p7.handshake.compression") {
                self.compression = P7Socket.Compression(rawValue: comp)!
            }
            if let cip = response.enumeration(forField: "p7.handshake.encryption") {
                self.cipherType = P7Socket.CipherType(rawValue: cip)!
            }
            if let _ = response.enumeration(forField: "p7.handshake.checksum") {
                // TODO: impl checksums
                // self.checksum = P7Socket.Checksum(rawValue: chs)!
            }
        }
        
        if let remoteCheck = response.bool(forField: "p7.handshake.compatibility_check"), remoteCheck == false {
            self.remoteCompatibilityCheck = false
        }
        
        message = P7Message(withName: "p7.handshake.acknowledge", spec: self.spec)
        
        if self.localCompatibilityCheck {
            message.addParameter(field: "p7.handshake.compatibility_check", value: true)
        }
        
        _ = self.write(message)
        
        return true
    }
    
    
    private func connectKeyExchange() -> Bool  {
        guard let response = self.readMessage() else {
            Logger.error("Handshake Failed: cannot read server key")
            return false
        }
        
        if response.name != "p7.encryption.server_key" {
            Logger.error("Message should be 'p7.encryption.server_key', not '\(response.name!)'")
        }
        
        guard let publicRSAKeyData = response.data(forField: "p7.encryption.public_key") else {
            Logger.error("Message has no 'p7.encryption.public_key' field")
            return false
        }
        
        self.publicKey = SwKeyConvert.PublicKey.derToPKCS8PEM(publicRSAKeyData)
        
        if self.publicKey == nil {
            Logger.error("Public key cannot be created")
            return false
        }
        
        self.sslCipher = P7Cipher(cipher: self.cipherType)
        
        if self.sslCipher == nil {
            Logger.error("Cipher cannot be created")
            return false
        }
        
        if self.password == nil || self.password == "" {
            self.password = "".sha1()
        } else {
            self.password = self.password.sha1()
        }
        
        let passwordData = self.password.data(using: .utf8)!
        
        var clientPassword1 = passwordData
        clientPassword1.append(publicRSAKeyData)
        clientPassword1 = clientPassword1.sha1().toHexString().data(using: .utf8)!
        
        var clientPassword2 = publicRSAKeyData
        clientPassword2.append(passwordData)
        clientPassword2 = clientPassword2.sha1().toHexString().data(using: .utf8)!
        
        let message = P7Message(withName: "p7.encryption.client_key", spec: self.spec)
        
        guard let encryptedCipherKey = self.encryptData(self.sslCipher!.cipherKey.data(using: .utf8)!) else {
            return false
        }
        
        guard let encryptedCipherIV = self.encryptData(Data(self.sslCipher!.cipherIV))  else {
            return false
        }
        
        guard let d = self.username.data(using: .utf8), let encryptedUsername = self.encryptData(d)  else {
            return false
        }
        
        guard let encryptedClientPassword1 = self.encryptData(clientPassword1)  else {
            return false
        }
        
        message.addParameter(field: "p7.encryption.cipher.key", value: encryptedCipherKey)
        message.addParameter(field: "p7.encryption.cipher.iv", value: encryptedCipherIV)
        message.addParameter(field: "p7.encryption.username", value: encryptedUsername)
        message.addParameter(field: "p7.encryption.client_password", value: encryptedClientPassword1)
        
        _ = self.write(message)
        
        guard let response2 = self.readMessage() else {
            return false
        }
        
        if response2.name == "p7.encryption.authentication_error" {
            Logger.error("Authentification failed for '\(self.username)'")
            return false
        }
        
        if response2.name != "p7.encryption.acknowledge" {
            Logger.error("Message should be 'p7.encryption.acknowledge', not '\(response2.name!)'")
            return false
        }
    
        guard let encryptedServerPasswordData = response2.data(forField: "p7.encryption.server_password") else {
            Logger.error("Message has no 'p7.encryption.server_password' field")
            return false
        }
        
        if let serverPasswordData = self.sslCipher.decrypt(data: encryptedServerPasswordData) {
            //print("serverPasswordData : \(serverPasswordData.toHex())")
            //print("clientPassword2 : \(clientPassword2.toHex())")
            
            // TODO: write my own passwords comparison method
            if serverPasswordData.toHexString() != clientPassword2.toHexString() {
                Logger.error("Password mismatch during key exchange")
                return false
            }
        }
        
        self.encryptionEnabled = true
        
        return true
    }
    
    
    private func checkPassword(password1: String, password2: String) -> Bool {
        return true
    }
    
    
    
    private func sendCompatibilityCheck() -> Bool {
        let message = P7Message(withName: "p7.compatibility_check.specification", spec: self.spec)
        
        message.addParameter(field: "p7.compatibility_check.specification", value: self.spec.xml!)
        
        _ = self.write(message)
        
        guard let response = self.readMessage() else {
            return false
        }
        
        if response.name != "p7.compatibility_check.status" {
            Logger.error("Message should be 'p7.encryption.server_key', not '\(response.name!)'")
        }
        
        guard let status = response.bool(forField: "p7.compatibility_check.status") else {
            Logger.error("Message has no 'p7.compatibility_check.status' field")
            return false
        }
        
        if status == false {
            Logger.error("Remote protocol '\(self.remoteName!) \(self.remoteVersion!)' is not compatible with local protocol '\(self.spec.protocolName!) \(self.spec.protocolVersion!)'")
        }
        
        return status
    }
    
    
    private func receiveCompatibilityCheck() -> Bool {
        return false
    }
    
    
    
    private func encryptData(_ data: Data) -> Data? {
        do {
            let dataKey = try SwKeyConvert.PublicKey.pemToPKCS1DER(self.publicKey)
            return try CC.RSA.encrypt(data, derKey: dataKey, tag: Data(), padding: .oaep, digest: .sha1)
        } catch  { }
        return nil
    }
    
    
    private func configureCompression() {
        self.compressionEnabled = true
    }
    
    
    private func configureChecksum() {
        self.checksumEnabled = true
    }
}
