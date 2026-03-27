//
//  Digest.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/04/2021.
//

import Foundation
import CryptoSwift

/// HMAC-based message authentication used on the P7 wire.
///
/// Wraps SHA-2/SHA-3 hashes and HMAC variants negotiated during the
/// P7 handshake.  For HMAC modes the `key` must be set to the hex-encoded
/// session key derived during key exchange.
public class Digest {
    /// The checksum algorithm negotiated for this session.
    public var type: P7Socket.Checksum
    /// Hex-encoded HMAC key; required when `type` is `.HMAC_256` or `.HMAC_384`.
    public var key: String?

    private var hmac: HMAC?

    enum DigestError: Error {
        case digestFailed(error: Error)
        case digestNotProperlyInitialized(message: String)
        case unsupportedDigest
    }

    /// Creates a `Digest` authenticator for the given checksum algorithm.
    ///
    /// - Parameters:
    ///   - type: The checksum variant to use.
    ///   - key: Hex-encoded key required for HMAC variants; ignored for plain hash variants.
    public init(type: P7Socket.Checksum, key: String? = nil) {
        self.type   = type
        self.key    = key

        if type == .HMAC_256 {
            self.initHMAC256()
        } else if type == .HMAC_384 {
            self.initHMAC384()
        }
    }

    /// Authenticates `data` using the configured checksum algorithm.
    ///
    /// - Parameter data: The message bytes to authenticate (typically the raw wire payload).
    /// - Returns: Authentication tag whose length matches the negotiated algorithm
    ///   (e.g. 32 bytes for SHA2-256 / HMAC-256).
    /// - Throws: `DigestError.unsupportedDigest` for unknown types;
    ///   `DigestError.digestNotProperlyInitialized` if an HMAC key was not provided.
    public func authenticate(data: Data) throws -> Data {
        switch self.type {
        case P7Socket.Checksum.SHA2_256:
            return data.sha256()

        case P7Socket.Checksum.SHA2_384:
            return data.sha384()

        case P7Socket.Checksum.SHA3_256:
            return data.sha3(SHA3.Variant.sha256)

        case P7Socket.Checksum.SHA3_384:
            return data.sha3(SHA3.Variant.sha384)

        case P7Socket.Checksum.HMAC_256:
            return try HMAC256_authenticate(data: data)

        case P7Socket.Checksum.HMAC_384:
            return try HMAC384_authenticate(data: data)

        default:
            throw DigestError.unsupportedDigest
        }
    }

    // MARK: -
    private func initHMAC256() {
        if let data = self.key?.dataFromHexadecimalString() {
            self.hmac = HMAC(key: Array(data), variant: HMAC.Variant.sha256)
        }
    }

    private func HMAC256_authenticate(data: Data) throws -> Data {
        guard let hmac = self.hmac else {
            throw DigestError.digestNotProperlyInitialized(message: "HMAC-256 not properly initialized")
        }

        let bytes = try hmac.authenticate(Array(data))
        return Data(bytes)
    }

    // MARK: -
    private func initHMAC384() {
        if let data = self.key?.dataFromHexadecimalString() {
            self.hmac = HMAC(key: Array(data), variant: HMAC.Variant.sha2(.sha384))
        }
    }

    private func HMAC384_authenticate(data: Data) throws -> Data {
        guard let hmac = self.hmac else {
            throw DigestError.digestNotProperlyInitialized(message: "HMAC-384 not properly initialized")
        }

        let bytes = try hmac.authenticate(Array(data))
        return Data(bytes)
    }
}
