
//
//  Sata.swift
//  Wired
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation


extension Data {
    public func toHex() -> String {
        return self.reduce("") { $0 + String(format: "%02x", $1) }
    }
    
    mutating func append(byte data: Int8, count:Int = 1) {
        var data = data
        self.append(UnsafeBufferPointer(start: &data, count: count))
    }
    
    
    mutating func append(uint8 data: UInt8, bigEndian: Bool = true) {
        var data = bigEndian ? data.bigEndian : data.littleEndian
        self.append(UnsafeBufferPointer(start: &data, count: 1))
    }
    
    
    mutating func append(uint16 data: UInt16, bigEndian: Bool = true) {
        var data = bigEndian ? data.bigEndian : data.littleEndian
        self.append(UnsafeBufferPointer(start: &data, count: 1))
    }
    
    
    mutating func append(uint32 data: UInt32, bigEndian: Bool = true) {
        var data = bigEndian ? data.bigEndian : data.littleEndian
        self.append(UnsafeBufferPointer(start: &data, count: 1))
    }
    
    
    mutating func append(uint64 data: UInt64, bigEndian: Bool = true) {
        var data = bigEndian ? data.bigEndian : data.littleEndian
        self.append(UnsafeBufferPointer(start: &data, count: 1))
    }
    
    
    mutating func append(double data: Double, bigEndian: Bool = true) {
        let d = bigEndian ? data.bitPattern.bigEndian : data.bitPattern.littleEndian
        self.append(Swift.withUnsafeBytes(of: d) { Data($0) })
    }
    
    
    var uint8: UInt8 {
        get {
            var number: UInt8 = 0
            self.copyBytes(to:&number, count: MemoryLayout<UInt8>.size)
            return number
        }
    }
    
    var uint16: UInt16? {
        get {
            self.withUnsafeBytes( { (ptr : UnsafeRawBufferPointer) in
                let pointer = ptr.baseAddress!.assumingMemoryBound(to: UInt16.self).pointee
                return CFSwapInt16HostToBig(pointer)
            })
        }
    }
    
    var uint32: UInt32? {
        get {
            self.withUnsafeBytes( { (ptr : UnsafeRawBufferPointer) in
                let pointer = ptr.baseAddress!.assumingMemoryBound(to: UInt32.self).pointee
                return CFSwapInt32HostToBig(pointer)
            })
        }
    }
    
    var uint64: UInt64? {
        get {
            self.withUnsafeBytes( { (ptr : UnsafeRawBufferPointer) in
                let pointer = ptr.baseAddress!.assumingMemoryBound(to: UInt64.self).pointee
                return CFSwapInt64HostToBig(pointer)
            })
        }
    }
    
    var double:Double? {
        get {
            self.withUnsafeBytes( { (ptr : UnsafeRawBufferPointer) in
                let pointer = ptr.baseAddress!.assumingMemoryBound(to: UInt64.self).pointee
                return CFConvertDoubleSwappedToHost(CFSwappedFloat64(v: pointer))
            })
        }
    }
        
    var uuid: NSUUID? {
        get {
            var bytes = [UInt8](repeating: 0, count: self.count)
            self.copyBytes(to:&bytes, count: self.count * MemoryLayout<UInt32>.size)
            return NSUUID(uuidBytes: bytes)
        }
    }
    var stringASCII: String? {
        get {
            return NSString(data: self, encoding: String.Encoding.ascii.rawValue) as String?
        }
    }
    
    var stringUTF8: String? {
        get {
            return NSString(data: self, encoding: String.Encoding.utf8.rawValue) as String?
        }
    }
    
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }
    
    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return map { String(format: format, $0) }.joined()
    }
}
