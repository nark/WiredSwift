//
//  ECDH.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2021.
//

import Foundation
import Crypto

open class ECDH {
    private var publicKey:P521.KeyAgreement.PublicKey!
    private var privateKey:P521.KeyAgreement.PrivateKey!
    private var sharedSecret:SharedSecret!
    
    public init() {
        self.privateKey = P521.KeyAgreement.PrivateKey()
        self.publicKey  = self.privateKey.publicKey
    }
    
    
    public init(withPublicKey data:Data) {
        do {
            self.publicKey  = try P521.KeyAgreement.PublicKey(rawRepresentation: data)
            self.privateKey = nil
        } catch let error {
            Logger.error("Cannot init public key: \(error)")
        }
    }

    
    public func publicKeyData() -> Data? {
        self.publicKey.rawRepresentation
    }
    
    
    public var secret:String? {
        if  let key = self.sharedSecret.description.split(separator: ":").last {
            return key.trimmingCharacters(in: CharacterSet.whitespaces)
        }
        return nil
    }
    
    
    public func computeSecret(withPublicKey data:Data) -> String? {
        do {
            let publicKey = try P521.KeyAgreement.PublicKey(rawRepresentation: data)
            self.sharedSecret = try self.privateKey.sharedSecretFromKeyAgreement(with: publicKey)
            
            return self.secret
        } catch let error {
            Logger.error("Cannot init public key: \(error)")
        }
        
        return nil
    }
    
    
    public func derivedSymmetricKey(withSalt salt:Data) -> String? {
        let deviredKey = self.sharedSecret.hkdfDerivedSymmetricKey(
                            using: SHA512.self,
                            salt: salt,
                            sharedInfo: Data(),
                            outputByteCount: 32)
        
        return deviredKey.withUnsafeBytes { body in
            Data(body).hexEncodedString()
        }
    }
    
    public func derivedKey(withSalt salt:Data, andIVofLength ivLength:Int) -> (Data, Data)? {
        let deviredKey = self.sharedSecret.hkdfDerivedSymmetricKey(
                            using: SHA512.self,
                            salt: salt,
                            sharedInfo: Data(),
                            outputByteCount: 32 + ivLength)
        
        let combined = deviredKey.withUnsafeBytes { body in
            Data(body)
        }
        
        if combined.count == 0 {
            return nil
        }
        
        return (combined.dropLast(ivLength), combined.dropFirst(32))
    }
}
