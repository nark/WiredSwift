//
//  Socket.swift
//  Wired 3
//
//  Created by Rafael Warnault on 18/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//
// swiftlint:disable file_length type_body_length
// TODO: Split P7Socket I/O and handshake logic into separate types

import Foundation
import SocketSwift
import CryptoSwift
import Crypto
#if !os(Linux)
import DataCompression
#endif

var sha2_256DigestLength  = 32
var sha2_384DigestLength  = 48
var sha3_256DigestLength  = 32
var sha3_384DigestLength  = 48
var hmac_256DigestLength  = 32
var hmac_384DigestLength  = 48

/// Supplies per-user credentials to a server-side `P7Socket` during key exchange.
public protocol SocketPasswordDelegate: AnyObject {
    /// Returns the stored (pre-hashed) password for the given username.
    ///
    /// - Parameter username: The username received from the client.
    /// - Returns: The stored password string, or `nil` if the user does not exist.
    func passwordForUsername(username: String) -> String?
    /// Returns the per-user stored salt (hex string) used to derive the base hash in key exchange.
    /// Return nil if the account has not yet been assigned a stored salt.
    func passwordSaltForUsername(username: String) -> String?
}

/// Provides the server's persistent identity key for TOFU (Trust On First Use).
/// Set on the server-side P7Socket so that `acceptKeyExchange` can sign the
/// ephemeral ECDH public key with the identity key.
public protocol ServerIdentityProvider: AnyObject {
    /// Raw P256 public key (64 bytes).
    var identityPublicKey: Data { get }
    /// Whether clients must hard-fail on key mismatch (true) or may auto-update (false).
    var strictIdentity: Bool { get }
    /// Sign the given data with the persistent identity private key.
    func signWithIdentity(data: Data) -> Data?
}

/// Full-duplex P7 socket providing TLS-style handshake, ECDH key exchange,
/// optional compression, and binary/XML message serialisation.
///
/// **Typical client usage:**
/// 1. Create with `init(hostname:port:spec:)` and configure `cipherType`, `checksum`, etc.
/// 2. Call `connect(withHandshake:)` to establish the TCP connection and run the P7 handshake.
/// 3. Use `write(_:)` / `readMessage()` to exchange `P7Message` objects.
/// 4. Call `disconnect()` when done.
///
/// **Typical server usage:**
/// 1. Accept an incoming TCP connection and create with `init(socket:spec:)`.
/// 2. Set `passwordProvider` (and optionally `identityProvider`).
/// 3. Call `accept(compression:cipher:checksum:)` to run the handshake.
/// 4. Use `write(_:)` / `readMessage()` to exchange messages.
public class P7Socket: NSObject {
    enum P7SocketError: Error {
        case interactiveSocketFailed
        case socketError(Error)
        case addressResolutionFailed(host: String, port: Int)
        case handshakeFailed(_ message: String? = nil, underlying: Error? = nil)
        case keyExchangeFailed(_ message: String? = nil)
        case remoteCompatibilityFailed(_ message: String? = nil)
        case localCompatibilityFailed(_ message: String? = nil)

        case writeFailed(_ message: String? = nil)
        case readFailed(_ message: String? = nil)

        case inflateError
        case deflateError
    }

    /// Maximum allowed P7 message size (64 MB) to prevent OOM from malicious length fields
    private static let maxMessageSize: UInt32 = 64 * 1024 * 1024

    /// Maximum time (seconds) allowed for the entire accept/handshake path per read.
    /// Prevents thread-pool exhaustion from clients that connect but never complete auth.
    private static let handshakeTimeout: TimeInterval = 30.0

    /// Wire serialisation format used for P7 messages.
    public enum Serialization: Int {
        /// Human-readable XML framing (debug / legacy).
        case XML            = 0
        /// Compact binary TLV framing used in production.
        case BINARY         = 1
    }

    /// Compression algorithm negotiated during the P7 handshake.
    ///
    /// Represented as an `OptionSet` so that multiple algorithms can be
    /// advertised in a capability bitmask; only a single value is active
    /// after negotiation completes.
    public struct Compression: OptionSet, CustomStringConvertible {
        /// Raw bitmask value as transmitted on the wire.
        public let rawValue: UInt32

        /// Creates a `Compression` from a raw wire value.
        public init(rawValue: UInt32 ) {
            self.rawValue = rawValue
        }

        /// No compression.
        public static let NONE                              = Compression(rawValue: 1 << 0)
        public static let DEFLATE                           = Compression(rawValue: 1 << 1)
        public static let LZFSE                             = Compression(rawValue: 1 << 2)
        public static let LZ4                               = Compression(rawValue: 1 << 3)
        public static let ALL: Compression                   = [.NONE, .DEFLATE, .LZFSE, .LZ4]
        public static let COMPRESSION_ONLY: Compression      = [.DEFLATE, .LZFSE, .LZ4]

        public var description: String {
            switch self {
            case .NONE:
                return "None"
            case .DEFLATE:
                return "DEFLATE"
            case .LZFSE:
                return "LZFSE"
            case .LZ4:
                return "LZ4"
            case .COMPRESSION_ONLY:
                return "COMPRESSION_ONLY"
            case .ALL:
                return "ALL"
            default:
                return "None"
            }
        }
    }

    /// Message-authentication algorithm negotiated during the P7 handshake.
    ///
    /// Like `Compression`, represented as an `OptionSet` for capability
    /// advertising; only one value is active after negotiation.
    public struct Checksum: OptionSet, CustomStringConvertible, Collection {
        /// Raw bitmask value as transmitted on the wire.
        public let rawValue: UInt32

        /// Creates a `Checksum` from a raw wire value.
        public init(rawValue: UInt32 ) {
            self.rawValue = rawValue
        }

        /// No message authentication.
        public static let NONE      = Checksum(rawValue: 1 << 0)
        public static let SHA2_256  = Checksum(rawValue: 1 << 1)
        public static let SHA2_384  = Checksum(rawValue: 1 << 2)
        public static let SHA3_256  = Checksum(rawValue: 1 << 3)
        public static let SHA3_384  = Checksum(rawValue: 1 << 4)
        public static let HMAC_256  = Checksum(rawValue: 1 << 5)
        public static let HMAC_384  = Checksum(rawValue: 1 << 6)

        public static let ALL: Checksum = [
            .NONE,
            .SHA2_256,
            .SHA2_384,
            .SHA3_256,
            .SHA3_384,
            .HMAC_256,
            .HMAC_384
        ]
        public static let SECURE_ONLY: Checksum = [
            .SHA2_256,
            .SHA2_384,
            .SHA3_256,
            .SHA3_384,
            .HMAC_256,
            .HMAC_384
        ]

        public var description: String {
            switch self {
            case .NONE:
                return "None"
            case .SHA2_256:
                return "SHA2_256"
            case .SHA2_384:
                return "SHA2_384"
            case .SHA3_256:
                return "SHA3_256"
            case .SHA3_384:
                return "SHA3_384"
            case .HMAC_256:
                return "HMAC_256"
            case .HMAC_384:
                return "HMAC_384"
            case .SECURE_ONLY:
                return "SECURE_ONLY"
            case .ALL:
                return "ALL"
            default:
                return "None"
            }
        }
    }

    /// Cipher suite negotiated during the P7 ECDH key exchange.
    ///
    /// Represented as an `OptionSet` for capability advertising; the server
    /// selects one cipher from the intersection with the client's offer.
    /// AEAD suites (GCM, ChaCha20-Poly1305, XChaCha20-Poly1305) also provide
    /// message integrity, making a separate `Checksum` redundant.
    public struct CipherType: OptionSet, CustomStringConvertible, Collection {
        /// Raw bitmask value as transmitted on the wire.
        public let rawValue: UInt32

