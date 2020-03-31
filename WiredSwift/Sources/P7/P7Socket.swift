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
import CZlib



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
        
        public static func pretty(_ type:CipherType) -> String {
            switch type {
            case .NONE:
                return "None"
            case .RSA_AES_128:
                return "AES/128 bits"
            case .RSA_AES_192:
                return "AES/192 bits"
            case .RSA_AES_256:
                return "AES/256 bits"
            case .RSA_BF_128:
                return "BF/128 bits"
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
    public var cipherType: CipherType = .RSA_AES_256
    public var checksum: Checksum = .NONE
    public var sslCipher: P7Cipher!
    public var timeout: Int = 10
    public var errors: [WiredError] = []
    
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
    private var dropped:Data = Data()
    
    private var deflateStream:z_stream = zlib.z_stream()
    private var inflateStream:z_stream = zlib.z_stream()
    
    public init(hostname: String, port: Int, spec: P7Spec) {
        self.hostname = hostname
        self.port = port
        self.spec = spec
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
    
    
    
    public func disconnect() {
        self.socket.close()
        
        self.connected = false
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
                
                Logger.info("WRITE [\(self.hash)]: \(message.name!)")
                Logger.debug("\(message.xml(pretty: true))\n")
                
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
                
                _ = self.write(lengthData.bytes, maxLength: lengthData.count)
                _ = self.write(messageData.bytes, maxLength: messageData.count)
                
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
                        
                        // init response message
                        let message = P7Message(withData: messageData, spec: self.spec)
                        
                        Logger.info("READ [\(self.hash)]: \(message.name!)")
                        Logger.debug("\(message.xml(pretty: true))\n")
                        
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
                
                readBytes += try ing { recv(socket.fileDescriptor, &messageBuffer, nLength, MSG_WAITALL) }
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
    
    
    
    private func encryptData(_ data: Data) -> Data? {
        do {
            let dataKey = try SwKeyConvert.PublicKey.pemToPKCS1DER(self.publicKey)
            return try CC.RSA.encrypt(data, derKey: dataKey, tag: Data(), padding: .oaep, digest: .sha1)
        } catch  { }
        return nil
    }
    
    
    private func configureCompression() {
        if self.compression == .DEFLATE {
            var err = zlib.deflateInit_(&self.deflateStream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            
            self.deflateStream.data_type = Z_UNKNOWN
            
            if err != Z_OK {
                Logger.error("Cannot init Zlib")
                
                return
            }
            
            err = zlib.inflateInit_(&self.inflateStream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            
            if err != Z_OK {
                Logger.error("Cannot init Zlib")
                
                return
            }
            
            self.compressionEnabled = true
            
        } else {
            self.compressionEnabled = false
        }
    }
    
    
    private func configureChecksum() {
        self.checksumEnabled = true
    }
    
    
// MARK: -
private func inflate(_ data: Data) -> Data? {
//    var outData = Data()
//    var inData = data
//
//
//    print("inflate")
//
//    for var multiple in stride(from: 0, to: 16, by: 2) {
//        print("multiple: \(multiple)")
//
//        let compression_buffer_length = inData.count * (1 << multiple)
//
//        print("compression_buffer_length: \(compression_buffer_length)")
//
//        var subData = Data(capacity: compression_buffer_length)
//
//        inData.withUnsafeBytes { (inputPointer: UnsafeRawBufferPointer) in
//            self.inflateStream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputPointer.bindMemory(to: Bytef.self).baseAddress!).advanced(by: Int(self.inflateStream.total_in))
//            self.inflateStream.avail_in = uint(inData.count)
//        }
//
//        subData.withUnsafeMutableBytes { (outputPointer: UnsafeMutableRawBufferPointer) in
//            self.inflateStream.next_out = outputPointer.bindMemory(to: Bytef.self).baseAddress!.advanced(by: Int(self.inflateStream.total_out))
//            self.inflateStream.avail_out = uInt(outData.count)
//        }
//
//        let err = zlib.inflate(&self.inflateStream, Z_FINISH)
//        let enderr = zlib.inflateReset(&self.inflateStream)
//
//        outData.append(Data(bytes: self.inflateStream.next_out, count: Int(self.inflateStream.avail_out)))
//
//        print("outData: \(outData.toHex())")
//
//        if err == Z_STREAM_END && enderr != Z_BUF_ERROR {
//            break
//        }
//    }
//
//    return outData
    return data
}
    
    private func deflate(_ data: Data) -> Data? {
        
//        var inData = data
//        let length = (inData.count * 2) + 16
//        var outData = Data(capacity: length)
//
//
//        var stream = zlib.z_stream()
//                    
//        stream.data_type = Z_UNKNOWN
//        
//        inData.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<Bytef>) in
//            stream.next_in = bytes
//        }
//        stream.avail_in = UInt32(inData.count)
//        
//        outData.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<Bytef>) in
//            stream.next_out = bytes
//        }
//        stream.avail_out = UInt32(outData.count)
//        
//        let err = zlib.deflate(&stream, Z_FINISH)
//        let enderr = zlib.deflateReset(&stream)
//        
//        print("deflate err : \(err)")
//        print("deflate err : \(err)")
//        
//        if (err != Z_STREAM_END) {
//            if (err == Z_OK) {
//                print("Deflate Z_BUF_ERROR")
//            }
//            
//            return nil;
//        }
//        
//        if (enderr != Z_OK) {
//            print("Deflate not Z_OK")
//            return nil;
//        }
//        
//        print("outData : \(outData.toHex())")
//
//        return outData
        return data
    }
    
}
