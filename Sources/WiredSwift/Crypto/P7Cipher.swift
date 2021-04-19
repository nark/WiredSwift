//
//  P7Cipher.swift
//  Wired 3
//
//  Created by Rafael Warnault on 25/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation
import CryptoSwift



public class P7Cipher {
    public var cipher: P7Socket.CipherType = .NONE
    public var cipherKey:String!
    public var cipherIV:[UInt8]!
    
    private var aes:AES? = nil
    
    

    
    public init(cipher: P7Socket.CipherType, key: String, iv: Data?) {
        self.cipher         = cipher
        self.cipherKey      = key
        
        if let i = iv {
            self.cipherIV = i.bytes
        } else {
            self.cipherIV = AES.randomIV(16)
        }
        self.initAES()
    }
    
    public func encrypt(data: Data) -> Data? {
        do {
            if let aes = self.aes {
                let dataArray = try aes.encrypt(Array(data))
                return Data(dataArray)
            }
        } catch {
            Logger.fatal("Encryption error: \(error)")
        }
        
        return nil
    }
    
    
    public func decrypt(data: Data) -> Data? {
        do {
            if let aes = self.aes {
            let decryptedData = try aes.decrypt(Array(data))
            
            return Data(decryptedData)
            }
        } catch {
            Logger.fatal("Decryption error: \(error) \(data.toHex())")
        }
        
        return nil
    }
    
    
    
    private func initAES() {
        do {
            if let data = self.cipherKey.dataFromHexadecimalString() {
                self.aes = try AES(key: Array(data), blockMode: CBC(iv: self.cipherIV!), padding: .pkcs7)
            }
        } catch {
            Logger.fatal("AES init error: \(error)")
        }
    }
}
