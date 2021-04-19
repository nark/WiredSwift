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
import SWCompression

var md5DigestLength       = 16
var sha1DigestLength      = 20
var sha256DigestLength    = 32
var sha512DigestLength    = 64

public protocol SocketPasswordDelegate: class {
    func passwordForUsername(username:String) -> String?
}

public class P7Socket: NSObject {
    public enum Serialization:Int {
        case XML            = 0
        case BINARY         = 1
    }
    
    public enum Compression:UInt32 {
        case NONE           = 999
        case DEFLATE        = 0
    }
    
    public enum Checksum:UInt32 {
        case NONE           = 999
        case ALL            = 998
        case SHA1           = 0
        case SHA256         = 1
        case SHA512         = 2
    }
    
    public struct CipherType: OptionSet {
        public let rawValue: UInt32
        
        public init(rawValue:UInt32 ) {
            self.rawValue = rawValue
        }
        
        public static let NONE                  = CipherType(rawValue: 0 << 0)
        public static let ECDH_AES256_SHA256    = CipherType(rawValue: 1 << 0)
        public static let ECDH_CHACHA20_SHA256  = CipherType(rawValue: 1 << 1)
        public static let ALL:CipherType        = [.ECDH_AES256_SHA256,
                                                   .ECDH_CHACHA20_SHA256]
        
        public static func pretty(_ type:CipherType) -> String {
            switch type {
            case .NONE:
                return "None"
            case .ECDH_AES256_SHA256:
                return "ECDH-AES256-SHA256"
            case .ECDH_CHACHA20_SHA256:
                return "ECDH-ChaCha20-SHA256"
            default:
                return "None"
            }
        }
    }

    
    
    public var hostname: String!
    public var port: Int!
    public var spec: P7Spec!
    public var username: String = "guest"
    public var password: String!
    public var serialization: Serialization = .BINARY
    
    public var compression: Compression = .NONE
    public var cipherType: CipherType = .NONE
    public var checksum: Checksum = .NONE
    public var sslCipher: P7Cipher!
    public var timeout: Int = 10
    public var errors: [WiredError] = []
    
    public var compressionEnabled: Bool = false
    public var compressionConfigured: Bool = false
    
    public var encryptionEnabled: Bool = false
    public var checksumEnabled: Bool = false
    public var checksumLength: Int = sha1DigestLength
    
    public var localCompatibilityCheck: Bool = false
    public var remoteCompatibilityCheck: Bool = false
    
    public var remoteVersion: String!
    public var remoteName: String!
    
    public var connected: Bool = false
    public var passwordProvider:SocketPasswordDelegate?
    
    private var socket: Socket!
    public var ecdh:ECDH!
    
    private var interactive:Bool = true
    
    public init(hostname: String, port: Int, spec: P7Spec) {
        self.hostname = hostname
        self.port = port
        self.spec = spec
    }
    
    
    public init(socket: Socket, spec: P7Spec) {
        self.socket     = socket
        self.spec       = spec
        self.connected  = true
    }
    
    
    public func getSocket() -> Socket {
        return self.socket
    }
    
    
    public func isInteractive() -> Bool {
        return self.interactive
    }
    
    public func set(interactive:Bool) {
        var option = interactive ? 1 : 0
        
        if(setsockopt(socket.fileDescriptor, Int32(IPPROTO_TCP), TCP_NODELAY, &option, socklen_t(MemoryLayout.size(ofValue: option))) < 0) {
            Logger.error("Cannot setsockopt TCP_NODELAY (interactive socket)")
        }

        self.interactive = interactive
    }
    
    
    public func clientAddress() -> String? {
        var addr = sockaddr(), len: socklen_t = socklen_t(MemoryLayout.size(ofValue: sockaddr.self))
        guard getpeername(self.socket.fileDescriptor, &addr, &len) == 0 else {
            print("getpeername(...) failed.")
            return nil
        }
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(&addr, len, &hostBuffer, socklen_t(hostBuffer.count),
            nil, 0, NI_NUMERICHOST) == 0 else {
            print("getnameinfo(...) failed.")
            return nil
        }
        
        return String(cString: hostBuffer)
    }
    
