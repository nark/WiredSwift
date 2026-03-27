//
//  P7Cipher.swift
//  Wired 3
//
//  Created by Rafael Warnault on 25/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

//
//  Cipher.swift
//  Wired 3
//
//  AEAD streaming nonces derived from handshake IV (p7.encryption.cipher.iv):
//   - AES-GCM / ChaCha20-Poly1305 / XChaCha20-Poly1305:
//       nonce = nonceBase with last 8 bytes replaced by a monotonically increasing counter (big-endian)
//       output frame: [ciphertext][tag]  (nonce NOT transmitted per message)
//
//  Legacy kept intact:
//   - ECDH_AES256_SHA256: AES-256-CBC + PKCS7
//       output frame: [iv(16)][ciphertext]
//

import Foundation
import CryptoSwift

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// ----------------------
// Data extension
// ----------------------
extension Data {
    var bytes: [UInt8] { Array(self) }
}

// ----------------------
// Cipher
// ----------------------
/// Symmetric cipher used for P7 wire encryption after the ECDH handshake.
///
/// Supports AES-256-CBC (legacy), AES-128/256-GCM, ChaCha20-Poly1305, and
/// XChaCha20-Poly1305.  AEAD modes derive per-message nonces from the
/// handshake IV by replacing the last 8 bytes with a monotonically
/// increasing counter, so the IV must never be reused across sessions.
public final class Cipher {

    // MARK: - Errors
    /// Errors that can be thrown by `Cipher` operations.
    public enum CipherError: Error {
        /// The supplied key is not the expected length.
        case invalidKey
        /// The supplied nonce or IV is missing or has the wrong length.
        case invalidNonce
        /// The requested cipher suite is not supported.
        case unsupportedCipher
        /// Encryption of plaintext failed.
        case encryptionFailed
        /// Decryption or authentication-tag verification failed.
        case decryptionFailed
        /// The 64-bit message counter has wrapped around; the session must be rekeyed.
        case counterOverflow
    }

    // MARK: - Mode
    private enum Mode: Equatable {
        case aes256cbc
        case aes128gcm
        case aes256gcm
        case chacha20poly1305
        case xchacha20poly1305
    }

    // MARK: - Properties
    private let mode: Mode
    private let keyBytes: [UInt8]

    /// For AEAD modes only: nonceBase comes from handshake IV (p7.encryption.cipher.iv).
    private let nonceBase: [UInt8]?

    private var sendCounter: UInt64 = 0
    private var recvCounter: UInt64 = 0

    // MARK: - Constants
    private static let ecdhKeySize = 32
    private static let tagSize = 16

    // MARK: - Init
    /// Creates a `Cipher` instance for the given suite.
    ///
    /// - Parameters:
    ///   - cipher: The negotiated cipher suite (from the P7 handshake).
    ///   - keyData: 32-byte symmetric key derived from the ECDH shared secret.
    ///   - iv: Handshake IV (`p7.encryption.cipher.iv`).
    ///     Required for AEAD modes (12 bytes for GCM/ChaCha20, 24 bytes for
    ///     XChaCha20); ignored for legacy AES-256-CBC.
    /// - Throws: `CipherError.invalidKey` if `keyData` is not 32 bytes,
    ///   `CipherError.invalidNonce` if the IV is missing or has the wrong size
    ///   for an AEAD mode, or `CipherError.unsupportedCipher` for an unknown suite.
    public init(cipher: P7Socket.CipherType, keyData: Data, iv: Data?) throws {
        guard keyData.count == Self.ecdhKeySize else { throw CipherError.invalidKey }

        switch cipher {
        case .ECDH_AES256_SHA256:
            self.mode = .aes256cbc
            self.keyBytes = Array(keyData)
            self.nonceBase = nil

        case .ECDH_AES128_GCM:
            self.mode = .aes128gcm
            self.keyBytes = Array(keyData.prefix(16))
            self.nonceBase = try Self.requireNonceBase(iv, size: 12)

        case .ECDH_AES256_GCM:
            self.mode = .aes256gcm
            self.keyBytes = Array(keyData)
            self.nonceBase = try Self.requireNonceBase(iv, size: 12)

        case .ECDH_CHACHA20_POLY1305:
            self.mode = .chacha20poly1305
            self.keyBytes = Array(keyData)
            self.nonceBase = try Self.requireNonceBase(iv, size: 12)

        case .ECDH_XCHACHA20_POLY1305:
            self.mode = .xchacha20poly1305
            self.keyBytes = Array(keyData)
            self.nonceBase = try Self.requireNonceBase(iv, size: 24)

        default:
            throw CipherError.unsupportedCipher
        }
    }