        /// Creates a `CipherType` from a raw wire value.
        public init(rawValue: UInt32 ) {
            self.rawValue = rawValue
        }

        /// No encryption.
        public static let NONE                      = CipherType(rawValue: 1 << 0)
        public static let ECDH_AES256_SHA256        = CipherType(rawValue: 1 << 1)
        public static let ECDH_AES128_GCM           = CipherType(rawValue: 1 << 2)
        public static let ECDH_AES256_GCM           = CipherType(rawValue: 1 << 3)
        public static let ECDH_CHACHA20_POLY1305    = CipherType(rawValue: 1 << 4)
        public static let ECDH_XCHACHA20_POLY1305   = CipherType(rawValue: 1 << 5)

        public static let ALL: CipherType = [
            .NONE,
            .ECDH_AES256_SHA256,
            .ECDH_AES128_GCM,
            .ECDH_AES256_GCM,
            .ECDH_CHACHA20_POLY1305,
            .ECDH_XCHACHA20_POLY1305
        ]
        public static let SECURE_ONLY: CipherType = [
            .ECDH_AES256_SHA256,
            .ECDH_AES128_GCM,
            .ECDH_AES256_GCM,
            .ECDH_CHACHA20_POLY1305,
            .ECDH_XCHACHA20_POLY1305
        ]

