//
//  ECDH.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2021.
//

import Foundation
import Crypto

open class ECDH {
    private var publicKey:P256.KeyAgreement.PublicKey!
    private var privateKey:P256.KeyAgreement.PrivateKey!
    
    
    public init() {
        self.privateKey = P256.KeyAgreement.PrivateKey()
        self.publicKey  = self.privateKey.publicKey
    }
    
    public init(withPublicKey data:Data) {
        do {
            self.publicKey  = try P256.KeyAgreement.PublicKey(rawRepresentation: data)
            self.privateKey = nil
        } catch let error {
            Logger.error("Cannot init public key: \(error)")
        }
    }
    
    public func publicKeyData() -> Data? {
        self.publicKey.rawRepresentation
    }
    
    public func computeSecret(withPublicKey data:Data) -> String? {
        do {
            let publicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: data)
            let sharedSecret:SharedSecret = try self.privateKey.sharedSecretFromKeyAgreement(with: publicKey)
            
            if  let key = sharedSecret.description.split(separator: ":").last {
                return key.trimmingCharacters(in: CharacterSet.whitespaces)
            }
        } catch let error {
            Logger.error("Cannot init public key: \(error)")
        }
        
        return nil
    }
}