    private static func requireNonceBase(_ iv: Data?, size: Int) throws -> [UInt8] {
        guard let iv else { throw CipherError.invalidNonce }
        let bytes = Array(iv)
        guard bytes.count == size else { throw CipherError.invalidNonce }
        return bytes
    }

    // MARK: - Counters
    /// Resets the send and receive nonce counters.
    ///
    /// Call this only when both sides agree to restart the counter (e.g.
    /// after rekeying).  The default resets both counters to zero.
    ///
    /// - Parameters:
    ///   - send: New value for the outgoing message counter.
    ///   - recv: New value for the incoming message counter.
    public func resetCounters(send: UInt64 = 0, recv: UInt64 = 0) {
        self.sendCounter = send
        self.recvCounter = recv
    }

    // MARK: - Nonce derivation (AEAD streaming)
    /// nonce = nonceBase with last 8 bytes replaced by counter (big-endian).
    private func makeNonce(counter: UInt64) throws -> [UInt8] {
        guard let nonceBase else { throw CipherError.invalidNonce }
        guard nonceBase.count == 12 || nonceBase.count == 24 else { throw CipherError.invalidNonce }

        var nonce = nonceBase
        let c = counter.bigEndian
        withUnsafeBytes(of: c) { raw in
            let start = nonce.count - 8
            nonce.replaceSubrange(start..<nonce.count, with: raw)
        }
        return nonce
    }

    private func nextSendNonce() throws -> [UInt8] {
        guard sendCounter != UInt64.max else { throw CipherError.counterOverflow }
        let n = try makeNonce(counter: sendCounter)
        sendCounter &+= 1
        return n
    }

    private func nextRecvNonce() throws -> [UInt8] {
        guard recvCounter != UInt64.max else { throw CipherError.counterOverflow }
        let n = try makeNonce(counter: recvCounter)
        recvCounter &+= 1
        return n
    }

    // MARK: - Encrypt
    /// Encrypts `data` using the configured cipher suite.
    ///
    /// Output framing:
    /// - Legacy AES-256-CBC: `[iv(16 B)][ciphertext]`
    /// - AEAD suites: `[ciphertext][tag(16 B)]`  (nonce is derived from the counter)
    ///
    /// - Parameters:
    ///   - data: Plaintext to encrypt.
    ///   - additionalData: Associated data authenticated but not encrypted (AEAD only).
    /// - Returns: Framed ciphertext as described above.
    /// - Throws: `CipherError` on key/nonce validation failure or underlying crypto error.
    public func encrypt(data: Data, additionalData: Data = Data()) throws -> Data {
        switch mode {

        case .aes256cbc:
            let iv = AES.randomIV(AES.blockSize)
            let aes = try AES(
                key: keyBytes,
                blockMode: CBC(iv: iv),
                padding: .pkcs7
            )
            let encrypted = try aes.encrypt(data.bytes)
            var out = Data()
            out.reserveCapacity(16 + encrypted.count)
            out.append(contentsOf: iv)
            out.append(contentsOf: encrypted)
            return out

        case .aes128gcm:
            guard keyBytes.count == 16 else { throw CipherError.invalidKey }
            let nonce = try nextSendNonce()
            return try sealAESGCM(plaintext: data, nonce: nonce, aad: additionalData)

        case .aes256gcm:
            guard keyBytes.count == 32 else { throw CipherError.invalidKey }
            let nonce = try nextSendNonce()
            return try sealAESGCM(plaintext: data, nonce: nonce, aad: additionalData)

        case .chacha20poly1305:
            guard keyBytes.count == 32 else { throw CipherError.invalidKey }
            let nonce = try nextSendNonce() // 12 bytes
            return try sealChaChaPoly(plaintext: data, keyBytes: keyBytes, nonce12: nonce, aad: additionalData)

        case .xchacha20poly1305:
            guard keyBytes.count == 32 else { throw CipherError.invalidKey }
            let nonce24 = try nextSendNonce() // 24 bytes
            return try sealXChaChaPoly(plaintext: data, keyBytes: keyBytes, nonce24: nonce24, aad: additionalData)
        }
    }

