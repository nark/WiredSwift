//
//  Digest.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/04/2021.
//

import Foundation
import CryptoSwift


public class Digest {
    public var type:Checksum!
    public var key:String!
    
    private var hmac:HMAC?      = nil
    private var poly:Poly1305?  = nil
    
    
    public init(key: String, type:Checksum) {
        self.key    = key
        self.type   = type
        
        if type == .HMAC_256 {
            self.initHMAC256()
        }
        else if type == .Poly1305 {
            self.initPoly1305()
        }
    }
    
    
    public func authenticate(data:Data) -> Data? {
        switch self.type {
        case Checksum.SHA2_256:
            return data.sha256()
            
        case Checksum.SHA3_256:
            return data.sha3(SHA3.Variant.sha256)
            
        case Checksum.HMAC_256:
            return HMAC256_authenticate(data: data)
            
        case Checksum.Poly1305:
            return Poly1305_authenticate(data: data)
            
        default:
            return nil
        }
    }
    
    
    
    
    
    // MARK: -
    private func initHMAC256() {
        if let data = self.key.dataFromHexadecimalString() {
            self.hmac = HMAC(key: data.bytes, variant: HMAC.Variant.sha256)
        }
    }
    
    
    private func initPoly1305() {
        if let data = self.key.dataFromHexadecimalString() {
            self.poly = Poly1305(key: data.bytes)
        }
    }
    
    
    private func HMAC256_authenticate(data:Data) -> Data? {
        do {
            if let bytes = try self.hmac?.authenticate(data.bytes) {
                return Data(bytes)
            }
        } catch let error {
            Logger.error("HMAC-256 authenticate error: \(error)")
        }
        return nil
    }
    
    private func Poly1305_authenticate(data:Data) -> Data? {
        do {
            if let bytes = try self.poly?.authenticate(data.bytes) {
                return Data(bytes)
            }
        } catch let error {
            Logger.error("Poly1305 authenticate error: \(error)")
        }
        return nil
    }
}
