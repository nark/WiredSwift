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
    
    private var aesBlockSize = 16

    
    
    public init(cipher: P7Socket.CipherType) {
        self.cipher         = cipher
        self.aesBlockSize   = self.keySize()
        self.cipherKey      = self.randomString(length: self.aesBlockSize)
        self.cipherIV       = AES.randomIV(16)
    }
    
    public init(cipher: P7Socket.CipherType, key: Data, iv: Data) {
        self.cipher         = cipher
        self.aesBlockSize   = self.keySize()
        self.cipherKey      = key.stringUTF8!
        self.cipherIV       = iv.bytes
    }
    
    public func encrypt(data: Data) -> Data? {
        do {
            let aes = try AES(key: Array(self.cipherKey.data(using: .utf8)!), blockMode: CBC(iv: self.cipherIV!), padding: .pkcs7)
            let dataArray = try aes.encrypt(Array(data))
            return Data(dataArray)
        } catch {
            Logger.fatal("Encryption error: \(error)")
            
            return nil
        }
    }
    
    
    public func decrypt(data: Data) -> Data? {
        do {
            let aes = try AES(key: Array(self.cipherKey.data(using: .utf8)!), blockMode: CBC(iv: self.cipherIV!), padding: .pkcs7)
            let dataArray = Array(data)
            let decryptedData = try aes.decrypt(dataArray)
            
            return Data(decryptedData)
        } catch {
            Logger.fatal("Decryption error: \(error) \(data.toHex())")
            
            return nil
        }
    }

    
    
    private func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
    
    private func keySize() -> Int {
        var keySizeAES = 0
        
        if      self.cipher == .RSA_AES_128_SHA1    ||
                self.cipher == .RSA_AES_192_SHA1    ||
                self.cipher == .RSA_AES_256_SHA1    {
            keySizeAES = 16
        }
        else if self.cipher == .RSA_AES_128_SHA256  ||
                self.cipher == .RSA_AES_192_SHA256  ||
                self.cipher == .RSA_AES_256_SHA256  {
            keySizeAES = 24
        }
        else if self.cipher == .RSA_AES_128_SHA512  ||
                self.cipher == .RSA_AES_192_SHA512  ||
                self.cipher == .RSA_AES_256_SHA512  {
            keySizeAES = 32
        }
        
        return keySizeAES
    }
}