    // MARK: - Decrypt
    /// Decrypts `data` produced by `encrypt(data:additionalData:)`.
    ///
    /// - Parameters:
    ///   - data: Framed ciphertext as returned by `encrypt`.
    ///   - additionalData: Associated data that was authenticated during encryption (AEAD only).
    /// - Returns: Recovered plaintext.
    /// - Throws: `CipherError` on key/nonce validation failure, authentication-tag mismatch,
    ///   or underlying crypto error.
    public func decrypt(data: Data, additionalData: Data = Data()) throws -> Data {
        switch mode {

        case .aes256cbc:
            guard data.count >= AES.blockSize else { throw CipherError.decryptionFailed }
            let iv = data.prefix(AES.blockSize)
            let ciphertext = data.dropFirst(AES.blockSize)

            let aes = try AES(
                key: keyBytes,
                blockMode: CBC(iv: iv.bytes),
                padding: .pkcs7
            )
            let plaintext = try aes.decrypt(ciphertext.bytes)
            return Data(plaintext)

        case .aes128gcm:
            guard keyBytes.count == 16 else { throw CipherError.invalidKey }
            let nonce = try nextRecvNonce()
            return try openAESGCM(box: data, nonce: nonce, aad: additionalData)

        case .aes256gcm:
            guard keyBytes.count == 32 else { throw CipherError.invalidKey }
            let nonce = try nextRecvNonce()
            return try openAESGCM(box: data, nonce: nonce, aad: additionalData)

        case .chacha20poly1305:
            guard keyBytes.count == 32 else { throw CipherError.invalidKey }
            let nonce = try nextRecvNonce() // 12 bytes
            return try openChaChaPoly(box: data, keyBytes: keyBytes, nonce12: nonce, aad: additionalData)

        case .xchacha20poly1305:
            guard keyBytes.count == 32 else { throw CipherError.invalidKey }
            let nonce24 = try nextRecvNonce() // 24 bytes
            return try openXChaChaPoly(box: data, keyBytes: keyBytes, nonce24: nonce24, aad: additionalData)
        }
    }
}

// MARK: - Swift Crypto AEAD (AES.GCM / ChaChaPoly)

private extension Cipher {

    func sealAESGCM(plaintext: Data, nonce: [UInt8], aad: Data) throws -> Data {
        // nonce must be 12 bytes
        guard nonce.count == 12 else { throw CipherError.invalidNonce }
        let key = SymmetricKey(data: Data(keyBytes))
        let n = try AES.GCM.Nonce(data: Data(nonce))
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: n, authenticating: aad)

        var out = Data()
        out.reserveCapacity(sealed.ciphertext.count + sealed.tag.count)
        out.append(sealed.ciphertext)
        out.append(sealed.tag) // 16 bytes
        return out
    }

    func openAESGCM(box: Data, nonce: [UInt8], aad: Data) throws -> Data {
        guard nonce.count == 12 else { throw CipherError.invalidNonce }
        guard box.count >= Self.tagSize else { throw CipherError.invalidNonce }

        let key = SymmetricKey(data: Data(keyBytes))
        let n = try AES.GCM.Nonce(data: Data(nonce))

        let ciphertext = box.dropLast(Self.tagSize)
        let tag = box.suffix(Self.tagSize)

        let sealed = try AES.GCM.SealedBox(nonce: n, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealed, using: key, authenticating: aad)
    }

    func sealChaChaPoly(plaintext: Data, keyBytes: [UInt8], nonce12: [UInt8], aad: Data) throws -> Data {
        guard keyBytes.count == 32 else { throw CipherError.invalidKey }
        guard nonce12.count == 12 else { throw CipherError.invalidNonce }

        let key = SymmetricKey(data: Data(keyBytes))
        let n = try ChaChaPoly.Nonce(data: Data(nonce12))
        let sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: n, authenticating: aad)

        var out = Data()
        out.reserveCapacity(sealed.ciphertext.count + sealed.tag.count)
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    func openChaChaPoly(box: Data, keyBytes: [UInt8], nonce12: [UInt8], aad: Data) throws -> Data {
        guard keyBytes.count == 32 else { throw CipherError.invalidKey }
        guard nonce12.count == 12 else { throw CipherError.invalidNonce }
        guard box.count >= Self.tagSize else { throw CipherError.invalidNonce }

        let key = SymmetricKey(data: Data(keyBytes))
        let n = try ChaChaPoly.Nonce(data: Data(nonce12))

        let ciphertext = box.dropLast(Self.tagSize)
        let tag = box.suffix(Self.tagSize)

        let sealed = try ChaChaPoly.SealedBox(nonce: n, ciphertext: ciphertext, tag: tag)
        return try ChaChaPoly.open(sealed, using: key, authenticating: aad)
    }
}

// MARK: - XChaCha20-Poly1305 (HChaCha20 subkey + ChaChaPoly)

private extension Cipher {

    func sealXChaChaPoly(plaintext: Data, keyBytes: [UInt8], nonce24: [UInt8], aad: Data) throws -> Data {
        guard keyBytes.count == 32 else { throw CipherError.invalidKey }
        guard nonce24.count == 24 else { throw CipherError.invalidNonce }

        // subkey = HChaCha20(key, nonce[0..15])
        let subkeyBytes = HChaCha20.deriveKey(key: keyBytes, nonce16: Array(nonce24[0..<16]))

        // chacha nonce = 4 zero bytes + nonce[16..23]  (12 bytes)
        let nonce12: [UInt8] = [0, 0, 0, 0] + Array(nonce24[16..<24])

        return try sealChaChaPoly(plaintext: plaintext, keyBytes: subkeyBytes, nonce12: nonce12, aad: aad)
    }

