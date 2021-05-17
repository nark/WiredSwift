//
//  Socket.swift
//  Wired 3
//
//  Created by Rafael Warnault on 18/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation
import SocketSwift
import CryptoSwift
import Crypto
import SWCompression
import NIO

var sha2_256DigestLength  = 32
var sha3_256DigestLength  = 32
var hmac_256DigestLength  = 32
var poly1305DigestLength  = 16




public enum Serialization:Int {
    case XML            = 0
    case BINARY         = 1
}




public struct Compression:OptionSet, CustomStringConvertible {
    public let rawValue: UInt32
    
    public init(rawValue:UInt32 ) {
        self.rawValue = rawValue
    }
    
    public static let NONE                              = Compression(rawValue: 1 << 0)
    public static let DEFLATE                           = Compression(rawValue: 1 << 1)
    public static let ALL:Compression                   = [.NONE, .DEFLATE]
    public static let COMPRESSION_ONLY:Compression      = [.DEFLATE]
    
    public var description: String {
        switch self {
        case .NONE:
            return "None"
        case .DEFLATE:
            return "DEFLATE"
        default:
            return "None"
        }
    }
}




public struct Checksum:OptionSet, CustomStringConvertible {
    public let rawValue: UInt32
    
    public init(rawValue:UInt32 ) {
        self.rawValue = rawValue
    }
    
    public static let NONE           = Checksum(rawValue: 1 << 0)
    public static let SHA2_256       = Checksum(rawValue: 1 << 1)
    public static let SHA3_256       = Checksum(rawValue: 1 << 2)
    public static let HMAC_256       = Checksum(rawValue: 1 << 3)
    public static let Poly1305       = Checksum(rawValue: 1 << 4)
    
    public static let ALL:Checksum          = [.NONE, .SHA2_256, .SHA3_256, .HMAC_256, .Poly1305]
    public static let SECURE_ONLY:Checksum  = [.SHA2_256, .SHA3_256, .HMAC_256, .Poly1305]
    
    public var description: String {
        switch self {
        case .NONE:
            return "None"
        case .SHA2_256:
            return "SHA2_256"
        case .SHA3_256:
            return "SHA3_256"
        case .HMAC_256:
            return "HMAC_256"
        case .Poly1305:
            return "Poly_1305"
        case .SECURE_ONLY:
            return "SECURE_ONLY"
        case .ALL:
            return "ALL"
        default:
            return "None"
        }
    }
}




public struct CipherType: OptionSet, CustomStringConvertible, Collection {
    public let rawValue: UInt32
    
    public init(rawValue:UInt32 ) {
        self.rawValue = rawValue
    }
    
    public static let NONE                      = CipherType(rawValue: 1 << 0)
    public static let ECDH_AES256_SHA256        = CipherType(rawValue: 1 << 1)
    public static let ECDH_CHACHA20_SHA256      = CipherType(rawValue: 1 << 2)
    
    public static let ALL:CipherType            = [.NONE,
                                                   .ECDH_AES256_SHA256,
                                                   .ECDH_CHACHA20_SHA256]
    public static let SECURE_ONLY:CipherType    = [.ECDH_AES256_SHA256,
                                                   .ECDH_CHACHA20_SHA256]
    
    public var description: String {
        switch self {
        case .NONE:
            return "None"
        case .ECDH_AES256_SHA256:
            return "ECDHE-ECDSA-AES256-SHA256"
        case .ECDH_CHACHA20_SHA256:
            return "ECDHE-ECDSA-ChaCha20-SHA256"
        case .ALL:
            return "ALL"
        case .SECURE_ONLY:
            return "SECURE_ONLY"
        default:
            return "None"
        }
    }
}




public enum Originator {
    case Client
    case Server
}




public struct SocketConfiguration {
    public var spec:P7Spec
    public var originator:Originator
    public var cipher:CipherType
    public var compression:Compression
    public var checksum:Checksum
    public var passwordProvider:SocketPasswordDelegate
    public var channelDelegate:SocketChannelDelegate?
    
    public init(spec: P7Spec, originator: Originator, cipher: CipherType, compression: Compression, checksum: Checksum, passwordProvider: SocketPasswordDelegate, channelDelegate:SocketChannelDelegate) {
        self.spec               = spec
        self.originator         = originator
        self.cipher             = cipher
        self.compression        = compression
        self.checksum           = checksum
        self.passwordProvider   = passwordProvider
        self.channelDelegate    = channelDelegate
    }
}




public protocol SocketChannelDelegate: class {
    func channelReceiveMessage(message:P7Message, socket:P7Socket, channel:Channel)
    func channelConnected(socket:P7Socket, channel:Channel)
    func channelDisconnected(socket:P7Socket, channel:Channel)
    func channelAuthenticated(socket:P7Socket, channel:Channel)
    func channelAuthenticationFailed(socket:P7Socket, channel:Channel)
}







public protocol SocketPasswordDelegate: class {
    func passwordForUsername(username:String, promise: EventLoopPromise<String?>) -> EventLoopFuture<String?>
    func passwordForUsername(username:String) -> String?
}






internal protocol P7SocketMessageHandler: class {
    func handleMessage(message: P7Message, context: ChannelHandlerContext)
}


private protocol P7ClientHandshake: class {

}



private protocol P7ServerHandshake: class {

}





public class P7ServerSocket : P7Socket, P7ClientHandshake {
    private var serverState:ServerState = .client_handshake

    private enum ServerState: Int {
        case client_handshake = 0
        case acknowledge
        case client_key
        case authenticated
    }
    
    
    public override func handleMessage(message: P7Message, context: ChannelHandlerContext) {
        if message.name == "p7.handshake.client_handshake" {
            if self.accept(message: message, compression: self.compression, cipher: self.cipherType, checksum: self.checksum) {
                
            }
        }
    }
    
    
    public func accept(message: P7Message, compression:Compression, cipher:CipherType, checksum:Checksum) -> Bool {
        self.remoteAddress = self.clientAddress()
        
        if !self.acceptHandshake(response: message, timeout: timeout, compression: compression, cipher: cipher, checksum: checksum) {
                return false
        }
            
        if self.compression != .NONE {
            self.configureCompression()
        
            Logger.info("Compression enabled for \(self.compression)")

        }
        
        if self.checksum != .NONE {
            self.configureChecksum()
        
            Logger.info("Checkum enabled for \(self.checksum)")

        }
                
        if self.cipherType != .NONE {
            if !self.acceptKeyExchange(timeout: timeout) {
                return false
            }
        
            Logger.info("Encryption enabled for \(self.cipherType)")
        }
                
        if self.localCompatibilityCheck {
            if !self.receiveCompatibilityCheck() {
                return false
            }
        }

        if self.remoteCompatibilityCheck {
            if !self.sendCompatibilityCheck() {
                return false
            }
        }
        
        return true
    }

    
    