    public func connect(withHandshake handshake: Bool = true) -> Bool {
        do {
            self.socket = try Socket(.inet, type: .stream, protocol: .tcp)
            
            try socket.set(option: .receiveTimeout, TimeValue(seconds: 10, milliseconds: 0, microseconds: 0))
            try socket.set(option: .sendTimeout, TimeValue(seconds: 10, milliseconds: 0, microseconds: 0))
            try socket.set(option: .receiveBufferSize, 327680)
            try socket.set(option: .sendBufferSize, 327680)
            
            var addr:SocketAddress!
            
            do {
                addr = try socket.addresses(for: self.hostname, port: Port(self.port)).first!
            } catch let e {
                if let socketError = e as? Socket.Error {
                    self.errors.append(WiredError(withTitle: "Socket Error", message: socketError.description))
                    Logger.error(socketError.description)
                } else {
                    self.errors.append(WiredError(withTitle: "Socket Error", message: e.localizedDescription))
                    Logger.error(e.localizedDescription)
                }
                return false
            }
            
            
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
                self.errors.append(WiredError(withTitle: "Socket Error", message: socketError.description))
                Logger.error(socketError.description)
            } else {
                self.errors.append(WiredError(withTitle: "Socket Error", message: error.localizedDescription))
                Logger.error(error.localizedDescription)
            }
            return false
        }
        
