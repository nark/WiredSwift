//
//  RSA.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Security
#elseif os(Linux)
import OpenSSL
#endif

open class RSA {
    var publicKey:Data!
    var privateKey:Data!

    public init?(publicKey: Data) {
        do {
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
                let k = SwKeyConvert.PublicKey.derToPKCS8PEM(publicKey)
                self.publicKey = try SwKeyConvert.PublicKey.pemToPKCS1DER(k)
            #elseif os(Linux)
            
            #endif
        } catch  {
            Logger.error("RSA Public Key init failed")
        }
    }
    
    
    public init?(bits: Int = 2048) {
        do {
            let (privatek, _) = try CC.RSA.generateKeyPair(bits)
            self.privateKey = privatek
        } catch  {
            Logger.error("RSA Public Key init failed")
        }
    }
    
    
    
    public func publicKey(from privateKey:Data) -> Data? {
        do {
            self.publicKey = try CC.RSA.getPublicKeyFromPrivateKey(privateKey)
            
            return self.publicKey
        } catch {
            Logger.error("Cannot get public key")
        }
        
        return nil
    }
    
    
    
    public func encrypt(data: Data) -> Data? {
        do {
            var encryptedData:Data? = nil
            
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
                encryptedData = try CC.RSA.encrypt(data, derKey: self.publicKey, tag: Data(), padding: .oaep, digest: .sha1)
            #elseif os(Linux)
                
            #endif
            
            return encryptedData
        } catch  {
            Logger.error("RSA Public encrypt failed")
        }

        return nil
    }
    
    
    public func decrypt(data: Data) -> Data? {
        do {
            var decryptedData:Data? = nil
            
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
                (decryptedData, _) = try CC.RSA.decrypt(data, derKey: self.privateKey, tag: Data(), padding: .oaep, digest: .sha1)
            #elseif os(Linux)
                
            #endif
            
            return decryptedData
        } catch  {
            Logger.error("RSA Public encrypt failed")
        }

        return nil
    }
}