    private func acceptHandshake(response: P7Message, timeout:Int, compression:Compression, cipher:CipherType, checksum:Checksum) -> Bool {
        var clientCipher:CipherType       = .NONE
        var clientChecksum:Checksum       = .NONE
        var clientCompression:Compression = .NONE
        
        self.compression = compression
        self.cipherType = cipher
        self.checksum = checksum
        
        // client handshake message
        if response.name != "p7.handshake.client_handshake" {
            Logger.error("Message should be 'p7.handshake.client_handshake', not '\(response.name!)'")
            return false
        }
        
        // hadshake version
        guard let version = response.string(forField: "p7.handshake.version") else {
            Logger.error("Message has no 'p7.handshake.version', field")
            return false
        }
        
        if version != self.spec.builtinProtocolVersion {
            Logger.error("Remote P7 protocol \(version) is not compatible")

            return false;
        }
        
        
        // protocol compatibility check
        guard let remoteName = response.string(forField: "p7.handshake.protocol.name") else {
            Logger.error("Message has no 'p7.handshake.protocol.name', field")
            return false
        }
        
        guard let remoteVersion = response.string(forField: "p7.handshake.protocol.version") else {
            Logger.error("Message has no 'p7.handshake.protocol.version', field")
            return false
        }
        
        self.remoteName = remoteName
        self.remoteVersion = remoteVersion
        self.localCompatibilityCheck = !self.spec.isCompatibleWithProtocol(withName: self.remoteName, version: self.remoteVersion)
        
        if self.serialization == .BINARY {
            if let compression = response.enumeration(forField: "p7.handshake.compression") {
                clientCompression = Compression(rawValue: compression)
            }
            
            if let encryption = response.enumeration(forField: "p7.handshake.encryption") {
                clientCipher = CipherType(rawValue: encryption)
            }
            
            if let checksum = response.enumeration(forField: "p7.handshake.checksum") {
                clientChecksum = Checksum(rawValue: checksum)
            }
        }
                                
        let message = P7Message(withName: "p7.handshake.server_handshake", spec: self.spec)
        message.addParameter(field: "p7.handshake.version", value: self.spec.builtinProtocolVersion)
        message.addParameter(field: "p7.handshake.protocol.name", value: self.spec.protocolName)
        message.addParameter(field: "p7.handshake.protocol.version", value: self.spec.protocolVersion)
        
        if self.serialization == .BINARY {
            // compression
            if self.compression.contains(clientCompression) {
                self.compression = clientCompression
            } else {
                Logger.error("Compression not supported (\(clientCompression)), fallback to \(self.compressionFallback)")

                self.compression = self.compressionFallback
            }
            
            if self.compression != .NONE {
                message.addParameter(field: "p7.handshake.compression", value: self.compression.rawValue)
            }
                    
            //cipher
            if self.cipherType.contains(clientCipher) {
                self.cipherType = clientCipher
            } else {
                Logger.error("Encryption cipher not supported (\(clientCipher)), fallback to \(self.cipherTypeFallback)")

                self.cipherType = self.cipherTypeFallback
            }
            
            if self.cipherType != .NONE {
                message.addParameter(field: "p7.handshake.encryption", value: self.cipherType.rawValue)
            }
            
            // checksum
            if self.checksum.contains(clientChecksum) {
                self.checksum = clientChecksum
            } else {
                Logger.error("Checksum not supported (\(clientChecksum)), fallback to \(self.checksumFallback)")
                self.checksum = self.checksumFallback
            }
                            
            if self.checksum != .NONE {
                message.addParameter(field: "p7.handshake.checksum", value: self.checksum.rawValue)
            }
        }
                        
        if self.localCompatibilityCheck {
            message.addParameter(field: "p7.handshake.compatibility_check", value: true)
        }
        
        print("acceptHandshake")
                        
        guard let acknowledge = self.send(message) else {
            print("NOOOO acknowledge")
            return false
        }
        
        print("acknowledge \(acknowledge)")
                
        if acknowledge.name != "p7.handshake.acknowledge" {
            Logger.error("Message should be 'p7.handshake.acknowledge', not '\(response.name!)'")
            return false
        }
        
        if let remoteCompatibilityCheck = acknowledge.bool(forField: "p7.handshake.compatibility_check") {
            self.remoteCompatibilityCheck = remoteCompatibilityCheck
        } else {
            self.remoteCompatibilityCheck = false
        }
        
        return true
    }
    
    
    
    
    private func acceptKeyExchange(timeout: Int) -> Bool {
        // send the server public key
        let message = P7Message(withName: "p7.encryption.server_key", spec: self.spec)
        
        self.ecdh = ECDH()
        
        if self.ecdh == nil {
            Logger.error("Missing ECDH key")
            return false
        }
        
        guard let serverPublicKey = self.ecdh.publicKeyData() else {
            return false
        }

        message.addParameter(field: "p7.encryption.public_key", value: serverPublicKey)

        // read the client public key
        guard let response = self.send(message) else {
            return false
        }
        
        if response.name != "p7.encryption.client_key" {
            Logger.error("Message should be 'p7.encryption.client_key', not '\(response.name!)'")
            return false
        }
        
        guard   let combinedBase64Keys = response.data(forField: "p7.encryption.cipher.key"),
                let combinedKeys = Data(base64Encoded: combinedBase64Keys) else {
            Logger.error("Client public key not found")
            return false
        }
        
        let clientPublicKey = combinedKeys.dropLast(64)
        
        if clientPublicKey.count != 132 {
            Logger.error("Invalid public key")
            return false
        }
        
        let publicSigningKey = combinedKeys.dropFirst(132)

        if publicSigningKey.count != 64 {
            Logger.error("Invalid signing key")
            return false
        }
        
        guard let serverSharedSecret = self.ecdh.computeSecret(withPublicKey: clientPublicKey) else {
            Logger.error("Cannot compute shared secret")
            return false
        }
                
        guard   let saltData = serverSharedSecret.data(using: .utf8),
                let (derivedKey, derivedIV) = self.ecdh.derivedKey(withSalt: saltData,
                                                                   andIVofLength: Cipher.IVlength(forCipher: self.cipherType)) else {
            Logger.error("Cannot derive key from shared secret")
            return false
        }
        
        self.sslCipher  = Cipher(cipher: self.cipherType, key: derivedKey.hexEncodedString(), iv: derivedIV)
        self.digest     = Digest(key: derivedKey.hexEncodedString(), type: self.checksum)
        
        if self.sslCipher == nil {
            Logger.error("Cannot init cipher (\(self.cipherType)")
            return false
        }

        guard   let dd = response.data(forField: "p7.encryption.username"),
                let data = self.sslCipher.decrypt(data: dd) else {
            Logger.error("Message has no 'p7.encryption.username' field")
            return false
        }
        
        guard let username = data.stringUTF8 else {
            Logger.error("Message has no 'p7.encryption.username' field")
            return false
        }

        self.username = username

        guard let client_password = response.data(forField: "p7.encryption.client_password") else {
            Logger.error("Message has no 'p7.encryption.client_password' field")
            return false
        }

        if self.passwordProvider != nil {
            guard let password = self.passwordProvider?.passwordForUsername(username: self.username) else {
                Logger.error("No user found with username '\(self.username)', abort")
                return false
            }
            
            self.password = password
        } else {
            // assume password is empty (guest with empty password access only)
            self.password = "".sha256()
        }

        let passwordData = self.password.data(using: .utf8)!
        var serverPassword1Data = passwordData
        serverPassword1Data.append(serverPublicKey)
        serverPassword1Data = serverPassword1Data.sha256().toHexString().data(using: .utf8)!

        var serverPassword2Data = serverPublicKey
        serverPassword2Data.append(passwordData)
        serverPassword2Data = serverPassword2Data.sha256().toHexString().data(using: .utf8)!
        
        guard let ecdsa = ECDSA(publicKey: publicSigningKey) else {
            Logger.error("Cannot init ECDSA with public signing key")
            return false
        }
        
        if !ecdsa.verify(data: serverPassword1Data, withSignature: client_password) {
            Logger.error("Password mismatch for '\(self.username)' during key exchange, ECDSA validation failed")
            return false
        }

        // acknowledge
        let message2 = P7Message(withName: "p7.encryption.acknowledge", spec: self.spec)
        
        guard let ecdsa2 = ECDSA(privateKey: derivedKey) else {
            Logger.error("Cannot init ECDSA with private signing key")
            return false
        }
        
        guard let passwordSignature = ecdsa2.sign(data: serverPassword2Data) else {
            Logger.error("Cannot sign server password")
            return false
        }

        message2.addParameter(field: "p7.encryption.server_password", value: passwordSignature)

        if !self.write(message2) {
            return false
        }
                
        guard let (derivedKey2, derivedIV2) = self.ecdh.derivedKey(withSalt: serverPassword2Data,
                                                                        andIVofLength: Cipher.IVlength(forCipher: self.cipherType)) else {
            Logger.error("Cannot derive key from server password")
            return false
        }

        self.digest     = Digest(key: derivedKey2.hexEncodedString(), type: self.checksum)
        self.sslCipher  = Cipher(cipher: self.cipherType, key: derivedKey2.hexEncodedString(), iv: derivedIV2)

        if self.digest == nil {
            Logger.error("Digest cannot be created")
            return false
        }
        
        if self.sslCipher == nil {
            Logger.error("Cipher cannot be created")
            return false
        }

        self.checksumEnabled    = true
        self.encryptionEnabled  = true

        return true
    }
}









