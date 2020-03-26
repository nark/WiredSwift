
//
//  Sata.swift
//  Wired
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation

extension Numeric {
    init<D: DataProtocol>(_ data: D) {
        var value: Self = .zero
        let size = withUnsafeMutableBytes(of: &value, { data.copyBytes(to: $0)} )
        assert(size == MemoryLayout.size(ofValue: value))
        self = value
    }
}

extension Data {
    init<T>(from value: T) {
        self = Swift.withUnsafeBytes(of: value) { Data($0) }
    }

    func to<T>(type: T.Type) -> T? where T: ExpressibleByIntegerLiteral {
        var value: T = 0
        guard count >= MemoryLayout.size(ofValue: value) else { return nil }
        _ = Swift.withUnsafeMutableBytes(of: &value, { copyBytes(to: $0)} )
        return value
    }
    
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
    
    var uint16: UInt16 {
        get {
            let i16array = self.withUnsafeBytes {
                UnsafeBufferPointer<UInt16>(start: $0, count: self.count/2).map(UInt16.init(littleEndian:))
            }
            return i16array[0]
        }
    }
    
    var uint32: UInt32 {
        get {
            let i32array = self.withUnsafeBytes {
                UnsafeBufferPointer<UInt32>(start: $0, count: self.count/2).map(UInt32.init(littleEndian:))
            }
            return i32array[0]
        }
    }
    
    var uint64: UInt64 {
        get {
            let i64array = self.withUnsafeBytes {
                UnsafeBufferPointer<UInt64>(start: $0, count: self.count/2).map(UInt64.init(bigEndian:))
            }
            return i64array[0]
        }
    }
    
//    var double:Double {
//        get {
//            let i64array = self.withUnsafeBytes {
//                UnsafeBufferPointer<Double>(start: UInt64(), count: self.count/2).map(Double.init(bitPattern:))
//            }
//            return i64array[0]
//        }
//    }
        
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
