//
//  ECDH.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2021.
//

import Foundation
import Crypto

/// P-521 Elliptic Curve Diffie-Hellman key agreement.
///
/// Used during the P7 key-exchange handshake.  One side generates a fresh
/// ephemeral key pair; both sides call `computeSecret` with the peer's public
/// key and then call `derivedKey` to obtain the symmetric key and IV for
/// the session `Cipher`.
open class ECDH {
    private var publicKey: P521.KeyAgreement.PublicKey?
    private var privateKey: P521.KeyAgreement.PrivateKey?
    private var sharedSecret: SharedSecret?

    /// Creates a new ephemeral P-521 key pair.
    public init() {
        let privateKey = P521.KeyAgreement.PrivateKey()
        self.privateKey = privateKey
        self.publicKey  = privateKey.publicKey
    }

    /// Creates an ECDH instance that holds only the remote peer's public key.
    ///
    /// Use this when you need to represent the peer without a local private key.
    ///
    /// - Parameter data: Raw uncompressed P-521 public key bytes (133 bytes).
    public init(withPublicKey data: Data) {
        do {
            self.publicKey  = try P521.KeyAgreement.PublicKey(rawRepresentation: data)
            self.privateKey = nil
        } catch let error {
            Logger.error("Cannot init public key: \(error)")
        }
    }

    /// Returns the raw uncompressed representation of the local public key.
    ///
    /// - Returns: 133-byte P-521 public key, or `nil` if no key has been generated.
    public func publicKeyData() -> Data? {
        self.publicKey?.rawRepresentation
    }

    /// The hex-encoded shared secret produced by the most recent `computeSecret` call.
    ///
    /// `nil` if `computeSecret` has not yet been called successfully.
    public var secret: String? {
        guard let sharedSecret else { return nil }
        return sharedSecret.description
            .split(separator: ":")
            .last
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
    }

    /// Performs the ECDH key agreement with the remote peer's public key.
    ///
    /// The resulting shared secret is stored internally and also returned as a
    /// hex string for use as the HKDF salt in subsequent key derivation.
    ///
    /// - Parameter data: Raw uncompressed P-521 public key bytes from the peer (133 bytes).
    /// - Returns: Hex-encoded shared secret, or `nil` if the operation fails.
    public func computeSecret(withPublicKey data: Data) -> String? {
        guard let privateKey else {
            Logger.error("Cannot compute secret without a private key")
            return nil
        }

        do {
            let publicKey = try P521.KeyAgreement.PublicKey(rawRepresentation: data)
            self.sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)

            return self.secret
        } catch let error {
            Logger.error("Cannot init public key: \(error)")
        }

        return nil
    }

    /// Derives a 32-byte symmetric key from the shared secret using HKDF-SHA-512.
    ///
    /// - Parameter salt: Salt data (typically the shared secret hex string encoded as UTF-8).
    /// - Returns: Hex-encoded 32-byte key, or `nil` if no shared secret is available.
    public func derivedSymmetricKey(withSalt salt: Data) -> String? {
        guard let sharedSecret else { return nil }
        let deviredKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA512.self,
            salt: salt,
            sharedInfo: Data(),
            outputByteCount: 32)

        return deviredKey.withUnsafeBytes { body in
            Data(body).hexEncodedString()
        }
    }

    /// Derives a symmetric key and IV from the shared secret using HKDF-SHA-512.
    ///
    /// The output material is `32 + ivLength` bytes; the first 32 bytes become the
    /// cipher key and the remaining `ivLength` bytes become the nonce base / IV
    /// passed to `Cipher.init`.
    ///
    /// - Parameters:
    ///   - salt: Salt data (typically the shared-secret hex string encoded as UTF-8).
    ///   - ivLength: Required IV length for the chosen cipher suite
    ///     (use `Cipher.IVlength(forCipher:)`).
    /// - Returns: A tuple `(key, iv)` of the appropriate lengths, or `nil` if no
    ///   shared secret is available.
    public func derivedKey(withSalt salt: Data, andIVofLength ivLength: Int) -> (Data, Data)? {
        guard let sharedSecret else { return nil }
        let deviredKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA512.self,
            salt: salt,
            sharedInfo: Data(),
            outputByteCount: 32 + ivLength)

        let combined = deviredKey.withUnsafeBytes { body in
            Data(body)
        }
        return (combined.dropLast(ivLength), combined.dropFirst(32))
    }
}