public class P7ClientSocket : P7Socket, P7ServerHandshake {
    private var clientState:ClientState = .server_handshake
    
    private enum ClientState: Int {
        case server_handshake = 0
        case server_key
        case acknowledge
        case authenticated
    }
    
    
    public func connect(withHandshake handshake: Bool = true) -> Bool {
        self.connected = true

        if handshake {
            guard let reply = self.connectHandshake() else {
                Logger.error("Handshake failed")
                
                self.errors.append(WiredError(withTitle: "Connection Error", message: "Handshake failed"))
                
                return false
            }

            if self.compression != .NONE {
                self.configureCompression()
            
                Logger.info("Compression enabled for \(self.compression)")
            }
                            
            if self.checksum != .NONE {
                self.configureChecksum()
                
                Logger.info("Checkum enabled for \(self.checksum)")
            }

            if self.cipherType != .NONE {
                guard let reply2 = self.connectKeyExchange(response: reply) else {
                    Logger.error("Key Exchange failed")
                    
                    self.errors.append(WiredError(withTitle: "Connection Error", message: "Authentication failed"))
                    
                    return false
                }
                
                Logger.info("Encryption enabled for \(self.cipherType)")
            }
            
            if self.remoteCompatibilityCheck {
                if !self.sendCompatibilityCheck() {
                    Logger.error("Remote Compatibility Check failed")
                    
                    self.errors.append(WiredError(withTitle: "Connection Error", message: "Remote Compatibility Check failed"))
                    
                    return false
                }
            }
            
            if self.localCompatibilityCheck {
                if !self.receiveCompatibilityCheck() {
                    Logger.error("Local Compatibility Check failed")
                    
                    self.errors.append(WiredError(withTitle: "Connection Error", message: "Local Compatibility Check failed"))
                    
                    return false
                }
            }
        }

        return true
    }
    
    
    
    private func connectHandshake() -> P7Message? {
        var serverCipher:CipherType?       = nil
        var serverChecksum:Checksum?       = nil
        var serverCompression:Compression? = nil
        
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
            
            if self.checksum != .NONE {
                message.addParameter(field: "p7.handshake.checksum", value: self.checksum.rawValue)
            }
        }
                                        
        guard let response = self.send(message) else {
            Logger.error("Handshake Failed: Should Receive Message: p7.handshake.server_handshake")
            return nil
        }
                
        if response.name != "p7.handshake.server_handshake" {
            Logger.error("Handshake Failed: Unexpected message \(response.name!) instead of p7.handshake.server_handshake")
        }
        
        guard let p7Version = response.string(forField: "p7.handshake.version") else {
            Logger.error("Handshake Failed: Built-in protocol version field is missing (p7.handshake.version)")
            return nil
        }
        
        if p7Version != spec.builtinProtocolVersion {
            Logger.error("Handshake Failed: Local version is \(p7Version) but remote version is \(spec.builtinProtocolVersion!)")
            return nil
        }
        
        self.remoteName = response.string(forField: "p7.handshake.protocol.name")
        self.remoteVersion = response.string(forField: "p7.handshake.protocol.version")

        self.localCompatibilityCheck = !spec.isCompatibleWithProtocol(withName: self.remoteName, version: self.remoteVersion)
                
