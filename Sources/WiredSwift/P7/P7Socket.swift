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

var sha2_256DigestLength  = 32
var sha3_256DigestLength  = 32
var hmac_256DigestLength  = 32
var poly1305DigestLength  = 16

public protocol SocketPasswordDelegate: class {
    func passwordForUsername(username:String) -> String?
}

public class P7Socket: NSObject {
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
    
    public var sslCipher: P7Cipher!
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
    
    public var connected: Bool = false
    public var passwordProvider:SocketPasswordDelegate?
    
    private var socket: Socket!
    public  var ecdh:ECDH!
    private var digest:Digest!
    
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
//        var option = interactive ? 1 : 0
//        
//        if(setsockopt(socket.fileDescriptor, Int32(IPPROTO_TCP), TCP_NODELAY, &option, socklen_t(MemoryLayout.size(ofValue: option))) < 0) {
//            Logger.error("Cannot setsockopt TCP_NODELAY (interactive socket)")
//        }

        self.interactive = interactive
    }
    
    
    public func clientAddress() -> String? {
        var address = sockaddr_in()
        var len = socklen_t(MemoryLayout.size(ofValue: address))
        let ptr = UnsafeMutableRawPointer(&address).assumingMemoryBound(to: sockaddr.self)

        guard getsockname(self.socket.fileDescriptor, ptr, &len) == 0 else {
            Logger.error("Socket getsockname failed.")
            return nil
        }

        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(ptr, len, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) == 0 else {
            Logger.error("Socket getnameinfo failed.")
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
                    if !self.connectKeyExchange() {
                        Logger.error("Key Exchange failed")
                        return false
                    }
                    
                    Logger.info("Encryption enabled for \(self.cipherType)")
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
    
    
    public func disconnect() {
        self.socket.close()
        
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
        var serverCipher:P7Socket.CipherType?       = nil
        var serverChecksum:P7Socket.Checksum?       = nil
        var serverCompression:P7Socket.Compression? = nil
        
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
                
        if response.name != "p7.handshake.c" {
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
                serverCompression = P7Socket.Compression(rawValue: comp)
            } else {
                serverCompression = .NONE
            }
            
            if let cip = response.enumeration(forField: "p7.handshake.encryption") {
                serverCipher = P7Socket.CipherType(rawValue: cip)
            } else {
                serverCipher = .NONE
            }
            
            if let chs = response.enumeration(forField: "p7.handshake.checksum") {
                serverChecksum = P7Socket.Checksum(rawValue: chs)
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
        var clientCipher:P7Socket.CipherType       = .NONE
        var clientChecksum:P7Socket.Checksum       = .NONE
        var clientCompression:P7Socket.Compression = .NONE
        
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
                clientCompression = P7Socket.Compression(rawValue: compression)
            }
            
            if let encryption = response.enumeration(forField: "p7.handshake.encryption") {
                clientCipher = P7Socket.CipherType(rawValue: encryption)
            }
            
            if let checksum = response.enumeration(forField: "p7.handshake.checksum") {
                clientChecksum = P7Socket.Checksum(rawValue: checksum)
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
                
        guard let saltData = serverSharedSecret.data(using: .utf8), let derivedKey = self.ecdh.deviredSymmetricKey(withSalt: saltData) else {
            Logger.error("Cannot derive key from shared secret")
            return false
        }
                
        self.sslCipher  = P7Cipher(cipher: self.cipherType, key: derivedKey, iv: nil)
        self.digest     = Digest(key: derivedKey, type: self.checksum)
        
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

        guard let privateSigningKeyData = derivedKey.dataFromHexadecimalString() else {
            Logger.error("Cannot create private signing key")
            return false
        }
        
        guard let ecdsa = ECDSA(privateKey: privateSigningKeyData) else {
            Logger.error("Cannot ini ECDSA")
            return false
        }
        
        guard let passwordSignature = ecdsa.sign(data: clientPassword1) else {
            Logger.error("Cannot read client password")
            return false
        }
        
        clientPublicKey.append(ecdsa.publicKey.rawRepresentation)
                    
        message.addParameter(field: "p7.encryption.cipher.key", value: clientPublicKey.base64EncodedData())
        message.addParameter(field: "p7.encryption.cipher.iv", value: Data(self.sslCipher.cipherIV))
        message.addParameter(field: "p7.encryption.username", value: encryptedUsername)
        message.addParameter(field: "p7.encryption.client_password", value: passwordSignature)
        
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
        
        if !ecdsa.verify(data: clientPassword2, withSignature: encryptedServerPasswordData) {
            Logger.error("Password mismatch for '\(self.username)' during key exchange, ECDSA validation failed")
            return false
        }
                
        guard let derivedKey2 = self.ecdh.deviredSymmetricKey(withSalt: clientPassword2) else {
            Logger.error("Cannot derive key from server password")
            return false
        }

        self.digest     = Digest(key: derivedKey2, type: self.checksum)
        self.sslCipher  = P7Cipher(cipher: self.cipherType, key: derivedKey2, iv: Data(self.sslCipher.cipherIV))
        
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
        
        guard   let combinedBase64Keys = response.data(forField: "p7.encryption.cipher.key"),
                let combinedKeys = Data(base64Encoded: combinedBase64Keys) else {
            Logger.error("Client public key not found")
            return false
        }
        
        let clientPublicKey     = combinedKeys.dropLast(64)
        let publicSigningKey    = combinedKeys.dropFirst(132)
        
        if clientPublicKey.count != 132 {
            Logger.error("Invalid public key")
            return false
        }

        if publicSigningKey.count != 64 {
            Logger.error("Invalid signing key")
            return false
        }
        
        guard let serverSharedSecret = self.ecdh.computeSecret(withPublicKey: clientPublicKey) else {
            Logger.error("Cannot compute shared secret")
            return false
        }
                
        guard let saltData = serverSharedSecret.data(using: .utf8), let derivedKey = self.ecdh.deviredSymmetricKey(withSalt: saltData) else {
            Logger.error("Cannot derive key from shared secret")
            return false
        }
                        
        guard let iv = response.data(forField: "p7.encryption.cipher.iv") else {
            Logger.error("Missing IV")
            return false
        }

        self.sslCipher  = P7Cipher(cipher: self.cipherType, key: derivedKey, iv: iv)
        self.digest     = Digest(key: derivedKey, type: self.checksum)
        
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

        guard let privateSigningKey = derivedKey.dataFromHexadecimalString() else {
            Logger.error("Cannot create private signing key")
            return false
        }
        
        guard let ecdsa2 = ECDSA(privateKey: privateSigningKey) else {
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
                
        guard let derivedKey2 = self.ecdh.deviredSymmetricKey(withSalt: serverPassword2Data) else {
            Logger.error("Cannot derive key from server password")
            return false
        }

        self.digest     = Digest(key: derivedKey2, type: self.checksum)
        self.sslCipher  = P7Cipher(cipher: self.cipherType, key: derivedKey2, iv: iv)

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
        if self.digest != nil  {
            return self.digest.authenticate(data: data)
        }
        return nil
    }
    
    
    private func configureCompression() {
        if self.compression == .DEFLATE {
            self.compressionEnabled = true
            
        } else {
            self.compressionEnabled = false
        }
    }
    
    
    private func configureChecksum() {
        if self.checksum == .SHA2_256 {
            self.checksumLength = sha2_256DigestLength
            
        } else if self.checksum == .SHA3_256 {
            self.checksumLength = sha3_256DigestLength
            
        } else if self.checksum == .HMAC_256 {
            self.checksumLength = hmac_256DigestLength
            
        } else if self.checksum == .Poly1305 {
            self.checksumLength = poly1305DigestLength
        }
        
        // self.checksumEnabled = true
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