        return true
    }
    
    
    
    public func accept(compression:Compression, cipher:CipherType, checksum:Checksum) -> Bool {
        if !self.acceptHandshake(timeout: timeout, compression: compression, cipher: cipher, checksum: checksum) {
                return false
        }
            
        if compression != .NONE {
            self.configureCompression()
        }

        if checksum != .NONE {
            self.configureChecksum()
        }
        
        if cipher != .NONE {
            if !self.acceptKeyExchange(timeout: timeout) {
                return false
            }
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
    
    
    public func disconnect() {
        self.socket.close()
        
        self.connected = false
        
        self.compressionEnabled = false
        self.compressionConfigured = false
        
        self.encryptionEnabled = false
        self.checksumEnabled = false
        self.checksumLength = sha1DigestLength

        self.localCompatibilityCheck = false
        self.remoteCompatibilityCheck = false
        
        self.ecdh = nil
    }
    
    
    
    public func write(_ message: P7Message) -> Bool {
        do {
            if self.serialization == .XML {
                let xml = message.xml()
                
                if let xmlData = xml.data(using: .utf8) {
                    try self.socket.write(xmlData.bytes)
                }
            }
            else if self.serialization == .BINARY {
                var lengthData = Data()
                var messageData = message.bin()
                
                lengthData.append(uint32: UInt32(messageData.count))
                
                Logger.info("WRITE [\(self.hash)]: \(message.name!)")
                //Logger.debug("\n\(message.xml())\n")

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
                
                // Logger.info("data after comp : \(messageData.toHexString())")
                
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

                _ = self.write(lengthData.bytes, maxLength: lengthData.count)
                _ = self.write(messageData.bytes, maxLength: messageData.bytes.count)
                                
                // checksum
                if self.checksumEnabled {
                    if let c = self.checksumData(messageData) {
                        _ = self.write(c.bytes, maxLength: self.checksumLength)
                    } else {
                        Logger.error("Checksum failed abnormally")
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
    

    
    
    public func readMessage() -> P7Message? {
        var messageData = Data()
        var error:WiredError? = nil
        
        var lengthBuffer = [Byte](repeating: 0, count: 4)
        let bytesRead = self.read(&lengthBuffer, maxLength: 4)
        
        // print("bytesRead : \(bytesRead)")
                                
        if bytesRead > 0 {
            if self.serialization == .XML {
                if let xml = String(bytes: messageData, encoding: .utf8) {
                    let message = P7Message(withXML: xml, spec: self.spec)

                    return message
                }
            }
            else if self.serialization == .BINARY {
                if bytesRead >= 4 {
                    guard let messageLength = Data(lengthBuffer).uint32 else {
                        error = WiredError(withTitle: "Read Error", message: "Cannot read message length")
                        
                        Logger.error(error!)
                        self.errors.append(error!)
                        
                        return nil
                    }
                    
                    do {
                        messageData = try self.readData(size: Int(messageLength))
                    } catch let e {
                        error = WiredError(withTitle: "Read Error", message: "")
                        
                        if let socketError = e as? Socket.Error {
                            error = WiredError(withTitle: "Read Error", message: socketError.description)
                        } else {
                            error = WiredError(withTitle: "Read Error", message: e.localizedDescription)
                        }
                        
                        Logger.error(error!)
                        self.errors.append(error!)
                        
                        return nil
                    }
                                        
                    // data to message object
                    if messageData.count > 0 {
                        let originalData = messageData
                        
                        // decryption
                        if self.encryptionEnabled {
                            guard let decryptedMessageData = self.sslCipher.decrypt(data: messageData) else {
                                error = WiredError(withTitle: "Read Error", message: "Cannot decrypt data")

                                Logger.error(error!)
                                self.errors.append(error!)
                                
                                return nil
                            }
                            messageData = decryptedMessageData
                        }
                        
                        // Logger.info("READ data before decomp : \(messageData.toHexString())")
                        
                        // inflate
                        if self.compressionEnabled {
                            guard let inflatedMessageData = self.inflate(messageData) else {
                                error = WiredError(withTitle: "Read Error", message: "Cannot inflate data")

                                Logger.error(error!)
                                self.errors.append(error!)
                                
                                return nil
                                
                            }
                            
                            messageData = inflatedMessageData
                        }
                    
                        //Logger.info("READ data after decomp : \(messageData.toHexString())")
                        
                        // checksum
                        if self.checksumEnabled {
                            do {
                                let remoteChecksum = try self.readData(size: self.checksumLength)
                                if remoteChecksum.count == 0 { return nil }

                                if let c = self.checksumData(originalData) {
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

                        // init response message
                        let message = P7Message(withData: messageData, spec: self.spec)
                        
                        Logger.info("READ [\(self.hash)]: \(message.name!)")
                        //Logger.debug("\n\(message.xml())\n")
                        
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
    
    
    
    private func write(_ buffer: Array<UInt8>, maxLength len: Int, timeout:TimeInterval = 1.0) -> Int {
        while let available = try? socket.wait(for: .write, timeout: timeout), self.connected == true {
            guard available else { continue } // timeout happend, try again
            
            let n = try? socket.write(buffer, size: len)
            
            return n ?? 0
        }
        
        return 0
    }
    
    
    
    private func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int, timeout:TimeInterval = 1.0) -> Int {
        while let available = try? socket.wait(for: .read, timeout: timeout), self.connected == true {
            guard available else { continue } // timeout happend, try again

            let n = try? socket.read(buffer, size: len)

            return n ?? 0
        }
        
        return 0
    }
    
    
    // I have pretty much had to rewrite my own read() function here
    private func readData(size: Int, timeout:TimeInterval = 1.0) throws -> Data {
        while let available = try? socket.wait(for: .read, timeout: timeout), self.connected == true {
            guard available else { continue } // timeout happend, try again
                
            var data = Data()
            var readBytes = 0
            var nLength = size

            while readBytes < size && nLength > 0 && self.connected == true {
                var messageBuffer = [Byte](repeating: 0, count: nLength)
                
                readBytes += try ing { recv(socket.fileDescriptor, &messageBuffer, nLength, Int32(MSG_WAITALL)) }
                nLength    = size - readBytes
                
                //print("readBytes : \(readBytes)")
                //print("nLength : \(nLength)")
                
                let subdata = Data(bytes: messageBuffer, count: readBytes)
                if subdata.count > nLength {
                    _ = subdata.dropLast(nLength)
                }
            
                //print("subdata : \(subdata.toHex())")
                
                data.append(subdata)
            }
            
            return data
        }
            
        return Data()
    }
    
    
    
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
        do {
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
                
                _ = try self.socket.write(lengthData.bytes, size: lengthData.count)
                _ = try self.socket.write(messageData.bytes, size: messageData.count)
                
                // checksum
                if self.checksumEnabled {
                    if let c = self.checksumData(originalData) {
                        _ = self.write(c.bytes, maxLength: self.checksumLength)
                    } else {
                        Logger.error("Checksum failed abnormally")
                    }
                }
            }
        } catch let error {
            if let socketError = error as? Socket.Error {
                Logger.error(socketError.description)
            } else {
                Logger.error(error.localizedDescription)
            }
            return false
        }
        
        return true
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
            
            if self.checksum != .NONE {
                message.addParameter(field: "p7.handshake.checksum", value: self.checksum.rawValue)
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
                self.cipherType = P7Socket.CipherType(rawValue: cip)
            }
            if let chs = response.enumeration(forField: "p7.handshake.checksum") {
                self.checksum = P7Socket.Checksum(rawValue: chs)!
            }
        }
                        
        if let bool = response.bool(forField: "p7.handshake.compatibility_check") {
            self.remoteCompatibilityCheck = bool
        }
        
        message = P7Message(withName: "p7.handshake.acknowledge", spec: self.spec)
        
        if self.localCompatibilityCheck {
            message.addParameter(field: "p7.handshake.compatibility_check", value: true)
        }
        
        _ = self.write(message)
        
        return true
    }
    
    
    
    private func acceptHandshake(timeout:Int, compression:Compression, cipher:CipherType, checksum:Checksum) -> Bool {
        self.compression = compression
        self.cipherType = cipher
        self.checksum = checksum
        
        // client handshake message
        guard let response = self.readMessage() else {
            Logger.error("Handshake Failed: cannot read client handshake")
            return false
        }
        
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
                self.compression = P7Socket.Compression(rawValue: compression)!
            }
            
            if let encryption = response.enumeration(forField: "p7.handshake.encryption") {
                self.cipherType = P7Socket.CipherType(rawValue: encryption)
            }
            
            if let checksum = response.enumeration(forField: "p7.handshake.checksum") {
                self.checksum = P7Socket.Checksum(rawValue: checksum)!
            }
        }
        
        let message = P7Message(withName: "p7.handshake.server_handshake", spec: self.spec)

        message.addParameter(field: "p7.handshake.version", value: self.spec.builtinProtocolVersion)
        message.addParameter(field: "p7.handshake.protocol.name", value: self.spec.protocolName)
        message.addParameter(field: "p7.handshake.protocol.version", value: self.spec.protocolVersion)
        
        if self.serialization == .BINARY {
            if self.compression != .NONE {
                message.addParameter(field: "p7.handshake.compression", value: self.compression.rawValue)
            }
            
            if self.cipherType != .NONE {
                if cipher.contains(self.cipherType) {
                    message.addParameter(field: "p7.handshake.encryption", value: self.cipherType.rawValue)
                } else {
                    message.addParameter(field: "p7.handshake.encryption", value: cipher.rawValue)
                }
            }
            
            if self.checksum != .NONE {
                message.addParameter(field: "p7.handshake.checksum", value: self.checksum.rawValue)
            }
        }
        
        if self.localCompatibilityCheck {
            message.addParameter(field: "p7.handshake.compatibility_check", value: true)
        }
                        
        if !self.write(message) {
            return false
        }
        
        guard let acknowledge = self.readMessage() else {
            return false
        }
                
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
    
    
    private func connectKeyExchange() -> Bool  {
        self.ecdh = ECDH()
        
        if self.ecdh == nil {
            Logger.error("ECDH Public key cannot be created")
            return false
        }
        
        guard let response = self.readMessage() else {
            Logger.error("Handshake Failed: cannot read server key")
            return false
        }
        
        if response.name != "p7.encryption.server_key" {
            Logger.error("Message should be 'p7.encryption.server_key', not '\(response.name!)'")
        }
        
        guard let serverPublicKey = response.data(forField: "p7.encryption.public_key") else {
            Logger.error("Message has no 'p7.encryption.public_key' field")
            return false
        }
        
        guard let serverSharedSecret = self.ecdh.computeSecret(withPublicKey: serverPublicKey) else {
            Logger.error("Cannot compute shared secret")
            return false
        }
        
        print("serverSharedSecret \(serverSharedSecret)")
        
        self.sslCipher = P7Cipher(cipher: self.cipherType, key: serverSharedSecret, iv: nil)
        
        if self.sslCipher == nil {
            Logger.error("Cipher cannot be created")
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

        if self.checksum == .SHA1 {
            clientPassword1 = clientPassword1.sha1().toHexString().data(using: .utf8)!
        } else if self.checksum == .SHA256 {
            clientPassword1 = clientPassword1.sha256().toHexString().data(using: .utf8)!
        } else if self.checksum == .SHA512 {
            clientPassword1 = clientPassword1.sha512().toHexString().data(using: .utf8)!
        }

        var clientPassword2 = serverPublicKey
        clientPassword2.append(passwordData)

        if self.checksum == .SHA1 {
            clientPassword2 = clientPassword2.sha1().toHexString().data(using: .utf8)!
        } else if self.checksum == .SHA256 {
            clientPassword2 = clientPassword2.sha256().toHexString().data(using: .utf8)!
        } else if self.checksum == .SHA512 {
            clientPassword2 = clientPassword2.sha512().toHexString().data(using: .utf8)!
        }

        let message = P7Message(withName: "p7.encryption.client_key", spec: self.spec)

        guard let clientPublicKey = self.ecdh.publicKeyData() else {
            Logger.error("Cannot read client public key")
            return false
        }
        
        guard let d = self.username.data(using: .utf8), let encryptedUsername = self.sslCipher.encrypt(data: d)  else {
            Logger.error("Cannot encrypt username")
            return false
        }

        guard let encryptedClientPassword1 = self.sslCipher.encrypt(data: clientPassword1)  else {
            Logger.error("Cannot read client password")
            return false
        }
        
        message.addParameter(field: "p7.encryption.cipher.key", value: clientPublicKey)
        message.addParameter(field: "p7.encryption.cipher.iv", value: Data(self.sslCipher.cipherIV))
        message.addParameter(field: "p7.encryption.username", value: encryptedUsername)
        message.addParameter(field: "p7.encryption.client_password", value: encryptedClientPassword1)

        _ = self.write(message)
        

        guard let response2 = self.readMessage() else {
            Logger.error("Cannot read p7.encryption.acknowledge message")
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
            // TODO: write our own passwords comparison method, this is uggly
            if serverPasswordData.toHexString() != clientPassword2.stringUTF8! {
                Logger.error("Password mismatch during key exchange")
                return false
            }
        }

        self.encryptionEnabled = true

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

        if !self.write(message) {
            return false
        }

        // read the client public key
        guard let response = self.readMessage() else {
            return false
        }
        
        if response.name != "p7.encryption.client_key" {
            Logger.error("Message should be 'p7.encryption.client_key', not '\(response.name!)'")
            return false
        }
        
        
        guard let clientPublicKey = response.data(forField: "p7.encryption.cipher.key") else {
            Logger.error("Client public key not found")
            return false
        }
        
        guard let clientSharedSecret = self.ecdh.computeSecret(withPublicKey: clientPublicKey) else {
            Logger.error("Cannot compute shared secret")
            return false
        }
        
        print("clientSharedSecret : \(clientSharedSecret)")
                
        guard let iv = response.data(forField: "p7.encryption.cipher.iv") else {
            Logger.error("Missing IV")
            return false
        }

        self.sslCipher = P7Cipher(cipher: self.cipherType, key: clientSharedSecret, iv: iv)

//        if iv != nil {
//            iv = self.rsa.decrypt(data: iv!)
//
//            if iv == nil {
//                Logger.error("Cannot decrypt 'p7.encryption.cipher.iv' vector")
//                return false
//            }
//        }
        
//        var iv = response.data(forField: "p7.encryption.cipher.iv")
//
//        if key == nil {
//            Logger.error("Message has no 'p7.encryption.cipher.key' field")
//            return false
//        }
//
//        key = self.rsa.decrypt(data: key!) //wi_rsa_decrypt(self.rsa.privateKey, key);
//
//        if key == nil {
//            Logger.error("Cannot decrypt 'p7.encryption.cipher.key' key")
//            return false
//        }
//
//        if iv != nil {
//            iv = self.rsa.decrypt(data: iv!)
//
//            if iv == nil {
//                Logger.error("Cannot decrypt 'p7.encryption.cipher.iv' vector")
//                return false
//            }
//        }
//
//        self.sslCipher = P7Cipher(cipher: self.cipherType, key: key!, iv: iv!)
//
        if self.sslCipher == nil {
            Logger.error("Cannot init cipher (\(self.cipherType)")
            return false
        }

        var data = response.data(forField: "p7.encryption.username")

        data = self.sslCipher.decrypt(data: data!)

        guard let username = data?.stringUTF8 else {
            Logger.error("Message has no 'p7.encryption.username' field")
            return false
        }

        self.username = username

        data = response.data(forField: "p7.encryption.client_password")

        data = self.sslCipher.decrypt(data: data!)

        guard let client_password = data?.stringUTF8 else {
            Logger.error("Message has no 'p7.encryption.client_password' field")
            return false
        }

        if self.passwordProvider != nil {
            // TODO: implement a password provider delegate protocol
            if let password = self.passwordProvider?.passwordForUsername(username: self.username) {
                self.password = password
            }
        } else {
            // assume password is empty (guest with empty password access only)
            self.password = "".sha256()
        }

        let passwordData = self.password.data(using: .utf8)!
        var serverPassword1Data = passwordData
        serverPassword1Data.append(serverPublicKey)

        if self.checksum == .SHA1 {
            serverPassword1Data = serverPassword1Data.sha1()
        } else if self.checksum == .SHA256 {
            serverPassword1Data = serverPassword1Data.sha256()
        } else if self.checksum == .SHA512 {
            serverPassword1Data = serverPassword1Data.sha512()
        }

        var serverPassword2Data = serverPublicKey
        serverPassword2Data.append(passwordData)

        if self.checksum == .SHA1 {
            serverPassword2Data = serverPassword2Data.sha1()
        } else if self.checksum == .SHA256 {
            serverPassword2Data = serverPassword2Data.sha256()
        } else if self.checksum == .SHA512 {
            serverPassword2Data = serverPassword2Data.sha512()
        }

        if client_password != serverPassword1Data.toHexString() {
            Logger.error("Password mismatch for '\(self.username)' during key exchange")
            return false
        }

        // acknowledge
        let message2 = P7Message(withName: "p7.encryption.acknowledge", spec: self.spec)

        guard let d = self.sslCipher.encrypt(data: serverPassword2Data) else {
            return false
        }

        message2.addParameter(field: "p7.encryption.server_password", value: d)

        if !self.write(message2) {
            return false
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
            Logger.error("Message should be 'p7.compatibility_check.status', not '\(response.name!)'")
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
    
    

    
    
    private func checksumData(_ data:Data) -> Data? {
        var checksum: Data? = nil
        
        if self.checksum == .SHA256 {
            checksum = data.sha256()
            
        } else if self.checksum == .SHA512 {
            checksum = data.sha512()
            
        } else {
            checksum = data.sha1()
        }
        
        return checksum
    }
    
    
    private func configureCompression() {
        if self.compression == .DEFLATE {
            self.compressionEnabled = true
            
        } else {
            self.compressionEnabled = false
        }
    }
    
    
    private func configureChecksum() {
        if self.checksum == .SHA1 {
            self.checksumLength = sha1DigestLength
            
        } else if self.checksum == .SHA256 {
            self.checksumLength = sha256DigestLength
            
        } else if self.checksum == .SHA512 {
            self.checksumLength = sha512DigestLength
        }
        
        self.checksumEnabled = true
    }
    
    
    // MARK: -
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