        public var description: String {
            switch self {
            case .NONE:
                return "None"
            case .ECDH_AES256_SHA256:
                return "ECDHE-ECDSA-AES256-SHA256"
            case .ECDH_AES128_GCM:
                return "ECDHE-ECDSA-AES128-GCM"
            case .ECDH_AES256_GCM:
                return "ECDHE-ECDSA-AES256-GCM"
            case .ECDH_CHACHA20_POLY1305:
                return "ECDHE-ECDSA-ChaCha20-Poly1305"
            case .ECDH_XCHACHA20_POLY1305:
                return "ECDHE-ECDSA-XChaCha20-Poly1305"
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

    public var sslCipher: Cipher!
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
    public var remoteAddress: String?

    public var connected: Bool = false
    public var passwordProvider: SocketPasswordDelegate?

    /// Server-side: provides the persistent identity key for TOFU signing.
    /// Set before calling `accept()` on the server side.
    public weak var identityProvider: ServerIdentityProvider?

    /// Client-side: called during `connectKeyExchange` when the server sends its identity key.
    ///
    /// Arguments:
    ///   - fingerprint: hex SHA-256 of the server's identity public key
    ///   - isNewKey: true on first connection (no stored fingerprint yet)
    ///   - strictIdentity: value advertised by the server
    ///
    /// Return true to continue the connection, false to abort.
    /// If nil, TOFU is not enforced (backward-compatible with pre-v1.3 servers).
    public var serverTrustHandler: ((_ fingerprint: String, _ isNewKey: Bool, _ strictIdentity: Bool) -> Bool)?

    private var socket: Socket?
    private let readLock = NSLock()
    private let writeLock = NSLock()
    private let connectionStateLock = NSLock()

    public  var ecdh: ECDH!
    public var digest: Digest = Digest(type: .SHA2_256)

    private var interactive: Bool = true

    private var cipherProvidesIntegrity: Bool {
           cipherType.contains(.ECDH_AES128_GCM)
        || cipherType.contains(.ECDH_AES256_GCM)
        || cipherType.contains(.ECDH_CHACHA20_POLY1305)
        || cipherType.contains(.ECDH_XCHACHA20_POLY1305)
    }

    private func normalizedCompression(_ value: Compression) -> Compression {
        #if os(Linux)
        var normalized = value
        if !LinuxCompressionSupport.isLZFSEAvailable {
            normalized.remove(.LZFSE)
        }
        return normalized.rawValue == 0 ? .NONE : normalized
        #else
        return value
        #endif
    }

    private func compressionPreview(_ data: Data, limit: Int = 16) -> String {
        let prefix = data.prefix(limit)
        let hex = prefix.map { String(format: "%02x", $0) }.joined(separator: " ")
        return "\(hex) (len=\(data.count))"
    }

    // Keep LZ4 wire format deterministic across platforms:
    // use Apple-compatible stored frame (bv4- + size + payload + bv4$).
    private func encodeLZ4StoreFrame(_ data: Data) -> Data {
        let header: [UInt8] = [0x62, 0x76, 0x34, 0x2d] // "bv4-"
        let footer: [UInt8] = [0x62, 0x76, 0x34, 0x24] // "bv4$"

        var framed = Data()
        framed.append(contentsOf: header)
        var sizeLE = UInt32(data.count).littleEndian
        framed.append(Data(bytes: &sizeLE, count: MemoryLayout<UInt32>.size))
        framed.append(data)
        framed.append(contentsOf: footer)
        return framed
    }

    private func decodeLZ4StoreFrame(_ data: Data) -> Data? {
        let overhead = 4 + MemoryLayout<UInt32>.size + 4
        guard data.count >= overhead else { return nil }

        let prefix = Array(data.prefix(4))
        let suffix = Array(data.suffix(4))
        guard prefix.count == 4,
              prefix[0] == 0x62, // b
              prefix[1] == 0x76, // v
              prefix[2] == 0x34, // 4
              suffix == [0x62, 0x76, 0x34, 0x24] // bv4$
        else {
            return nil
        }

        let sizeData = data.subdata(in: 4..<(4 + MemoryLayout<UInt32>.size))
        let sizeBytes = Array(sizeData)
        guard sizeBytes.count == 4 else { return nil }
        let expectedSize = Int(
            UInt32(sizeBytes[0]) |
            (UInt32(sizeBytes[1]) << 8) |
            (UInt32(sizeBytes[2]) << 16) |
            (UInt32(sizeBytes[3]) << 24)
        )

        let payload = data.subdata(in: (4 + MemoryLayout<UInt32>.size)..<(data.count - 4))
        if payload.count == expectedSize {
            return payload
        }

        return nil
    }

    /// Creates a client-side socket that will connect to the given host.
    ///
    /// - Parameters:
    ///   - hostname: Remote host name or IP address.
    ///   - port: TCP port number.
    ///   - spec: The P7 protocol specification used for message serialisation.
    public init(hostname: String, port: Int, spec: P7Spec) {
        self.hostname = hostname
        self.port = port
        self.spec = spec
    }

    /// Creates a server-side socket wrapping an already-accepted TCP connection.
    ///
    /// - Parameters:
    ///   - socket: The raw TCP socket returned by the server's accept loop.
    ///   - spec: The P7 protocol specification used for message serialisation.
    public init(socket: Socket, spec: P7Spec) {
        self.socket     = socket
        self.spec       = spec
        self.connected  = true
    }

    /// Returns the underlying `SocketSwift` socket, if connected.
    public func getNativeSocket() -> Socket? {
        return self.socket
    }

    /// Returns whether the socket is currently in interactive (TCP_NODELAY) mode.
    public func isInteractive() -> Bool {
        return self.interactive
    }

    /// Enables or disables TCP_NODELAY (Nagle's algorithm) on the underlying socket.
    ///
    /// Set `interactive` to `true` for latency-sensitive chat sessions and `false`
    /// for bulk transfers.
    ///
    /// - Parameter interactive: `true` to disable Nagle's algorithm (low latency);
    ///   `false` to enable it (higher throughput).
    /// - Throws: `P7SocketError.interactiveSocketFailed` if `setsockopt` fails.
    public func set(interactive: Bool) throws {
        var option = interactive ? 1 : 0

        if let socket {
            if setsockopt(socket.fileDescriptor, Int32(IPPROTO_TCP), TCP_NODELAY, &option, socklen_t(MemoryLayout.size(ofValue: option))) < 0 {
                Logger.error("Cannot setsockopt TCP_NODELAY (interactive socket)")
                throw P7SocketError.interactiveSocketFailed
            }
        }

        self.interactive = interactive
    }

    // MARK: - CONNECTION
    /// Opens a TCP connection to `hostname:port` and, by default, runs the full
    /// P7 handshake (capability negotiation + ECDH key exchange).
    ///
    /// Configure `compression`, `cipherType`, and `checksum` before calling this.
    ///
    /// - Parameter handshake: Pass `false` to skip the P7 handshake (raw TCP only).
    /// - Throws: `NetworkError` or `P7SocketError` on connection or handshake failure.
    public func connect(withHandshake handshake: Bool = true) throws {
        self.compression = normalizedCompression(self.compression)
        self.compressionFallback = normalizedCompression(self.compressionFallback)

        do {
            self.socket = try Socket(.inet, type: .stream, protocol: .tcp)

            try socket?.set(option: .receiveTimeout, TimeValue(seconds: 10, milliseconds: 0, microseconds: 0))
            try socket?.set(option: .sendTimeout, TimeValue(seconds: 10, milliseconds: 0, microseconds: 0))
            try socket?.set(option: .receiveBufferSize, 327680)
            try socket?.set(option: .sendBufferSize, 327680)

            // Résolution d’adresse
            guard let addr = try socket?
                .addresses(for: self.hostname, port: Port(self.port))
                .first
            else {
                print("throwing here")
                throw P7SocketError.addressResolutionFailed(
                    host: hostname,
                    port: port
                )
            }

            try socket?.connect(address: addr)
            self.connected = true

            guard handshake else { return }

            // Handshake
            try self.connectHandshake()

            if self.compression != .NONE {
                self.configureCompression()

                Logger.debug("Compression enabled for \(self.compression)")
            }

            if self.checksum != .NONE {
                self.configureChecksum()

                Logger.debug("Checksum enabled for \(self.checksum)")
            }

            if self.cipherType != .NONE {
                // Key Exchange
                try self.connectKeyExchange()

                Logger.debug("Connect with encryption enabled for \(self.cipherType)")
            }

            if self.remoteCompatibilityCheck {
                try self.sendCompatibilityCheck()
            }

            if self.localCompatibilityCheck {
                try self.receiveCompatibilityCheck()
            }

        } catch {
            if let socketError = error as? Socket.Error {
                throw NetworkError.fromErrno(socketError.errno, host: hostname, port: port)
            } else {
                throw error
            }
        }
    }

    /// Runs the server-side P7 handshake on an already-accepted TCP socket.
    ///
    /// The server advertises its supported `compression`, `cipher`, and `checksum`
    /// capabilities and negotiates a single algorithm for each with the client.
    ///
    /// - Parameters:
    ///   - compression: Compression algorithms the server is willing to accept.
    ///   - cipher: Cipher suites the server is willing to accept.
    ///   - checksum: Checksum algorithms the server is willing to accept.
    /// - Throws: `P7SocketError` on handshake or key-exchange failure.
    public func accept(compression: Compression, cipher: CipherType, checksum: Checksum) throws {
        self.remoteAddress = self.clientAddress()

        try self.acceptHandshake(timeout: timeout, compression: compression, cipher: cipher, checksum: checksum)

        if self.compression != .NONE {
            self.configureCompression()

            Logger.debug("Compression enabled for \(self.compression)")

        }

        if self.checksum != .NONE {
            self.configureChecksum()

            Logger.debug("Checksum enabled for \(self.checksum)")

        }

        if self.cipherType != .NONE {
            try self.acceptKeyExchange(timeout: timeout)

            Logger.debug("Accept with encryption enabled for \(self.cipherType)")
        }

        if self.localCompatibilityCheck {
            try self.receiveCompatibilityCheck()
        }

        if self.remoteCompatibilityCheck {
            try self.sendCompatibilityCheck()
        }
    }

    /// Closes the TCP connection and resets all session state.
    ///
    /// Safe to call from any thread and idempotent — subsequent calls are no-ops.
    public func disconnect() {
        // Disconnect can be triggered from multiple paths (client-side close,
        // server-side disconnect callbacks). Make it idempotent and thread-safe
        // to avoid double-closing guarded file descriptors on macOS.
        connectionStateLock.lock()
        let socketToClose = self.socket
        self.socket = nil
        connectionStateLock.unlock()

        socketToClose?.close()

        self.connected = false

        self.compressionEnabled = false
        self.compressionConfigured = false

        self.encryptionEnabled = false
        self.checksumEnabled = false

        self.localCompatibilityCheck = false
        self.remoteCompatibilityCheck = false

        self.ecdh = nil
    }

    // MARK: - MESSAGE READ/WRITE
    /// Serialises and sends a `P7Message` over the wire.
    ///
    /// Applies compression and encryption according to the negotiated session
    /// parameters, then appends a checksum if required.
    ///
    /// - Parameter message: The message to send.
    /// - Returns: `true` if the message was written successfully; `false` on error.
    public func write(_ message: P7Message) -> Bool {
        writeLock.lock()
        defer { writeLock.unlock() }

        do {
            if self.serialization == .XML {
                let xml = message.xml()

                if let xmlData = xml.data(using: .utf8) {
                    try self.socket?.write(Array(xmlData))
                }
            } else if self.serialization == .BINARY {
                var lengthData = Data()
                var messageData = message.bin()

                lengthData.append(uint32: UInt32(messageData.count))

                Logger.debug("WRITE [\(self.hash)]: \(message.name!) \(messageData.count)")
                // Logger.debug("\n\(message.xml())\n")

                // deflate
                if self.compressionEnabled {
                    messageData = try self.compress(messageData)

                    lengthData = Data()
                    lengthData.append(uint32: UInt32(messageData.count))
                }

                // Logger.info("data after comp : \(messageData.toHexString())")

                // encryption
                if self.encryptionEnabled {
                    guard let encryptedMessageData = try? self.sslCipher.encrypt(data: messageData) else {
                        Logger.error("Cannot encrypt data")
                        return false
                    }

                    messageData = encryptedMessageData

                    lengthData = Data()
                    lengthData.append(uint32: UInt32(messageData.count))
                }

                // print("write data : \(messageData.toHexString())")

                let wroteLength = self.write(Array(lengthData), maxLength: lengthData.count)
                if wroteLength != lengthData.count {
                    return false
                }

                let payloadBytes = Array(messageData)
                let wrotePayload = self.write(payloadBytes, maxLength: payloadBytes.count)
                if wrotePayload != payloadBytes.count {
                    return false
                }

                // checksum
                if self.checksumEnabled {
                    do {
                        let c = try self.checksumData(messageData)

                        let wroteChecksum = self.write(Array(c), maxLength: self.checksumLength(self.digest.type))
                        if wroteChecksum != self.checksumLength(self.digest.type) {
                            return false
                        }

                    } catch let error {
                        Logger.error("Checksum failed abnormally \(error)")
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

    /// Reads the next `P7Message` from the wire.
    ///
    /// Validates the length header, decrypts, decompresses, and verifies the
    /// checksum before deserialising the binary TLV payload into a `P7Message`.
    ///
    /// - Parameters:
    ///   - timeout: Per-read I/O timeout in seconds.
    ///   - enforceDeadline: When `true`, the cumulative read time is capped at
    ///     `timeout` seconds across all internal read calls for this message.
    /// - Returns: The next decoded message.
    /// - Throws: `P7SocketError.readFailed` on I/O error, length validation
    ///   failure, decryption error, or checksum mismatch.
    public func readMessage(
        timeout: TimeInterval = 1.0,
        enforceDeadline: Bool = false
    ) throws -> P7Message {
        readLock.lock()
        defer { readLock.unlock() }

        guard connected else {
            throw P7SocketError.readFailed("Not connected")
        }

        guard serialization == .BINARY else {
            throw P7SocketError.readFailed("Not binary serialization")
        }

        // 1️⃣ Read message length (4 bytes)
        let lengthData = try readExactly(size: 4, timeout: timeout, enforceDeadline: enforceDeadline)
        guard let messageLength = lengthData.uint32 else {
            let errorMessage = "Cannot read message length"
            Logger.error(errorMessage)
            throw P7SocketError.readFailed(errorMessage)
        }

        // 2️⃣ Validate message length before allocation
        // SECURITY (FUZZ_001): A declared length of 0 (or < 4) causes P7Message to crash
        // trying to read the 4-byte msg_id from an empty payload.
        guard messageLength >= 4 else {
            let errorMessage = "Message length \(messageLength) too small (minimum 4 bytes for msg_id)"
            Logger.error(errorMessage)
            throw P7SocketError.readFailed(errorMessage)
        }
        guard messageLength <= P7Socket.maxMessageSize else {
            let errorMessage = "Message length \(messageLength) exceeds maximum allowed size (\(P7Socket.maxMessageSize))"
            Logger.error(errorMessage)
            throw P7SocketError.readFailed(errorMessage)
        }

        // 3️⃣ Read payload
        let encryptedPayload = try readExactly(size: Int(messageLength), timeout: timeout, enforceDeadline: enforceDeadline)
        let originalPayload = encryptedPayload
        var payload = encryptedPayload

        // 3️⃣ Decrypt
        if encryptionEnabled {
            guard let decrypted = try? sslCipher.decrypt(data: payload) else {
                let errorMessage = "Decryption failed"
                Logger.error(errorMessage)
                throw P7SocketError.readFailed(errorMessage)
            }
            payload = decrypted
        }

        // 4️⃣ Inflate
        if compressionEnabled {
            payload = try decompress(payload)
        }

        // 5️⃣ Checksum (STRICT framing)
        if checksumEnabled {
            let remoteChecksum = try readExactly(size: checksumLength(self.digest.type), timeout: timeout, enforceDeadline: enforceDeadline)
            let localChecksum = try checksumData(originalPayload)

            if localChecksum != remoteChecksum {
                let errorMessage = "Checksum failed"
                Logger.error(errorMessage)
                throw P7SocketError.readFailed(errorMessage)
            }
        }

        // 6️⃣ Build message
        let message = P7Message(withData: payload, spec: spec)
        Logger.debug("READ [\(hash)]: \(message.name)")

        return message

    }

    // MARK: - PRIVATE READ/WRITE
    private func write(
        _ buffer: [UInt8],
        maxLength len: Int,
        timeout: TimeInterval = 1.0,
        enforceDeadline: Bool = false
    ) -> Int {
        guard len > 0 else { return 0 }

        var written = 0
        let start = Date()
        while self.connected == true && written < len {
            if enforceDeadline && Date().timeIntervalSince(start) >= timeout {
                break
            }

            guard let available = try? socket?.wait(for: .write, timeout: timeout) else {
                break
            }
            guard available else { continue }

            let remaining = len - written
            let n: Int = buffer.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return 0 }
                let ptr = base.advanced(by: written)
                return (try? socket?.write(ptr, size: remaining)) ?? 0
            }

            if n <= 0 {
                break
            }

            written += n
        }

        return written
    }

    private func readExactly(
        size: Int,
        timeout: TimeInterval = 1.0,
        enforceDeadline: Bool = false
    ) throws -> Data {
        guard let socket = socket else {
            throw Socket.Error(errno: -1)
        }

        var buffer = Data()
        buffer.reserveCapacity(size)
        let start = Date()

        while buffer.count < size {
            if enforceDeadline && Date().timeIntervalSince(start) >= timeout {
                throw P7SocketError.readFailed("Timed out while reading data")
            }

            // Vérifie la connexion de façon thread-safe
            guard connected else { throw Socket.Error(errno: ECONNRESET) }

            // Attend que le socket soit lisible
            let available = try socket.wait(for: .read, timeout: timeout)
            guard available else { continue }

            var temp = [UInt8](repeating: 0, count: size - buffer.count)
            let bytesRead: Int
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            bytesRead = temp.withUnsafeMutableBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return -1 }
                return Darwin.recv(socket.fileDescriptor, base, rawBuffer.count, 0)
            }
            #else
            bytesRead = temp.withUnsafeMutableBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return -1 }
                return Glibc.recv(socket.fileDescriptor, base, rawBuffer.count, 0)
            }
            #endif

            if bytesRead == 0 {
                // Socket fermé proprement
                throw Socket.Error(errno: ECONNRESET)
            } else if bytesRead < 0 {
                // Vérifie si c’est une interruption ou un EAGAIN
                if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
                    continue // réessaye
                } else {
                    throw Socket.Error(errno: errno)
                }
            }

            buffer.append(temp, count: bytesRead)
        }

        return buffer
    }