        if self.serialization == .BINARY {
            if let comp = response.enumeration(forField: "p7.handshake.compression") {
                serverCompression = Compression(rawValue: comp)
            } else {
                serverCompression = .NONE
            }
            
            if let cip = response.enumeration(forField: "p7.handshake.encryption") {
                serverCipher = CipherType(rawValue: cip)
            } else {
                serverCipher = .NONE
            }
            
            if let chs = response.enumeration(forField: "p7.handshake.checksum") {
                serverChecksum = Checksum(rawValue: chs)
            } else {
                serverChecksum = .NONE
            }
            
            if serverCompression != self.compression {
                return nil
            }
            
            if serverCipher != self.cipherType {
                return nil
            }
            
            if serverChecksum != self.checksum {
                return nil
            }
        }
                                
        if let bool = response.bool(forField: "p7.handshake.compatibility_check") {
            self.remoteCompatibilityCheck = bool
        }
        
        message = P7Message(withName: "p7.handshake.acknowledge", spec: self.spec)
        
        if self.localCompatibilityCheck {
            message.addParameter(field: "p7.handshake.compatibility_check", value: true)
        }
                        
        return self.send(message)
    }
    
    
    
    private func connectKeyExchange(response: P7Message) -> P7Message?  {
        self.ecdh = ECDH()
        
        if self.ecdh == nil {
            Logger.error("ECDH Public key cannot be created")
            return nil
        }
        
        if response.name != "p7.encryption.server_key" {
            Logger.error("Message should be 'p7.encryption.server_key', not '\(response.name!)'")
        }
        
        guard let serverPublicKey = response.data(forField: "p7.encryption.public_key") else {
            Logger.error("Message has no 'p7.encryption.public_key' field")
            return nil
        }
        
        guard let serverSharedSecret = self.ecdh.computeSecret(withPublicKey: serverPublicKey) else {
            Logger.error("Cannot compute shared secret")
            return nil
        }
                
        guard   let saltData = serverSharedSecret.data(using: .utf8),
                let (derivedKey, derivedIV) = self.ecdh.derivedKey(withSalt: saltData, andIVofLength: Cipher.IVlength(forCipher: self.cipherType)) else {
            Logger.error("Cannot derive key from shared secret")
            return nil
        }
                
        self.sslCipher  = Cipher(cipher: self.cipherType, key: derivedKey.hexEncodedString(), iv: derivedIV)
        self.digest     = Digest(key: derivedKey.hexEncodedString(), type: self.checksum)
        
        if self.sslCipher == nil {
            Logger.error("Cipher cannot be created")
            return nil
        }
        
        if self.digest == nil {
            Logger.error("Digest cannot be created")
            return nil
        }

        if self.password == nil || self.password == "" {
            self.password = "".sha256()
        } else {
            self.password = self.password.sha256()
        }

        let passwordData = self.password.data(using: .utf8)!

        var clientPassword1 = passwordData
        clientPassword1.append(serverPublicKey)
        clientPassword1 = clientPassword1.sha256().toHexString().data(using: .utf8)!

        var clientPassword2 = serverPublicKey
        clientPassword2.append(passwordData)
        clientPassword2 = clientPassword2.sha256().toHexString().data(using: .utf8)!

        let message = P7Message(withName: "p7.encryption.client_key", spec: self.spec)

        guard var clientPublicKey = self.ecdh.publicKeyData() else {
            Logger.error("Cannot read client public key")
            return nil
        }
        
        guard let d = self.username.data(using: .utf8), let encryptedUsername = self.sslCipher.encrypt(data: d)  else {
            Logger.error("Cannot encrypt username")
            return nil
        }

        guard let ecdsa = ECDSA(privateKey: derivedKey) else {
            Logger.error("Cannot ini ECDSA")
            return nil
        }
        
        guard let passwordSignature = ecdsa.sign(data: clientPassword1) else {
            Logger.error("Cannot read client password")
            return nil
        }
        
        clientPublicKey.append(ecdsa.publicKey.rawRepresentation)
                    
        message.addParameter(field: "p7.encryption.cipher.key", value: clientPublicKey.base64EncodedData())
        message.addParameter(field: "p7.encryption.username", value: encryptedUsername)
        message.addParameter(field: "p7.encryption.client_password", value: passwordSignature)
        
        guard let response2 = self.send(message) else {
            Logger.error("Cannot read p7.encryption.acknowledge message")
            return nil
        }

        if response2.name == "p7.encryption.authentication_error" {
            Logger.error("Authentification failed for '\(self.username)'")
            return nil
        }

        if response2.name != "p7.encryption.acknowledge" {
            Logger.error("Message should be 'p7.encryption.acknowledge', not '\(response2.name!)'")
            return nil
        }

        guard let encryptedServerPasswordData = response2.data(forField: "p7.encryption.server_password") else {
            Logger.error("Message has no 'p7.encryption.server_password' field")
            return nil
        }
        
        if !ecdsa.verify(data: clientPassword2, withSignature: encryptedServerPasswordData) {
            Logger.error("Password mismatch for '\(self.username)' during key exchange, ECDSA validation failed")
            return nil
        }

        guard let (derivedKey2, derivedIV2) = self.ecdh.derivedKey(withSalt: clientPassword2,
                                                                        andIVofLength: Cipher.IVlength(forCipher: self.cipherType)) else {
            Logger.error("Cannot derive key from server password")
            return nil
                                                                            
        }

        self.digest     = Digest(key: derivedKey2.hexEncodedString(), type: self.checksum)
        self.sslCipher  = Cipher(cipher: self.cipherType, key: derivedKey2.hexEncodedString(), iv: derivedIV2)
        
        if self.digest == nil {
            Logger.error("Digest cannot be created")
            return nil
        }

        if self.sslCipher == nil {
            Logger.error("Cipher cannot be created")
            return nil
        }

        self.checksumEnabled = true
        self.encryptionEnabled = true

        return response2
    }
    
    
    public override func handleMessage(message: P7Message, context: ChannelHandlerContext) {
        if self.originator == .Client {
            self.handleServerMessage(message, context: context)
        }
    }
    
    fileprivate func handleServerMessage(_ message: P7Message, context: ChannelHandlerContext) {
//        switch self.clientState {
//        case .server_handshake:
//            if message.name == "p7.handshake.server_handshake" {
//                if !self.handleServerHandshake(message, channel: context.channel) {
//                    self.close(context: context)
//                }
//
//                if self.compression != .NONE {
//                    self.configureCompression()
//
//                    Logger.info("Compression enabled for \(self.compression)")
//                }
//
//                if self.checksum != .NONE {
//                    self.configureChecksum()
//
//                    Logger.info("Checkum enabled for \(self.checksum)")
//                }
//
//                self.clientState = .server_key
//            }
//        case .server_key:
//            if message.name == "p7.encryption.server_key" {
//                if !self.handleServerKey(message, channel: context.channel) {
//                    self.close(context: context)
//                }
//
//                self.clientState = .acknowledge
//            }
//        case .acknowledge:
//            if message.name == "p7.encryption.acknowledge" {
//                if !self.handleServerEncryptionAcknowledge(message, channel: context.channel) {
//                    self.close(context: context)
//                }
//
//                if self.remoteCompatibilityCheck {
//                    if !self.sendCompatibilityCheck() {
//                        Logger.error("Remote Compatibility Check failed")
//
//                        self.errors.append(WiredError(withTitle: "Connection Error", message: "Remote Compatibility Check failed"))
//
//                        self.close(context: context)
//                    }
//                }
//
//                if self.localCompatibilityCheck {
//                    if !self.receiveCompatibilityCheck() {
//                        Logger.error("Local Compatibility Check failed")
//
//                        self.errors.append(WiredError(withTitle: "Connection Error", message: "Local Compatibility Check failed"))
//
//                        self.close(context: context)
//                    }
//                }
//
//                self.clientState = .authenticated
//            }
//        default:
//            if message.name == "p7.encryption.authentication_error" {
//                Logger.error("Authentification failed for '\(self.username)'")
//
//                self.errors.append(WiredError(withTitle: "Authentification Error", message: "Authentication failed, message out of sequence"))
//
//                self.close(context: context)
//
//                return
//            }
//
//            if self.clientState != .authenticated {
//                Logger.error("Authentication failed, message out of sequence")
//
//                self.errors.append(WiredError(withTitle: "Connection Error", message: "Authentication failed, message out of sequence"))
//
//                self.close(context: context)
//
//                return
//            }
//
//            channelDelegate?.channelReceiveMessage(message: message, socket: self, channel: context.channel)
//        }
    }
    
    
    
    fileprivate func handleServerEncryptionAcknowledge(_ message: P7Message, channel: Channel) -> Bool {
        let passwordData = self.password.data(using: .utf8)!
        
        var clientPassword1 = passwordData
        clientPassword1.append(serverPublicKey)
        clientPassword1 = clientPassword1.sha256().toHexString().data(using: .utf8)!

        var clientPassword2 = Data(serverPublicKey)
        clientPassword2.append(passwordData)
        clientPassword2 = clientPassword2.sha256().toHexString().data(using: .utf8)!
        
        guard let encryptedServerPasswordData = message.data(forField: "p7.encryption.server_password") else {
            Logger.error("Message has no 'p7.encryption.server_password' field")
            return false
        }

        guard let ecdsa = ECDSA(privateKey: derivedKey) else {
            Logger.error("Cannot init ECDSA")
            return false
        }

        self.ecdsa = ecdsa
        
        if !ecdsa.verify(data: clientPassword2, withSignature: encryptedServerPasswordData) {
            Logger.error("Password mismatch for '\(self.username)' during key exchange, ECDSA validation failed")
            return false
        }

        guard let (derivedKey2, derivedIV2) = self.ecdh.derivedKey(withSalt: clientPassword2,
                                                                        andIVofLength: Cipher.IVlength(forCipher: self.cipherType)) else {
            Logger.error("Cannot derive key from server password")
            return false
                                                                            
        }

        self.digest     = Digest(key: derivedKey2.hexEncodedString(), type: self.checksum)
        self.sslCipher  = Cipher(cipher: self.cipherType, key: derivedKey2.hexEncodedString(), iv: derivedIV2)
        
        if self.digest == nil {
            Logger.error("Digest cannot be created")
            return false
        }

        if self.sslCipher == nil {
            Logger.error("Cipher cannot be created")
            return false
        }

        self.checksumEnabled = true
        self.encryptionEnabled = true
        
        self.handshakePromise.succeed(channel)
        
        return true
    }

    
    fileprivate func handleServerKey(_ message: P7Message, channel: Channel) -> Bool {
        self.ecdh = ECDH()
        
        guard let serverPublicKey = message.data(forField: "p7.encryption.public_key") else {
            Logger.error("Message has no 'p7.encryption.public_key' field")
            return false
        }
        
        self.serverPublicKey = serverPublicKey
        
        guard let serverSharedSecret = self.ecdh.computeSecret(withPublicKey: serverPublicKey) else {
            Logger.error("Cannot compute shared secret")
            return false
        }
                        
        guard   let saltData = serverSharedSecret.data(using: .utf8),
                let (derivedKey, derivedIV) = self.ecdh.derivedKey(withSalt: saltData, andIVofLength: Cipher.IVlength(forCipher: self.cipherType)) else {
            Logger.error("Cannot derive key from shared secret")
            return false
        }
                
        self.derivedKey = derivedKey
        self.sslCipher  = Cipher(cipher: self.cipherType, key: derivedKey.hexEncodedString(), iv: derivedIV)
        self.digest     = Digest(key: derivedKey.hexEncodedString(), type: self.checksum)
        
        if self.sslCipher == nil {
            Logger.error("Cipher cannot be created")
            return false
        }
        
        if self.digest == nil {
            Logger.error("Digest cannot be created")
            return false
        }

        if self.password == nil || self.password == "" {
            self.password = "".sha256()
        } else {
            self.password = self.password.sha256()
        }

        let passwordData = self.password.data(using: .utf8)!

        var clientPassword1 = passwordData
        clientPassword1.append(serverPublicKey)
        clientPassword1 = clientPassword1.sha256().toHexString().data(using: .utf8)!

        var clientPassword2 = serverPublicKey
        clientPassword2.append(passwordData)
        clientPassword2 = clientPassword2.sha256().toHexString().data(using: .utf8)!

        let message = P7Message(withName: "p7.encryption.client_key", spec: self.spec)

        guard var clientPublicKey = self.ecdh.publicKeyData() else {
            Logger.error("Cannot read client public key")
            return false
        }
        
        guard let d = self.username.data(using: .utf8), let encryptedUsername = self.sslCipher.encrypt(data: d)  else {
            Logger.error("Cannot encrypt username")
            return false
        }

        guard let ecdsa = ECDSA(privateKey: derivedKey) else {
            Logger.error("Cannot ini ECDSA")
            return false
        }
        
        self.ecdsa = ecdsa
        
        guard let passwordSignature = ecdsa.sign(data: clientPassword1) else {
            Logger.error("Cannot read client password")
            return false
        }
        
        clientPublicKey.append(ecdsa.publicKey.rawRepresentation)
                    
        message.addParameter(field: "p7.encryption.cipher.key", value: clientPublicKey.base64EncodedData())
        message.addParameter(field: "p7.encryption.username", value: encryptedUsername)
        message.addParameter(field: "p7.encryption.client_password", value: passwordSignature)
        
        return self.write(message, channel: channel)
    }
    
    
    
    
    fileprivate func handleServerHandshake(_ message: P7Message, channel: Channel) -> Bool {
        var serverCipher:CipherType?       = nil
        var serverChecksum:Checksum?       = nil
        var serverCompression:Compression? = nil
        
        guard let p7Version = message.string(forField: "p7.handshake.version") else {
            Logger.error("Handshake Failed: Built-in protocol version field is missing (p7.handshake.version)")
            return false
        }
        
        if p7Version != spec.builtinProtocolVersion {
            Logger.error("Handshake Failed: Local version is \(p7Version) but remote version is \(spec.builtinProtocolVersion!)")
            return false
        }
        
        self.remoteName = message.string(forField: "p7.handshake.protocol.name")
        self.remoteVersion = message.string(forField: "p7.handshake.protocol.version")

        self.localCompatibilityCheck = !spec.isCompatibleWithProtocol(withName: self.remoteName, version: self.remoteVersion)
                
        if self.serialization == .BINARY {
            if let comp = message.enumeration(forField: "p7.handshake.compression") {
                serverCompression = Compression(rawValue: comp)
            } else {
                serverCompression = .NONE
            }
            
            if let cip = message.enumeration(forField: "p7.handshake.encryption") {
                serverCipher = CipherType(rawValue: cip)
            } else {
                serverCipher = .NONE
            }
            
            if let chs = message.enumeration(forField: "p7.handshake.checksum") {
                serverChecksum = Checksum(rawValue: chs)
            } else {
                serverChecksum = .NONE
            }
            
            if serverCompression != self.compression {
                return false
            }
            
            if serverCipher != self.cipherType {
                return false
            }
            
            if serverChecksum != self.checksum {
                return false
            }
        }
                                
        if let bool = message.bool(forField: "p7.handshake.compatibility_check") {
            self.remoteCompatibilityCheck = bool
        }
        
        let response = P7Message(withName: "p7.handshake.acknowledge", spec: self.spec)
        
        if self.localCompatibilityCheck {
            response.addParameter(field: "p7.handshake.compatibility_check", value: true)
        }
        
        return self.write(response, channel: channel)
    }    
}


