//
//  Digest.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/04/2021.
//

import Foundation
import CryptoSwift


public class Digest {
    public var type:P7Socket.Checksum
    public var key:String?    = nil
    
    private var hmac:HMAC?  = nil

    
    enum DigestError: Error {
        case digestFailed(error: Error)
        case digestNotProperlyInitialized(message: String)
        case unsupportedDigest
    }
    
    
    public init(type:P7Socket.Checksum, key: String? = nil) {
        self.type   = type
        self.key    = key
        
        if type == .HMAC_256 {
            self.initHMAC256()
        }
        else if type == .HMAC_384 {
            self.initHMAC384()
        }
    }
    
    
    public func authenticate(data:Data) throws -> Data {
        switch self.type {
        case P7Socket.Checksum.SHA2_256:
            return data.sha256()
            
        case P7Socket.Checksum.SHA2_384:
            return data.sha384()
            
        case P7Socket.Checksum.SHA3_256:
            return data.sha3(SHA3.Variant.sha256)
           
        case P7Socket.Checksum.SHA3_384:
            return data.sha3(SHA3.Variant.sha384)
            
        case P7Socket.Checksum.HMAC_256:
            return try HMAC256_authenticate(data: data)
            
        case P7Socket.Checksum.HMAC_384:
            return try HMAC384_authenticate(data: data)
            
        default:
            throw DigestError.unsupportedDigest
        }
    }
    
    
    
    
    
    // MARK: -
    private func initHMAC256() {
        if let data = self.key?.dataFromHexadecimalString() {
            self.hmac = HMAC(key: Array(data), variant: HMAC.Variant.sha256)
        }
    }
        
    private func HMAC256_authenticate(data:Data) throws -> Data {
        guard let hmac = self.hmac else {
            throw DigestError.digestNotProperlyInitialized(message: "HMAC-256 not properly initialized")
        }
        
        var bytes: Array<UInt8> = []
        
        do {
            bytes = try hmac.authenticate(Array(data))
            
        } catch let error {
            Logger.error("HMAC-256 authenticate error: \(error)")
            throw DigestError.digestFailed(error: error)
        }
        
        return Data(bytes)
    }
    
    // MARK: -
    private func initHMAC384() {
        if let data = self.key?.dataFromHexadecimalString() {
            self.hmac = HMAC(key: Array(data), variant: HMAC.Variant.sha2(.sha384))
        }
    }
        
    private func HMAC384_authenticate(data:Data) throws -> Data {
        guard let hmac = self.hmac else {
            throw DigestError.digestNotProperlyInitialized(message: "HMAC-384 not properly initialized")
        }
        
        var bytes: Array<UInt8> = []
        
        do {
            bytes = try hmac.authenticate(Array(data))
            
        } catch let error {
            Logger.error("HMAC-384 authenticate error: \(error)")
            throw DigestError.digestFailed(error: error)
        }
        
        return Data(bytes)
    }
}