    // MARK: - OOB DATA
    /// Reads a raw out-of-band (OOB) data blob from the wire.
    ///
    /// OOB transfers share the same length-prefixed framing and session
    /// encryption/compression/checksum as regular messages but carry opaque
    /// `Data` rather than a `P7Message`.  Used for file transfers.
    ///
    /// - Parameter timeout: Per-read I/O timeout in seconds.
    /// - Returns: Decrypted, decompressed payload.
    /// - Throws: `P7SocketError.readFailed` on any I/O or integrity error.
    public func readOOB(timeout: TimeInterval = 1.0) throws -> Data {
        let lengthData = try readExactly(size: 4, timeout: timeout, enforceDeadline: true)

        guard let messageLength = Data(lengthData).uint32 else {
            Logger.error("Cannot read message length")
            throw P7SocketError.readFailed("Cannot read message length")
        }

        guard messageLength <= Self.maxMessageSize else {
            Logger.error("OOB message length \(messageLength) exceeds maximum \(Self.maxMessageSize)")
            throw P7SocketError.readFailed("OOB message too large: \(messageLength) bytes")
        }

        var messageData = try self.readExactly(size: Int(messageLength), timeout: timeout, enforceDeadline: true)
        let originalPayload = messageData

        if self.encryptionEnabled {
            messageData = try self.sslCipher.decrypt(data: messageData)
        }

        if self.compressionEnabled {
            messageData = try self.decompress(messageData)
        }

        if self.checksumEnabled {
            let remoteChecksum = try readExactly(size: checksumLength(self.digest.type), timeout: timeout, enforceDeadline: true)
            let localChecksum = try checksumData(originalPayload)

            if localChecksum != remoteChecksum {
                let errorMessage = "Checksum failed"
                Logger.error(errorMessage)
                throw P7SocketError.readFailed(errorMessage)
            }
        }

        return messageData
    }

