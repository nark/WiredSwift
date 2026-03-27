//
//  ECDSA.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 22/04/2021.
//

import Foundation
import Crypto

/// P-256 ECDSA signing and verification for P7 server-identity certificates.
///
/// During the key exchange the session ECDH-derived key is used as the ECDSA
/// private key so that authentication is bound to the shared secret.  The
/// server also uses a persistent P-256 identity key to sign its ephemeral
/// ECDH public key for TOFU (Trust On First Use).
public class ECDSA {
    /// The P-256 private key; present only when initialised with `init(privateKey:)`.
    public var privateKey: P256.Signing.PrivateKey?
    /// The corresponding P-256 public key; always present after a successful initialisation.
    public var publicKey: P256.Signing.PublicKey!

    /// Creates an ECDSA instance that can both sign and verify.
    ///
    /// - Parameter privateKey: Raw 32-byte P-256 private key scalar.
    /// - Returns: `nil` if the key data is invalid.
    public init?(privateKey: Data) {
        guard let pk = try? P256.Signing.PrivateKey(rawRepresentation: privateKey) else {
            Logger.error("ECDSA init from private key failed")
            return nil
        }

        self.privateKey = pk
        self.publicKey  = pk.publicKey
    }

    /// Creates an ECDSA instance that can only verify signatures.
    ///
    /// - Parameter publicKey: Raw 64-byte uncompressed P-256 public key.
    /// - Returns: `nil` if the key data is invalid.
    public init?(publicKey: Data) {
        guard let pk = try? P256.Signing.PublicKey(rawRepresentation: publicKey) else {
            Logger.error("ECDSA init from public key failed")
            return nil
        }

        self.privateKey = nil
        self.publicKey  = pk
    }

    /// Signs `data` with the private key.
    ///
    /// - Parameter data: The message bytes to sign (not pre-hashed; the P-256
    ///   implementation hashes internally with SHA-256).
    /// - Returns: Raw fixed-size ECDSA signature (64 bytes), or `nil` if no
    ///   private key is available or signing fails.
    public func sign(data: Data) -> Data? {
        guard let privateKey else {
            Logger.error("Cannot sign without a private key")
            return nil
        }
        return try? privateKey.signature(for: data).rawRepresentation
    }

    /// Verifies that `signature` is a valid ECDSA signature over `data`.
    ///
    /// - Parameters:
    ///   - data: The original message bytes that were signed.
    ///   - signature: Raw 64-byte ECDSA signature produced by `sign(data:)`.
    /// - Returns: `true` if the signature is valid; `false` otherwise.
    public func verify(data: Data, withSignature signature: Data) -> Bool {
        guard let publicKey = self.publicKey else {
            Logger.error("Cannot verify without a public key")
            return false
        }

        guard let s = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            Logger.error("Fail to read ECDSA Signature")
            return false
        }
        return publicKey.isValidSignature(s, for: data)
    }
}