public class P7Socket: ChannelInboundHandler, P7SocketMessageHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    
    public var hostname: String!
    public var port: Int!
    public var spec: P7Spec!
    public var username: String = "guest"
    public var password: String!
    public var serialization: Serialization = .BINARY
    
    public var compression: Compression = .NONE
    public var cipherType: CipherType = .NONE
    public var checksum: Checksum = .NONE
    
    // if no consensus is found during the handshake
    // the server fallback to the following encryption settings
    public var compressionFallback: Compression = .DEFLATE
    public var cipherTypeFallback: CipherType = .ECDH_AES256_SHA256
    public var checksumFallback: Checksum = .SHA2_256
    
    public var sslCipher: Cipher!
    public var timeout: Int = 10
    public var errors: [WiredError] = []
    
    public var compressionEnabled: Bool = false
    public var compressionConfigured: Bool = false
    
    public var encryptionEnabled: Bool = false
    public var checksumEnabled: Bool = false
    public var checksumLength: Int = 0
    
    public var localCompatibilityCheck: Bool = false
    public var remoteCompatibilityCheck: Bool = false
    
    public var remoteVersion: String!
    public var remoteName: String!
    public var remoteAddress:String?
    
    public var connected: Bool = false
    public var passwordProvider:SocketPasswordDelegate?
    public var channelDelegate:SocketChannelDelegate?
    
    // All access to channels is guarded by channelsSyncQueue.
    private let channelsSyncQueue = DispatchQueue(label: "channelsQueue")
    private var channels: [ObjectIdentifier: Channel] = [:]
    public var channel:Channel!
    
    public var lastMessage:P7Message!
    
    public  var ecdh:ECDH!
    internal var ecdsa:ECDSA!
    internal var digest:Digest!
    internal var serverPublicKey:Data!
    internal var derivedKey:Data!
    internal var handshakePromise:EventLoopPromise<Channel>!
    internal var interactive:Bool = true
    internal var originator:Originator
    
    internal var transactionHandler:P7TransactionHandler? = nil
    
    public init(spec: P7Spec, originator:Originator) {
        self.spec               = spec
        self.originator         = originator
        self.connected          = true
        
        self.transactionHandler = P7TransactionHandler(socket: self)
    }
    
    
    
    
    public init(_ configuration:SocketConfiguration) {
        self.spec               = configuration.spec
        self.originator         = configuration.originator
        
        self.cipherType         = configuration.cipher
        self.compression        = configuration.compression
        self.checksum           = configuration.checksum
        
        self.passwordProvider   = configuration.passwordProvider
        self.channelDelegate    = configuration.channelDelegate
        
        self.transactionHandler = P7TransactionHandler(socket: self)
        
        self.connected          = true
    }
    
    
    
    
    
    
    
    
    // MARK: -
    
    public func channelActive(context: ChannelHandlerContext) {
        self.channel = context.channel
        
        self.channelDelegate?.channelConnected(socket: self, channel: context.channel)
    }
    
    
    public func channelInactive(context: ChannelHandlerContext) {
        self.channelDelegate?.channelDisconnected(socket: self, channel: context.channel)
    }
    
    


    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if self.interactive == true {
            self.readMessage(context: context, data: data)
        } else {
            self.readTransfer(context: context, data: data)
        }
    }
    
    
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)

        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        context.close(promise: nil)
    }




    
    
    
    
    // MARK: -
    public func handleMessage(message: P7Message, context: ChannelHandlerContext) {
        
    }
    
    
    
    
    // MARK: - CONNECTION

    
    public func disconnect() {
        //self.channel.close()
        
        self.connected = false
        
        self.compressionEnabled = false
        self.compressionConfigured = false
        
        self.encryptionEnabled = false
        self.checksumEnabled = false
        self.checksumLength = 0

        self.localCompatibilityCheck = false
        self.remoteCompatibilityCheck = false
        
        self.ecdh = nil
    }
    
    
    public func clientAddress() -> String? {
        return channel?.remoteAddress?.description
    }
    
    
    
    public func isInteractive() -> Bool {
        return self.interactive
    }
    
    
    public func set(interactive:Bool) {
        let option = interactive ? 1 : 0

        self.channel.setOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: ChannelOptions.Types.SocketOption.Value(option)).whenSuccess { (Void) in
            self.interactive = interactive
        }
    }
    
    internal func close(context: ChannelHandlerContext) {
        DispatchQueue.main.async {
            try? context.close().wait()
        }
    }
    
    
    
    
    
    // MARK: - SEND MESSAGES
    public func reply(reply: P7Message, message: P7Message, channel: Channel? = nil) -> P7Message? {
        if let transactionID = message.uint32(forField: "wired.transaction") {
            reply.addParameter(field: "wired.transaction", value: transactionID)
        }
        
        return self.send(reply, channel: channel)
    }
    
    
    public func send(_ message: P7Message, channel: Channel? = nil) -> P7Message? {
        return self.transactionHandler?.send(message: message, channel: channel == nil ? self.channel : channel!)
    }
    
    
    

    
    // MARK: - PRIVATE WRITE
    public func write(_ message: P7Message) -> Bool {
        return self.write(message, channel: self.channel)
    }
    
    
    
    
    public func write(_ message: P7Message, channel: Channel, promise: EventLoopPromise<Void>? = nil) -> Bool {
            if self.serialization == .XML {
                // TODO: reanable XML serialization for testing purpose
            }
            else if self.serialization == .BINARY {
                var lengthData = Data()
                var messageData = message.bin()
                
                lengthData.append(uint32: UInt32(messageData.count))
                
                let t = message.uint32(forField: "wired.transaction")
                
                // deflate
                if self.compressionEnabled {
                    guard let deflatedMessageData = self.deflate(messageData) else {
                        Logger.error("Cannot deflate data")
                        return false
                        
                    }
                    messageData = deflatedMessageData
                    
                    lengthData = Data()
                    lengthData.append(uint32: UInt32(messageData.count))
                }
                                
                // encryption
                if self.encryptionEnabled {
                    guard let encryptedMessageData = self.sslCipher.encrypt(data: messageData) else {
                        Logger.error("Cannot encrypt data")
                        return false
                    }
                    
                    messageData = encryptedMessageData
                    
                    lengthData = Data()
                    lengthData.append(uint32: UInt32(messageData.count))
                }
                                
                let buffer = channel.allocator.buffer(data: lengthData + messageData)
                channel.write(buffer, promise: promise)
                
                // checksum
                if self.checksumEnabled {
                    if let c = self.checksumData(messageData) {
                        let buffer = channel.allocator.buffer(data: c)
                        channel.write(buffer, promise: promise)
                    } else {
                        Logger.error("Checksum failed abnormally")
                    }
                }
                
                channel.flush()
                
                Logger.info("-> WRITE: \(message.name!) [\(messageData.count)] [encryption: \(self.encryptionEnabled)] [compression: \(self.compressionEnabled)] [checksum: \(self.checksumEnabled)] [transaction: \(t)]")
                //Logger.debug("\n\(message)\n")
            }
        
        return true
    }
    
    
    
    
    
    
    // MARK: - PRIVATE READ/WRITE
    private func write(_ data: Array<UInt8>, maxLength len: Int, timeout:TimeInterval = 1.0) -> Int {
//        while let available = try? socket.wait(for: .write, timeout: timeout), self.connected == true {
//            guard available else { continue } // timeout happend, try again
//
//            let n = try? socket.write(buffer, size: len)
//
//            return n ?? 0
//        }
//
        return 0
    }
    
    
    
    private func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int, timeout:TimeInterval = 1.0) -> Int {

//        while let available = try? socket.wait(for: .read, timeout: timeout), self.connected == true {
//            guard available else { continue } // timeout happend, try again
//
//            let n = try? socket.read(buffer, size: len)
//
//            return n ?? 0
//        }
//
//        return 0
        
        return 0
    }
    
    
    // I have pretty much had to rewrite my own read() function here
    private func readData(size: Int, timeout:TimeInterval = 1.0) throws -> Data {
//        while let available = try? socket.wait(for: .read, timeout: timeout), self.connected == true {
//            guard available else { continue } // timeout happend, try again
//
//            var data = Data()
//            var readBytes = 0
//            var nLength = size
//
//            while readBytes < size && nLength > 0 && self.connected == true {
//                var messageBuffer = [Byte](repeating: 0, count: nLength)
//
//                readBytes += try ing { recv(socket.fileDescriptor, &messageBuffer, nLength, Int32(MSG_WAITALL)) }
//                nLength    = size - readBytes
//
//                //print("readBytes : \(readBytes)")
//                //print("nLength : \(nLength)")
//
//                let subdata = Data(bytes: messageBuffer, count: readBytes)
//                if subdata.count > nLength {
//                    _ = subdata.dropLast(nLength)
//                }
//
//                //print("subdata : \(subdata.toHex())")
//
//                data.append(subdata)
//            }
//
//            return data
//        }
//
//        return Data()
        
        return Data()
    }
    
    
    // MARK: - OOB DATA
    public func readOOB(timeout:TimeInterval = 1.0) -> Data? {
        var messageData = Data()
        var lengthBuffer = [Byte](repeating: 0, count: 4)
        let bytesRead = self.read(&lengthBuffer, maxLength: 4, timeout: timeout)
        
        if bytesRead >= 4 {
            guard let messageLength = Data(lengthBuffer).uint32 else {
                Logger.error("Cannot read message length")
                return nil
            }
            
            messageData = try! self.readData(size: Int(messageLength))
            
            // data to message object
            if messageData.count > 0 {
                // decryption
                if self.encryptionEnabled {
                    guard let decryptedMessageData = self.sslCipher.decrypt(data: messageData) else {
                        Logger.error("Cannot decrypt data")
                        return messageData
                    }
                    messageData = decryptedMessageData
                }

                // inflate
                if self.compressionEnabled {
                    guard let inflatedMessageData = self.inflate(messageData) else {
                        Logger.error("Cannot inflate data")
                        return nil

                    }
                    messageData = inflatedMessageData
                }

                // checksum
                if self.checksumEnabled {
                    do {
                        let remoteChecksum = try self.readData(size: self.checksumLength)
                        if remoteChecksum.count == 0 { return nil }

                        if let c = self.checksumData(messageData) {
                            if !c.elementsEqual(remoteChecksum) {
                                Logger.fatal("Checksum failed")
                                return nil
                            }
                        } else {
                           Logger.error("Checksum failed abnormally")
                       }
                    } catch let e {
                        Logger.error("Checksum error: \(e)")
                    }
                }
                
                return messageData
            }
        }
        else {
            Logger.error("Nothing read, abort")
        }
        
        return messageData
    }
    
    
    
    public func writeOOB(data:Data, timeout:TimeInterval = 1.0) -> Bool {
        if self.serialization == .BINARY {
            var messageData = data
            let originalData = messageData
            var lengthData = Data()
            
            lengthData.append(uint32: UInt32(messageData.count))
                                            
            // deflate
            if self.compressionEnabled {
                guard let deflatedMessageData = self.deflate(messageData) else {
                    Logger.error("Cannot deflate data")
                    return false

                }
                messageData = deflatedMessageData
            }

            // encryption
            if self.encryptionEnabled {
                guard let encryptedMessageData = self.sslCipher.encrypt(data: messageData) else {
                    Logger.error("Cannot encrypt data")
                    return false
                }

                messageData = encryptedMessageData

                lengthData = Data()
                lengthData.append(uint32: UInt32(messageData.count))
            }
            

            let buffer = channel.allocator.buffer(data: lengthData + messageData)
            channel.write(buffer, promise: nil)
            
            // checksum
            // checksum
            if self.checksumEnabled {
                if let c = self.checksumData(messageData) {
                    let buffer = channel.allocator.buffer(data: c)
                    channel.write(buffer, promise: nil)
                } else {
                    Logger.error("Checksum failed abnormally")
                }
            }
            
            channel.flush()
        }
    
        return true
    }

    
    

    
    
    // MARK: - CHECKSUM
    public func checksumData(_ data:Data) -> Data? {
        if self.digest != nil  {
            return self.digest.authenticate(data: data)
        }
        return nil
    }

}