    /// Sends a raw out-of-band (OOB) data blob over the wire.
    ///
    /// The data is compressed and encrypted according to the current session
    /// parameters and framed with a 4-byte big-endian length prefix.
    ///
    /// - Parameters:
    ///   - data: Raw payload to send (e.g. a file chunk).
    ///   - timeout: Per-write I/O timeout in seconds.
    /// - Throws: `P7SocketError.writeFailed` if the socket write fails.
    public func writeOOB(data: Data, timeout: TimeInterval = 1.0) throws {
        guard connected else {
            throw P7SocketError.readFailed("Not connected")
        }

        guard serialization == .BINARY else {
            throw P7SocketError.readFailed("Not binary serialization")
        }

        var messageData = data
        let originalData = messageData

        // deflate
        if self.compressionEnabled {
            messageData = try self.compress(messageData)
        }

        // encryption
        if self.encryptionEnabled {
            messageData = try self.sslCipher.encrypt(data: messageData)
        }

        // SECURITY (FINDING_P_008): compute length AFTER compression/encryption
        var lengthData = Data()
        lengthData.append(uint32: UInt32(messageData.count))

        let wroteLength = self.write(Array(lengthData), maxLength: lengthData.count, timeout: timeout, enforceDeadline: true)
        guard wroteLength == lengthData.count else {
            throw P7SocketError.writeFailed("Cannot write OOB length")
        }

        let payloadBytes = Array(messageData)
        let wrotePayload = self.write(payloadBytes, maxLength: payloadBytes.count, timeout: timeout, enforceDeadline: true)
        guard wrotePayload == payloadBytes.count else {
            throw P7SocketError.writeFailed("Cannot write OOB payload")
        }

        // checksum
        if self.checksumEnabled {
            let c = try self.checksumData(messageData)

            let wroteChecksum = self.write(Array(c), maxLength: self.checksumLength(self.digest.type), timeout: timeout, enforceDeadline: true)
            guard wroteChecksum == self.checksumLength(self.digest.type) else {
                throw P7SocketError.writeFailed("Cannot write OOB checksum")
            }
        }
    }