    func openXChaChaPoly(box: Data, keyBytes: [UInt8], nonce24: [UInt8], aad: Data) throws -> Data {
        guard keyBytes.count == 32 else { throw CipherError.invalidKey }
        guard nonce24.count == 24 else { throw CipherError.invalidNonce }

        let subkeyBytes = HChaCha20.deriveKey(key: keyBytes, nonce16: Array(nonce24[0..<16]))
        let nonce12: [UInt8] = [0, 0, 0, 0] + Array(nonce24[16..<24])

        return try openChaChaPoly(box: box, keyBytes: subkeyBytes, nonce12: nonce12, aad: aad)
    }
}

// MARK: - HChaCha20 (pure Swift, fast enough, cross-platform)

private struct HChaCha20 {

    static func deriveKey(key: [UInt8], nonce16: [UInt8]) -> [UInt8] {
        precondition(key.count == 32)
        precondition(nonce16.count == 16)

        let constants: [UInt32] = [
            0x61707865, 0x3320646e,
            0x79622d32, 0x6b206574
        ]

        func u32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
            let chunk = Array(bytes)
            guard chunk.count == 4 else { return 0 }
            return UInt32(chunk[0]) |
                   (UInt32(chunk[1]) << 8) |
                   (UInt32(chunk[2]) << 16) |
                   (UInt32(chunk[3]) << 24)
        }

        var state: [UInt32] = [
            constants[0], constants[1], constants[2], constants[3],
            u32(key[0..<4]), u32(key[4..<8]),
            u32(key[8..<12]), u32(key[12..<16]),
            u32(key[16..<20]), u32(key[20..<24]),
            u32(key[24..<28]), u32(key[28..<32]),
            u32(nonce16[0..<4]), u32(nonce16[4..<8]),
            u32(nonce16[8..<12]), u32(nonce16[12..<16])
        ]

        @inline(__always) func rotl(_ v: UInt32, _ n: UInt32) -> UInt32 {
            (v << n) | (v >> (32 - n))
        }

        @inline(__always) func quarterRound(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
            state[a] &+= state[b]; state[d] ^= state[a]; state[d] = rotl(state[d], 16)
            state[c] &+= state[d]; state[b] ^= state[c]; state[b] = rotl(state[b], 12)
            state[a] &+= state[b]; state[d] ^= state[a]; state[d] = rotl(state[d], 8)
            state[c] &+= state[d]; state[b] ^= state[c]; state[b] = rotl(state[b], 7)
        }

        for _ in 0..<10 {
            // column rounds
            quarterRound(0, 4, 8, 12)
            quarterRound(1, 5, 9, 13)
            quarterRound(2, 6, 10, 14)
            quarterRound(3, 7, 11, 15)
            // diagonal rounds
            quarterRound(0, 5, 10, 15)
            quarterRound(1, 6, 11, 12)
            quarterRound(2, 7, 8, 13)
            quarterRound(3, 4, 9, 14)
        }

        var out = [UInt8]()
        out.reserveCapacity(32)

        for i in [0, 1, 2, 3, 12, 13, 14, 15] {
            let v = state[i].littleEndian
            out.append(UInt8(v & 0xff))
            out.append(UInt8((v >> 8) & 0xff))
            out.append(UInt8((v >> 16) & 0xff))
            out.append(UInt8((v >> 24) & 0xff))
        }
        return out
    }
}

// MARK: - Compatibility helpers (IVlength/randomIV)

public extension Cipher {

    /// Nominal IV/nonce sizes for handshake IV (p7.encryption.cipher.iv) and legacy IV lengths.
    static func IVlength(forCipher cipher: P7Socket.CipherType) -> Int {
        switch cipher {
        case .ECDH_AES256_SHA256:
            return 16
        case .ECDH_AES128_GCM,
             .ECDH_AES256_GCM,
             .ECDH_CHACHA20_POLY1305:
            return 12
        case .ECDH_XCHACHA20_POLY1305:
            return 24
        default:
            return 0
        }
    }

    /// Kept for compatibility with existing code. For AEAD streaming, IV MUST come from handshake.
    static func randomIV(forCipher cipher: P7Socket.CipherType) -> [UInt8]? {
        switch cipher {
        case .ECDH_AES256_SHA256:
            return AES.randomIV(IVlength(forCipher: cipher))
        default:
            // AEAD streaming: do not generate here; must be provided as p7.encryption.cipher.iv
            return nil
        }
    }
}
