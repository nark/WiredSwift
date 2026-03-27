//
//  ECDH.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2021.
//

import Foundation
import Crypto

open class ECDH {
    private var publicKey: P521.KeyAgreement.PublicKey?
    private var privateKey: P521.KeyAgreement.PrivateKey?
    private var sharedSecret: SharedSecret?

    public init() {
        let privateKey = P521.KeyAgreement.PrivateKey()
        self.privateKey = privateKey
        self.publicKey  = privateKey.publicKey
    }

    public init(withPublicKey data: Data) {
        do {
            self.publicKey  = try P521.KeyAgreement.PublicKey(rawRepresentation: data)
            self.privateKey = nil
        } catch let error {
            Logger.error("Cannot init public key: \(error)")
        }
    }

    public func publicKeyData() -> Data? {
        self.publicKey?.rawRepresentation
    }

    public var secret: String? {
        guard let sharedSecret else { return nil }
        return sharedSecret.description
            .split(separator: ":")
            .last
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
    }

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