internal extension P7Socket {
    // MARK: - READ HELPERS
    private func readMessage(context: ChannelHandlerContext, data: NIOAny) {
        var error:WiredError? = nil
        
        var buffer = self.unwrapInboundIn(data)
        
        let messageLength = buffer.readableBytes - (self.checksumEnabled ? self.checksumLength : 0)
        
        guard var messageData: Data = buffer.readData(length: messageLength) else {
            return
        }
                
        let originalData = messageData
        
        // decryption
        if self.encryptionEnabled {
            guard let decryptedMessageData = self.sslCipher.decrypt(data: messageData) else {
                error = WiredError(withTitle: "Read Error", message: "Cannot decrypt data")

                Logger.error(error!)
                self.errors.append(error!)

                self.close(context: context)
                return
            }
            messageData = decryptedMessageData
        }

        // inflate
        if self.compressionEnabled {
            guard let inflatedMessageData = self.inflate(messageData) else {
                error = WiredError(withTitle: "Read Error", message: "Cannot inflate data")

                Logger.error(error!)
                self.errors.append(error!)

                self.close(context: context)
                return
            }
            messageData = inflatedMessageData
        }
        
        // checksum
        if self.checksumEnabled {
            guard let remoteChecksum = buffer.readData(length: self.checksumLength) else {
                error = WiredError(withTitle: "Checksum Error", message: "Missing checksum data")

                Logger.error(error!)
                self.errors.append(error!)

                self.close(context: context)
                return
            }

            if let localChecksum = self.checksumData(originalData) {
                if !localChecksum.elementsEqual(remoteChecksum) {
                    error = WiredError(withTitle: "Checksum Error", message: "Checksum failed")

                    Logger.error(error!)
                    self.errors.append(error!)

                    self.close(context: context)
                    return
                }
            }
        }
        
        let message = P7Message(withData: messageData, spec: self.spec)
        
        self.transactionHandler?.receive(message: message)
        
        Logger.info("-> READ: \(message.name!) [\(messageData.count)] [encryption: \(self.encryptionEnabled)] [compression: \(self.compressionEnabled)] [checksum: \(self.checksumEnabled)] [transaction: \(message.uint32(forField: "wired.transaction"))]")
        
        self.handleMessage(message: message, context: context)
    }

    
    
    
    
