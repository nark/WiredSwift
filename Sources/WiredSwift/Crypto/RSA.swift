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
    
    
    func encrypt(data: Data) -> Data? {
        do {
            var encryptedData:Data? = nil
            
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
                let k = SwKeyConvert.PublicKey.derToPKCS8PEM(self.publicKey)
                let pk = try SwKeyConvert.PublicKey.pemToPKCS1DER(k)
                encryptedData = try CC.RSA.encrypt(data, derKey: pk, tag: Data(), padding: .oaep, digest: .sha1)
            #elseif os(Linux)
                
            #endif
            
            return encryptedData
        } catch  {
            Logger.error("RSA Public encrypt failed")
        }

        return nil
    }
    
    
    func decrypt(data: Data) -> Data? {
        return nil
    }
}
