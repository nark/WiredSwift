//
//  ECDSA.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 22/04/2021.
//

import Foundation
import Crypto

public class ECDSA {
    public var privateKey:P256.Signing.PrivateKey!
    public var publicKey:P256.Signing.PublicKey!
    
    public init?(privateKey: Data) {
        guard let pk = try? P256.Signing.PrivateKey(rawRepresentation: privateKey) else {
            Logger.error("ECDSA init from private key failed")
            return nil
        }

        self.privateKey = pk
        self.publicKey  = pk.publicKey
    }
    
    
    public init?(publicKey: Data) {
        guard let pk = try? P256.Signing.PublicKey(rawRepresentation: publicKey) else {
            Logger.error("ECDSA init from public key failed")
            return nil
        }

        self.privateKey = nil
        self.publicKey  = pk
    }
    
    
    public func sign(data: Data) -> Data? {
        return try? self.privateKey.signature(for: data).rawRepresentation
    }
    
    
    public func verify(data: Data, withSignature signature:Data) -> Bool {
        if self.publicKey == nil {
            Logger.error("Cannot verify without a public key")
            return false
        }
        
        guard let s = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            Logger.error("Fail to read ECDSA Signature")
            return false
        }
        return self.publicKey.isValidSignature(s, for: data)
    }
}