    private func readTransfer(context: ChannelHandlerContext, data: NIOAny) {
        print("readTransfer")
    }
    
    
    
    
    
    
    
    // MARK: - COMPATIBILITY CHECK
    func sendCompatibilityCheck() -> Bool {
       let message = P7Message(withName: "p7.compatibility_check.specification", spec: self.spec)
       
       message.addParameter(field: "p7.compatibility_check.specification", value: self.spec.xml!)
               
       return self.write(message)
       
//       guard let response = self.readMessage() else {
//           return false
//       }
//
//       if response.name != "p7.compatibility_check.status" {
//           Logger.error("Message should be 'p7.compatibility_check.status', not '\(response.name!)'")
//       }
//
//       guard let status = response.bool(forField: "p7.compatibility_check.status") else {
//           Logger.error("Message has no 'p7.compatibility_check.status' field")
//           return false
//       }
//
//       if status == false {
//           Logger.error("Remote protocol '\(self.remoteName!) \(self.remoteVersion!)' is not compatible with local protocol '\(self.spec.protocolName!) \(self.spec.protocolVersion!)'")
//       }
//
//       return status
    }


    func receiveCompatibilityCheck() -> Bool {
       // TODO: implement this ?
       return false
    }
    
    
    
    // MARK: - CHECKSUM
    func configureChecksum() {
        if self.checksum == .SHA2_256 {
            self.checksumLength = sha2_256DigestLength
            
        } else if self.checksum == .SHA3_256 {
            self.checksumLength = sha3_256DigestLength
            
        } else if self.checksum == .HMAC_256 {
            self.checksumLength = hmac_256DigestLength
            
        } else if self.checksum == .Poly1305 {
            self.checksumLength = poly1305DigestLength
        }
    }
    
    
    // MARK: - COMPRESSION
    func configureCompression() {
        if self.compression == .DEFLATE {
            self.compressionEnabled = true
            
        } else {
            self.compressionEnabled = false
        }
    }
    
    
    
    private func inflate(_ data: Data) -> Data? {
        do {
            return try Deflate.decompress(data: data)
        } catch let error {
            Logger.error("Inflate error: \(error)")
            return nil
        }
    }
        
    private func deflate(_ data: Data) -> Data? {
        return Deflate.compress(data: data)
    }
}