    // MARK: - Handshake
    private func connectHandshake() throws {
        var serverCipher: P7Socket.CipherType?
        var serverChecksum: P7Socket.Checksum?
        var serverCompression: P7Socket.Compression?

        var message = P7Message(withName: "p7.handshake.client_handshake", spec: self.spec)
        message.addParameter(field: "p7.handshake.version", value: self.spec.builtinProtocolVersion ?? "1.2")
        message.addParameter(field: "p7.handshake.protocol.name", value: "Wired")
        message.addParameter(field: "p7.handshake.protocol.version", value: "3.0")

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

        let response = try self.readMessage()

        if response.name != "p7.handshake.server_handshake" {
            let message = "Handshake Failed: Unexpected message \(response.name ?? "unknown") instead of p7.handshake.server_handshake"
            Logger.error(message)
            throw P7SocketError.handshakeFailed(message)
        }

        guard let p7Version = response.string(forField: "p7.handshake.version") else {
            let message = "Handshake Failed: Built-in protocol version field is missing (p7.handshake.version)"
            Logger.error(message)
            throw P7SocketError.handshakeFailed(message)
        }

        if p7Version != spec.builtinProtocolVersion {
            let message = "Handshake Failed: Local version is \(p7Version) but remote version is \(spec.builtinProtocolVersion!)"
            Logger.error(message)
            throw P7SocketError.handshakeFailed(message)
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
                throw P7SocketError.handshakeFailed("Compression configure failed")
            }

            if serverCipher != self.cipherType {
                throw P7SocketError.handshakeFailed("Cipher configure failed")
            }

            if serverChecksum != self.checksum {
                throw P7SocketError.handshakeFailed("Checksum configure failed")
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
    }

    private func acceptHandshake(timeout: Int, compression: Compression, cipher: CipherType, checksum: Checksum) throws {
        var clientCipher: P7Socket.CipherType       = .NONE
        var clientChecksum: P7Socket.Checksum       = .NONE
        var clientCompression: P7Socket.Compression = .NONE

        self.compression = normalizedCompression(compression)
        self.compressionFallback = normalizedCompression(self.compressionFallback)
        self.cipherType = cipher
        self.checksum = checksum

        // client handshake message (with deadline to prevent thread-pool exhaustion)
        let response = try self.readMessage(timeout: P7Socket.handshakeTimeout, enforceDeadline: true)

        if response.name != "p7.handshake.client_handshake" {
            let message = "Message should be 'p7.handshake.client_handshake', not '\(response.name ?? "unknown")'"
            Logger.error(message)
            throw P7SocketError.handshakeFailed(message)
        }

        // hadshake version
        guard let version = response.string(forField: "p7.handshake.version") else {
            let message = "Message has no 'p7.handshake.version', field"
            Logger.error(message)
            throw P7SocketError.handshakeFailed(message)
        }

        if version != self.spec.builtinProtocolVersion {
            let message = "Remote P7 protocol \(version) is not compatible"
            Logger.error(message)
            throw P7SocketError.handshakeFailed(message)
        }

        // protocol compatibility check
        guard let remoteName = response.string(forField: "p7.handshake.protocol.name") else {
            let message = "Message has no 'p7.handshake.protocol.name', field"
            Logger.error(message)
            throw P7SocketError.handshakeFailed(message)
        }

        guard let remoteVersion = response.string(forField: "p7.handshake.protocol.version") else {
            let message = "Message has no 'p7.handshake.protocol.version', field"
            Logger.error(message)
            throw P7SocketError.handshakeFailed(message)
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

            // cipher
            if self.cipherType.contains(clientCipher) {
                self.cipherType = clientCipher
            } else if clientCipher == .NONE {
                // Client explicitly requested no encryption but server requires it.
                // Reject with a clear error instead of silently upgrading the cipher.
                let msg = "Server requires encryption but client requested NONE. Please configure your client to use encryption."
                Logger.error(msg)
                throw P7SocketError.handshakeFailed(msg)
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
            throw P7SocketError.writeFailed()
        }

        let acknowledge = try self.readMessage(timeout: P7Socket.handshakeTimeout, enforceDeadline: true)

        if acknowledge.name != "p7.handshake.acknowledge" {
            let message = "Message should be 'p7.handshake.acknowledge', not '\(response.name ?? "unknown")'"
            Logger.error(message)
            throw P7SocketError.handshakeFailed(message)
        }

        if let remoteCompatibilityCheck = acknowledge.bool(forField: "p7.handshake.compatibility_check") {
            self.remoteCompatibilityCheck = remoteCompatibilityCheck
        } else {
            self.remoteCompatibilityCheck = false
        }
    }

    // MARK: - KEY EXCHANGE
    // P7 v1.2 key exchange flow (client side):
    //   1. Receive server_key {public_key}
    //   2. Setup ECDH cipher from server public key
    //   3. Send username_request {cipher.key, encrypted username}
    //   4. Receive server_challenge {encrypted stored_salt}
    //   5. Derive base_hash: SHA256(stored_salt || passwordData) if salt present, else passwordData
    //   6. Generate session_salt (32 random bytes)
    //   7. Compute saltedPasswordData = SHA256(session_salt || base_hash)
    //   8. Send client_key {ECDSA signature over saltedPasswordData+serverKey, session_salt}
    //   9. Receive acknowledge, verify server signature, derive final session keys
    private func connectKeyExchange() throws {
        self.ecdh = ECDH()
        self.digest = Digest(type: .SHA2_256)

        if self.ecdh == nil {
            let message = "ECDH Public key cannot be created"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }

        // Step 1: receive server_key
        let serverKeyMsg = try self.readMessage()
        if serverKeyMsg.name != "p7.encryption.server_key" {
            let message = "Message should be 'p7.encryption.server_key', not '\(serverKeyMsg.name ?? "unknown")'"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        guard let serverPublicKey = serverKeyMsg.data(forField: "p7.encryption.public_key") else {
            let message = "Message has no 'p7.encryption.public_key' field"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }

        // SECURITY (A_009): TOFU — verify server identity if provided
        if let trustHandler = self.serverTrustHandler,
           let identityKeyData = serverKeyMsg.data(forField: "p7.encryption.server_identity_key") {
            let strictIdentity = serverKeyMsg.bool(forField: "p7.encryption.strict_identity") ?? true
            let fp = ServerIdentity.computeFingerprint(identityKeyData)

            // Verify the identity signature over the ephemeral ECDH public key
            if let sigData = serverKeyMsg.data(forField: "p7.encryption.server_identity_sig") {
                guard let identityPubKey = try? P256.Signing.PublicKey(rawRepresentation: identityKeyData),
                      let ecdsaSig = try? P256.Signing.ECDSASignature(rawRepresentation: sigData),
                      identityPubKey.isValidSignature(ecdsaSig, for: serverPublicKey) else {
                    let message = "Server identity signature verification failed — possible MITM"
                    Logger.error(message)
                    throw P7SocketError.keyExchangeFailed(message)
                }
            }

            // Delegate trust decision to caller (TOFU store lookup)
            if !trustHandler(fp, false, strictIdentity) {
                let message = "Server identity rejected by trust handler (fingerprint: \(fp))"
                Logger.error(message)
                throw P7SocketError.keyExchangeFailed(message)
            }
        }

        // Step 2: setup cipher from ECDH shared secret
        guard let serverSharedSecret = self.ecdh.computeSecret(withPublicKey: serverPublicKey) else {
            let message = "Cannot compute shared secret"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        guard let ecdhSaltData = serverSharedSecret.data(using: .utf8),
              let (derivedKey, derivedIV) = self.ecdh.derivedKey(withSalt: ecdhSaltData,
                                                                  andIVofLength: Cipher.IVlength(forCipher: self.cipherType)) else {
            let message = "Cannot derive key from shared secret"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        do {
            self.sslCipher = try Cipher(cipher: self.cipherType, keyData: derivedKey, iv: derivedIV)
        } catch let error {
            let message = "Cipher cannot be created: \(error)"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }

        if self.password == nil || self.password?.isEmpty == true {
            self.password = "".sha256()
        } else {
            self.password = self.password.sha256()
        }
        let passwordData = self.password.data(using: .utf8)!

        guard let ecdsa = ECDSA(privateKey: derivedKey) else {
            let message = "Cannot init ECDSA"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }

        // Step 3: send username_request {cipher.key, encrypted username}
        guard var clientPublicKey = self.ecdh.publicKeyData() else {
            let message = "Cannot read client public key"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        guard let usernameBytes = self.username.data(using: .utf8),
              let encryptedUsername = try? self.sslCipher.encrypt(data: usernameBytes) else {
            let message = "Cannot encrypt username"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        clientPublicKey.append(ecdsa.publicKey.rawRepresentation)

        let usernameRequest = P7Message(withName: "p7.encryption.username_request", spec: self.spec)
        usernameRequest.addParameter(field: "p7.encryption.cipher.key", value: clientPublicKey.base64EncodedData())
        usernameRequest.addParameter(field: "p7.encryption.username", value: encryptedUsername)
        _ = self.write(usernameRequest)

        // Step 4: receive server_challenge {encrypted stored_salt}
        let challengeMsg = try self.readMessage()
        if challengeMsg.name != "p7.encryption.server_challenge" {
            let message = "Message should be 'p7.encryption.server_challenge', not '\(challengeMsg.name ?? "unknown")'"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }

        // Step 5: derive base_hash
        // If server provided a per-user stored_salt, the expected stored hash is SHA256(storedSalt || SHA256(plain)).
        // We replicate that derivation so both sides produce the same proof value.
        let baseHashData: Data
        if let encryptedStoredSalt = challengeMsg.data(forField: "p7.encryption.stored_salt"),
           let storedSaltData = try? self.sslCipher.decrypt(data: encryptedStoredSalt),
           !storedSaltData.isEmpty {
            var combined = storedSaltData
            combined.append(passwordData)
            baseHashData = combined.sha256().toHexString().data(using: .utf8)!
        } else {
            baseHashData = passwordData
        }

        // Step 6-7: generate session_salt and derive saltedPasswordData
        var rng = SystemRandomNumberGenerator()
        let sessionSalt = Data((0..<32).map { _ in UInt8.random(in: 0...255, using: &rng) })

        var saltedInput = sessionSalt
        saltedInput.append(baseHashData)
        let saltedPasswordData = saltedInput.sha256().toHexString().data(using: .utf8)!

        var clientPassword1 = saltedPasswordData
        clientPassword1.append(serverPublicKey)
        clientPassword1 = clientPassword1.sha256().toHexString().data(using: .utf8)!

        var clientPassword2 = serverPublicKey
        clientPassword2.append(saltedPasswordData)
        clientPassword2 = clientPassword2.sha256().toHexString().data(using: .utf8)!

        // Step 8: send client_key {signature, session_salt}
        guard let passwordSignature = ecdsa.sign(data: clientPassword1) else {
            let message = "Cannot sign client password"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        let clientKeyMsg = P7Message(withName: "p7.encryption.client_key", spec: self.spec)
        clientKeyMsg.addParameter(field: "p7.encryption.client_password", value: passwordSignature)
        clientKeyMsg.addParameter(field: "p7.encryption.password_salt", value: sessionSalt)
        _ = self.write(clientKeyMsg)

        self.digest = Digest(type: self.checksum, key: derivedKey.hexEncodedString())

        // Step 9: receive acknowledge, verify server signature
        let acknowledgeMsg = try self.readMessage()
        if acknowledgeMsg.name == "p7.encryption.authentication_error" {
            let message = "Authentication failed for '\(self.username)'"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        if acknowledgeMsg.name != "p7.encryption.acknowledge" {
            let message = "Message should be 'p7.encryption.acknowledge', not '\(acknowledgeMsg.name ?? "unknown")'"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        guard let serverPasswordSignature = acknowledgeMsg.data(forField: "p7.encryption.server_password") else {
            let message = "Message has no 'p7.encryption.server_password' field"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        if !ecdsa.verify(data: clientPassword2, withSignature: serverPasswordSignature) {
            let message = "Server password mismatch for '\(self.username)' during key exchange"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }

        // Derive final session keys from clientPassword2
        guard let (derivedKey2, derivedIV2) = self.ecdh.derivedKey(withSalt: clientPassword2,
                                                                     andIVofLength: Cipher.IVlength(forCipher: self.cipherType)) else {
            let message = "Cannot derive final session key"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        self.digest = Digest(type: self.checksum, key: derivedKey2.hexEncodedString())
        do {
            self.sslCipher = try Cipher(cipher: self.cipherType, keyData: derivedKey2, iv: derivedIV2)
        } catch let error {
            let message = "Cipher cannot be created: \(error)"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        self.encryptionEnabled = true
    }

    // P7 v1.2 key exchange flow (server side):
    //   1. Send server_key {public_key}
    //   2. Receive username_request {cipher.key, encrypted username} — setup ECDH cipher
    //   3. Look up per-user stored_salt; send server_challenge {encrypted stored_salt}
    //   4. Receive client_key {ECDSA signature, session_salt}
    //   5. Derive base_hash (mirror client): SHA256(storedSalt || passwordData) if salt present
    //   6. Derive saltedPasswordData = SHA256(session_salt || base_hash), verify ECDSA
    //   7. Send acknowledge {server ECDSA signature over reversed proof}, derive final session keys
    private func acceptKeyExchange(timeout: Int) throws {
        // Step 1: send server_key
        self.ecdh = ECDH()
        self.digest = Digest(type: .SHA2_256)

        if self.ecdh == nil {
            let message = "Missing ECDH key"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        guard let serverPublicKey = self.ecdh.publicKeyData() else {
            let message = "Failed to generate ECDH public key"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        let serverKeyMsg = P7Message(withName: "p7.encryption.server_key", spec: self.spec)
        serverKeyMsg.addParameter(field: "p7.encryption.public_key", value: serverPublicKey)

        // SECURITY (A_009): Attach persistent identity key + signature for TOFU
        if let identity = self.identityProvider {
            serverKeyMsg.addParameter(field: "p7.encryption.server_identity_key",
                                      value: identity.identityPublicKey)
            if let sig = identity.signWithIdentity(data: serverPublicKey) {
                serverKeyMsg.addParameter(field: "p7.encryption.server_identity_sig", value: sig)
            }
            serverKeyMsg.addParameter(field: "p7.encryption.strict_identity",
                                      value: identity.strictIdentity)
        }

        if !self.write(serverKeyMsg) {
            let message = "Failed to send server public key"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }

        // Step 2: receive username_request {cipher.key, encrypted username}
        let usernameRequestMsg = try self.readMessage(timeout: P7Socket.handshakeTimeout, enforceDeadline: true)
        if usernameRequestMsg.name != "p7.encryption.username_request" {
            let message = "Message should be 'p7.encryption.username_request', not '\(usernameRequestMsg.name ?? "unknown")'"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        guard let combinedBase64Keys = usernameRequestMsg.data(forField: "p7.encryption.cipher.key"),
              let combinedKeys = Data(base64Encoded: combinedBase64Keys) else {
            let message = "Client public key not found in username_request"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        let clientPublicKey = combinedKeys.dropLast(64)
        if clientPublicKey.count != 132 {
            let message = "Invalid public key length in username_request"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        let publicSigningKey = combinedKeys.dropFirst(132)
        if publicSigningKey.count != 64 {
            let message = "Invalid signing key length in username_request"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }

        // Setup ECDH cipher from client's public key (needed to decrypt username)
        guard let serverSharedSecret = self.ecdh.computeSecret(withPublicKey: clientPublicKey) else {
            let message = "Cannot compute shared secret"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        guard let ecdhSaltData = serverSharedSecret.data(using: .utf8),
              let (derivedKey, derivedIV) = self.ecdh.derivedKey(withSalt: ecdhSaltData,
                                                                  andIVofLength: Cipher.IVlength(forCipher: self.cipherType)) else {
            let message = "Cannot derive key from shared secret"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        do {
            self.sslCipher = try Cipher(cipher: self.cipherType, keyData: derivedKey, iv: derivedIV)
        } catch let error {
            let message = "Cipher cannot be created: \(error)"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        self.digest = Digest(type: self.checksum, key: derivedKey.hexEncodedString())

        // Decrypt username
        guard let encryptedUsernameData = usernameRequestMsg.data(forField: "p7.encryption.username"),
              let usernameData = try? self.sslCipher.decrypt(data: encryptedUsernameData),
              let username = usernameData.stringUTF8 else {
            let message = "Cannot decrypt username from username_request"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        self.username = username

        // Look up password and per-user stored salt
        if self.passwordProvider != nil {
            if let password = self.passwordProvider?.passwordForUsername(username: self.username) {
                self.password = password
            } else {
                // SECURITY (FINDING_A_014): Use dummy password to prevent username enumeration
                // via timing differences. Key exchange proceeds and fails at ECDSA verification,
                // matching the timing of a valid user with wrong password.
                self.password = UUID().uuidString.sha256()
            }
        } else {
            self.password = "".sha256()
        }
        // Per-user stored salt for base_hash derivation (nil = not yet assigned)
        let storedSalt = self.passwordProvider?.passwordSaltForUsername(username: self.username)

        // Step 3: send server_challenge {encrypted stored_salt}
        let storedSaltBytes: Data = storedSalt.flatMap { $0.isEmpty ? nil : $0.data(using: .utf8) } ?? Data()
        guard let encryptedStoredSalt = try? self.sslCipher.encrypt(data: storedSaltBytes) else {
            let message = "Cannot encrypt stored_salt for server_challenge"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        let challengeMsg = P7Message(withName: "p7.encryption.server_challenge", spec: self.spec)
        challengeMsg.addParameter(field: "p7.encryption.stored_salt", value: encryptedStoredSalt)
        if !self.write(challengeMsg) {
            let message = "Failed to send server_challenge"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }

        // Step 4: receive client_key {signature, session_salt}
        let clientKeyMsg = try self.readMessage(timeout: P7Socket.handshakeTimeout, enforceDeadline: true)
        if clientKeyMsg.name != "p7.encryption.client_key" {
            let message = "Message should be 'p7.encryption.client_key', not '\(clientKeyMsg.name ?? "unknown")'"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        guard let clientPasswordSignature = clientKeyMsg.data(forField: "p7.encryption.client_password") else {
            let message = "Message has no 'p7.encryption.client_password' field"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }

        // Step 5-6: derive base_hash then saltedPasswordData (mirror client derivation)
        let passwordData = self.password.data(using: .utf8)!
        let baseHashData: Data
        if !storedSaltBytes.isEmpty {
            // Mirror: base_hash = SHA256(storedSaltBytes || SHA256(plain).utf8)
            var combined = storedSaltBytes
            combined.append(passwordData)
            baseHashData = combined.sha256().toHexString().data(using: .utf8)!
        } else {
            baseHashData = passwordData
        }

        let saltedPasswordData: Data
        if let sessionSalt = clientKeyMsg.data(forField: "p7.encryption.password_salt") {
            var saltedInput = sessionSalt
            saltedInput.append(baseHashData)
            saltedPasswordData = saltedInput.sha256().toHexString().data(using: .utf8)!
        } else {
            saltedPasswordData = baseHashData
        }

        var serverPassword1Data = saltedPasswordData
        serverPassword1Data.append(serverPublicKey)
        serverPassword1Data = serverPassword1Data.sha256().toHexString().data(using: .utf8)!

        var serverPassword2Data = serverPublicKey
        serverPassword2Data.append(saltedPasswordData)
        serverPassword2Data = serverPassword2Data.sha256().toHexString().data(using: .utf8)!

        // Verify client ECDSA signature
        guard let ecdsa = ECDSA(publicKey: publicSigningKey) else {
            let message = "Cannot init ECDSA with public signing key"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        if !ecdsa.verify(data: serverPassword1Data, withSignature: clientPasswordSignature) {
            let message = "Password mismatch for '\(self.username)' during key exchange, ECDSA validation failed"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }

        // Step 7: send acknowledge {server ECDSA signature}
        guard let ecdsa2 = ECDSA(privateKey: derivedKey) else {
            let message = "Cannot init ECDSA with private signing key"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        guard let serverPasswordSignature = ecdsa2.sign(data: serverPassword2Data) else {
            let message = "Cannot sign server password"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        let acknowledgeMsg = P7Message(withName: "p7.encryption.acknowledge", spec: self.spec)
        acknowledgeMsg.addParameter(field: "p7.encryption.server_password", value: serverPasswordSignature)
        if !self.write(acknowledgeMsg) {
            let message = "Cannot write acknowledge message"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }

        // Derive final session keys from serverPassword2Data
        guard let (derivedKey2, derivedIV2) = self.ecdh.derivedKey(withSalt: serverPassword2Data,
                                                                     andIVofLength: Cipher.IVlength(forCipher: self.cipherType)) else {
            let message = "Cannot derive final session key"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        self.digest = Digest(type: self.checksum, key: derivedKey2.hexEncodedString())
        do {
            self.sslCipher = try Cipher(cipher: self.cipherType, keyData: derivedKey2, iv: derivedIV2)
        } catch let error {
            let message = "Cipher cannot be created: \(error)"
            Logger.error(message)
            throw P7SocketError.keyExchangeFailed(message)
        }
        self.encryptionEnabled = true
    }

    // MARK: - COMPATIBILITY CHECK
    private func sendCompatibilityCheck() throws {
        let message = P7Message(withName: "p7.compatibility_check.specification", spec: self.spec)

        message.addParameter(field: "p7.compatibility_check.specification", value: self.spec.xml!)

        _ = self.write(message)

        let response = try self.readMessage()

        if response.name != "p7.compatibility_check.status" {
            let message = "Message should be 'p7.compatibility_check.status', not '\(response.name ?? "unknown")'"
            Logger.error(message)
            throw P7SocketError.remoteCompatibilityFailed(message)
        }

        guard let status = response.bool(forField: "p7.compatibility_check.status") else {
            let message = "Message has no 'p7.compatibility_check.status' field"
            Logger.error(message)
            throw P7SocketError.remoteCompatibilityFailed(message)
        }

        if status == false {
            let message = "Remote protocol '\(self.remoteName!) \(self.remoteVersion!)' is not compatible with local protocol '\(self.spec.protocolName!) \(self.spec.protocolVersion!)'"
            Logger.error(message)
            throw P7SocketError.remoteCompatibilityFailed(message)
        }
    }

    private func receiveCompatibilityCheck() throws {
        let response = try self.readMessage(timeout: P7Socket.handshakeTimeout, enforceDeadline: true)

        if response.name != "p7.compatibility_check.specification" {
            let message = "Message should be 'p7.compatibility_check.specification', not '\(response.name ?? "unknown")'"
            Logger.error(message)
            throw P7SocketError.localCompatibilityFailed(message)
        }

        // Validate the remote spec against our local protocol
        let compatible = self.spec.isCompatibleWithProtocol(withName: self.remoteName, version: self.remoteVersion)

        let reply = P7Message(withName: "p7.compatibility_check.status", spec: self.spec)
        reply.addParameter(field: "p7.compatibility_check.status", value: compatible)
        _ = self.write(reply)

        if !compatible {
            // swiftlint:disable:next line_length
            let message = "Local protocol '\(self.spec.protocolName ?? "unknown") \(self.spec.protocolVersion ?? "unknown")' is not compatible with remote protocol '\(self.remoteName ?? "unknown") \(self.remoteVersion ?? "unknown")'"
            Logger.error(message)
            throw P7SocketError.localCompatibilityFailed(message)
        }
    }

    // MARK: - CHECKSUM
    private func checksumData(_ data: Data) throws -> Data {
        if self.digest != nil {
            return try self.digest.authenticate(data: data)
        }

        return try Digest(type: .SHA2_256).authenticate(data: data)
    }

    private func configureChecksum() {
        // AEAD already authenticates; checksum here is redundant (and currently over ciphertext)
        if cipherProvidesIntegrity {
            self.checksumEnabled = false
        } else {
            self.checksumEnabled = (self.checksum != .NONE)
        }
    }

    /// Returns the byte length of the authentication tag for the given checksum type.
    ///
    /// - Parameter type: The negotiated `Checksum` variant.
    /// - Returns: Tag length in bytes (e.g. 32 for SHA2-256, 48 for SHA2-384), or 0 for `.NONE`.
    public func checksumLength(_ type: Checksum) -> Int {
        if type == .SHA2_256 {
            sha2_256DigestLength

        } else if type == .SHA2_384 {
            sha2_384DigestLength

        } else if type == .SHA3_256 {
            sha3_256DigestLength

        } else if type == .SHA3_384 {
            sha3_384DigestLength

        } else if type == .HMAC_256 {
            hmac_256DigestLength

        } else if type == .HMAC_384 {
            hmac_384DigestLength

        } else {
            0
        }
    }

    // MARK: - COMPRESSION
    private func configureCompression() {
        if self.compression != .NONE {
            self.compressionEnabled = true

        } else {
            self.compressionEnabled = false
        }
    }

    private func compress(_ data: Data) throws -> Data {
        if compression == .DEFLATE {
            if let out = data.deflate() {
                return out
            }
        } else if compression == .LZFSE {
            if let out = data.compress(withAlgorithm: .lzfse) {
                return out
            }

        } else if compression == .LZ4 {
            return encodeLZ4StoreFrame(data)

        } else if compression == .NONE {
            return data
        }
        Logger.error("Compression encode failed for \(compression). input=\(compressionPreview(data))")
        throw P7SocketError.inflateError
    }

    private func decompress(_ data: Data) throws -> Data {
        if compression == .DEFLATE {
            if let out = data.inflate() {
                return out
            }
        } else if compression == .LZFSE {
            if let out = data.decompress(withAlgorithm: .lzfse) {
                return out
            }

        } else if compression == .LZ4 {
            if let out = decodeLZ4StoreFrame(data) {
                return out
            }
            if let out = data.decompress(withAlgorithm: .lz4) {
                return out
            }

        } else if compression == .NONE {
            return data
        }
        Logger.error("Compression decode failed for \(compression). input=\(compressionPreview(data))")
        throw P7SocketError.deflateError
    }

    // MARK: -

    private func handleConnectionError(_ error: Error) {
        if let socketError = error as? Socket.Error {
            self.errors.append(
                WiredError(withTitle: "Socket Error",
                           message: socketError.description)
            )
            Logger.error(socketError.description)
        } else {
            self.errors.append(
                WiredError(withTitle: "Connection Error",
                           message: error.localizedDescription)
            )
            Logger.error(error.localizedDescription)
        }
    }

    // MARK: -

    /// Returns the remote peer's IP address as a string (IPv4 or IPv6).
    ///
    /// - Returns: Dotted-decimal IPv4 or colon-separated IPv6 string, or `nil` on failure.
    public func getClientIP() -> String? {
        if let fileDescriptor = self.socket?.fileDescriptor {
            return peerIPAddress(socketFD: fileDescriptor)
        }

        return nil
    }

    /// Returns the remote peer's hostname via reverse DNS, falling back to the IP address.
    ///
    /// - Returns: Hostname string, or `nil` on failure.
    public func getClientHostname() -> String? {
        if let fileDescriptor = self.socket?.fileDescriptor {
            return peerIPAddress(socketFD: fileDescriptor)
        }

        return nil
    }

    /// Returns the local socket address as a numeric IP string.
    ///
    /// - Returns: Numeric IP of the local end of the connection, or `nil` on failure.
    public func clientAddress() -> String? {
        var addresString: String?
        var address = sockaddr_in()
        var len = socklen_t(MemoryLayout.size(ofValue: address))
        // let ptr = UnsafeMutableRawPointer(&address).assumingMemoryBound(to: sockaddr.self)

         withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                if let socket {
                    if getsockname(socket.fileDescriptor, ptr, &len) == 0 {
                        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                        if getnameinfo(ptr, len, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                            addresString = String(cString: hostBuffer)
                        }
                    }
                }
            }
        }

        return addresString
    }

    private func peerIPAddress(socketFD: Int32) -> String? {
        var addr = sockaddr_storage()
        var len = socklen_t(MemoryLayout<sockaddr_storage>.size)

        let result = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getpeername(socketFD, $0, &len)
            }
        }

        guard result == 0 else {
            return nil
        }

        if addr.ss_family == sa_family_t(AF_INET) {
            var addr4 = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            }

            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &addr4.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
            return String(cString: buffer)
        }

        if addr.ss_family == sa_family_t(AF_INET6) {
            var addr6 = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
            }

            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            inet_ntop(AF_INET6, &addr6.sin6_addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
            return String(cString: buffer)
        }

        return nil
    }

    private func peerHostInfo(socketFD: Int32) -> String? {
        var addr = sockaddr_storage()
        var len = socklen_t(MemoryLayout<sockaddr_storage>.size)

        let result = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getpeername(socketFD, $0, &len)
            }
        }

        guard result == 0 else {
            return nil
        }

        // Buffer hostname / service
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var serv = [CChar](repeating: 0, count: Int(NI_MAXSERV))

        let flags = NI_NAMEREQD // force le reverse DNS

        let nameResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo(
                    $0,
                    len,
                    &host,
                    socklen_t(host.count),
                    &serv,
                    socklen_t(serv.count),
                    flags
                )
            }
        }

        let hostname = (nameResult == 0) ? String(cString: host) : nil

        return hostname
    }
}
