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
    public var cipher: P7Socket.CipherType = .ECDH_AES256_SHA256
    public var cipherKey:String!
    public var cipherIV:[UInt8]!
    
    private var aes:AES? = nil
    private var chacha:ChaCha20? = nil
    
    
    // MARK: -
    public init(cipher: P7Socket.CipherType, key: String, iv: Data?) {
        self.cipher         = cipher
        self.cipherKey      = key
        
        if let i = iv {
            self.cipherIV = i.bytes
        } else {
            self.cipherIV = self.randomIV(forCipher: cipher)
        }
        
        if self.cipher == .ECDH_AES256_SHA256 {
            self.initAES()
        }
        else if self.cipher == .ECDH_CHACHA20_SHA256 {
            self.initChaCha20()
        }
    }
    
    
    
    
    
    // MARK: -
    public func encrypt(data: Data) -> Data? {
        if self.cipher == .ECDH_AES256_SHA256 {
            return self.AES_encrypt(data: data)
        }
        else if self.cipher == .ECDH_CHACHA20_SHA256 {
            return self.ChaCha20_encrypt(data: data)
        }
        
        return nil
    }
    
    
    public func decrypt(data: Data) -> Data? {
        if self.cipher == .ECDH_AES256_SHA256 {
            return self.AES_decrypt(data: data)
        }
        else if self.cipher == .ECDH_CHACHA20_SHA256 {
            return self.ChaCha20_encrypt(data: data)
        }
        
        return nil
    }
    
    
    
    
    
    
    // MARK: -
    private func AES_encrypt(data: Data) -> Data? {
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
    
    
    private func AES_decrypt(data: Data) -> Data? {
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
    
    
    
    
    
    // MARK: -
    private func ChaCha20_encrypt(data: Data) -> Data? {
        do {
            if let chacha = self.chacha {
                let dataArray = try chacha.encrypt(Array(data))
                return Data(dataArray)
            }
        } catch {
            Logger.fatal("Encryption error: \(error)")
        }
        
        return nil
    }
    
    
    private func ChaCha20_decrypt(data: Data) -> Data? {
        do {
            if let chacha = self.chacha {
            let decryptedData = try chacha.decrypt(Array(data))
            
            return Data(decryptedData)
            }
        } catch {
            Logger.fatal("Decryption error: \(error) \(data.toHex())")
        }
        
        return nil
    }
    
    
    
    
    // MARK: -
    private func initAES() {
        do {
            if let data = self.cipherKey.dataFromHexadecimalString() {
                self.aes = try AES(key: Array(data), blockMode: CBC(iv: self.cipherIV!), padding: .pkcs7)
            }
        } catch {
            Logger.fatal("AES init error: \(error)")
        }
    }
    
    
    private func initChaCha20() {
        do {
            if let data = self.cipherKey.dataFromHexadecimalString() {
                self.chacha = try ChaCha20(key: Array(data), iv: self.cipherIV)
            }
        } catch {
            Logger.fatal("ChaCha20 init error: \(error)")
        }
    }
    
    
    // MARK: -
    
    private func randomIV(forCipher cipher:P7Socket.CipherType) -> Array<UInt8>? {
        if cipher == .ECDH_AES256_SHA256 {
            return AES.randomIV(16)
        } else if cipher == .ECDH_CHACHA20_SHA256 {
            return ChaCha20.randomIV(12)
        }
        return nil
    }
}
