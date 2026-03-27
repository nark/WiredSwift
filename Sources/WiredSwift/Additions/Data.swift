//
//  Sata.swift
//  Wired
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation
import CoreFoundation

extension Data {

    init<T>(from value: T) {
        self = Swift.withUnsafeBytes(of: value) { Data($0) }
    }

    func to<T>(type: T.Type) -> T? where T: ExpressibleByIntegerLiteral {
        var value: T = 0
        guard count >= MemoryLayout.size(ofValue: value) else { return nil }
        _ = Swift.withUnsafeMutableBytes(of: &value, { copyBytes(to: $0) })
        return value
    }
}

extension Data {
    public func toHex() -> String {
        return self.reduce("") { $0 + String(format: "%02x", $1) }
    }

    public mutating func append(byte data: Int8, count: Int = 1) {
        self.append(Data(from: data))
    }

    public mutating func append(uint8 data: UInt8, bigEndian: Bool = true) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }

    public mutating func append(uint16 data: UInt16, bigEndian: Bool = true) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }

    public mutating func append(uint32 data: UInt32, bigEndian: Bool = true) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }

    public mutating func append(uint64 data: UInt64, bigEndian: Bool = true) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }

    public mutating func append(double data: Double, bigEndian: Bool = true) {
        let value = bigEndian ? data.bitPattern.bigEndian : data.bitPattern.littleEndian
        self.append(Data(from: value))
    }

    var uint8: UInt8 {
        get {
            var number: UInt8 = 0
            self.copyBytes(to: &number, count: MemoryLayout<UInt8>.size)
            return number
        }
    }

    public var uint16: UInt16? {
        get {
            guard self.count >= MemoryLayout<UInt16>.size else { return nil }
            var value: UInt16 = 0
            _ = Swift.withUnsafeMutableBytes(of: &value) { (destination: UnsafeMutableRawBufferPointer) in
                self.prefix(MemoryLayout<UInt16>.size).copyBytes(to: destination)
            }
            return CFSwapInt16HostToBig(value)
        }
    }

    public var uint32: UInt32? {
        get {
            guard self.count >= MemoryLayout<UInt32>.size else { return nil }
            var value: UInt32 = 0
            _ = Swift.withUnsafeMutableBytes(of: &value) { (destination: UnsafeMutableRawBufferPointer) in
                self.prefix(MemoryLayout<UInt32>.size).copyBytes(to: destination)
            }
            return CFSwapInt32HostToBig(value)
        }
    }

    public var uint64: UInt64? {
        get {
            guard self.count >= MemoryLayout<UInt64>.size else { return nil }
            var value: UInt64 = 0
            _ = Swift.withUnsafeMutableBytes(of: &value) { (destination: UnsafeMutableRawBufferPointer) in
                self.prefix(MemoryLayout<UInt64>.size).copyBytes(to: destination)
            }
            return CFSwapInt64HostToBig(value)
        }
    }

    public var double: Double? {
        get {
            guard self.count >= MemoryLayout<UInt64>.size else { return nil }
            var bitPattern: UInt64 = 0
            _ = Swift.withUnsafeMutableBytes(of: &bitPattern) { (destination: UnsafeMutableRawBufferPointer) in
                self.prefix(MemoryLayout<UInt64>.size).copyBytes(to: destination)
            }
            return CFConvertDoubleSwappedToHost(CFSwappedFloat64(v: bitPattern))
        }
    }

    public var uuid: NSUUID? {
        get {
            guard self.count >= 16 else { return nil }
            var bytes = [UInt8](repeating: 0, count: 16)
            self.copyBytes(to: &bytes, count: 16)
            return NSUUID(uuidBytes: bytes)
        }
    }

    public var stringASCII: String? {
        get {
            return NSString(data: self, encoding: String.Encoding.ascii.rawValue) as String?
        }
    }

    public var stringUTF8: String? {
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
