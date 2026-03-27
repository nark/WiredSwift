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
    /// Returns a lowercase hexadecimal string representation of the bytes.
    ///
    /// - Returns: A string of `2 * count` lowercase hex characters.
    public func toHex() -> String {
        return self.reduce("") { $0 + String(format: "%02x", $1) }
    }

    /// Appends a single signed byte to the buffer.
    ///
    /// - Parameters:
    ///   - data: The `Int8` byte value to append.
    ///   - count: Unused; retained for API compatibility.
    public mutating func append(byte data: Int8, count: Int = 1) {
        self.append(Data(from: data))
    }

    /// Appends a `UInt8` value, optionally in big-endian byte order.
    ///
    /// - Parameters:
    ///   - data: The value to append.
    ///   - bigEndian: When `true` (default), writes in big-endian order.
    public mutating func append(uint8 data: UInt8, bigEndian: Bool = true) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }

    /// Appends a `UInt16` value, optionally in big-endian byte order.
    ///
    /// - Parameters:
    ///   - data: The value to append.
    ///   - bigEndian: When `true` (default), writes in big-endian order.
    public mutating func append(uint16 data: UInt16, bigEndian: Bool = true) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }

    /// Appends a `UInt32` value, optionally in big-endian byte order.
    ///
    /// - Parameters:
    ///   - data: The value to append.
    ///   - bigEndian: When `true` (default), writes in big-endian order.
    public mutating func append(uint32 data: UInt32, bigEndian: Bool = true) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }

    /// Appends a `UInt64` value, optionally in big-endian byte order.
    ///
    /// - Parameters:
    ///   - data: The value to append.
    ///   - bigEndian: When `true` (default), writes in big-endian order.
    public mutating func append(uint64 data: UInt64, bigEndian: Bool = true) {
        let value = bigEndian ? data.bigEndian : data.littleEndian
        self.append(Data(from: value))
    }

    /// Appends a `Double` value by encoding its bit pattern as a `UInt64`,
    /// optionally in big-endian byte order.
    ///
    /// - Parameters:
    ///   - data: The `Double` value to append.
    ///   - bigEndian: When `true` (default), writes in big-endian order.
    public mutating func append(double data: Double, bigEndian: Bool = true) {
        let value = bigEndian ? data.bitPattern.bigEndian : data.bitPattern.littleEndian
        self.append(Data(from: value))
    }

    var uint8: UInt8 {
        var number: UInt8 = 0
        self.copyBytes(to: &number, count: MemoryLayout<UInt8>.size)
        return number
    }

    /// Interprets the first two bytes as a big-endian `UInt16`.
    ///
    /// - Returns: The value, or `nil` if the buffer contains fewer than 2 bytes.
    public var uint16: UInt16? {
        guard self.count >= MemoryLayout<UInt16>.size else { return nil }
        var value: UInt16 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { (destination: UnsafeMutableRawBufferPointer) in
            self.prefix(MemoryLayout<UInt16>.size).copyBytes(to: destination)
        }
        return CFSwapInt16HostToBig(value)
    }

    /// Interprets the first four bytes as a big-endian `UInt32`.
    ///
    /// - Returns: The value, or `nil` if the buffer contains fewer than 4 bytes.
    public var uint32: UInt32? {
        guard self.count >= MemoryLayout<UInt32>.size else { return nil }
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { (destination: UnsafeMutableRawBufferPointer) in
            self.prefix(MemoryLayout<UInt32>.size).copyBytes(to: destination)
        }
        return CFSwapInt32HostToBig(value)
    }

    /// Interprets the first eight bytes as a big-endian `UInt64`.
    ///
    /// - Returns: The value, or `nil` if the buffer contains fewer than 8 bytes.
    public var uint64: UInt64? {
        guard self.count >= MemoryLayout<UInt64>.size else { return nil }
        var value: UInt64 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { (destination: UnsafeMutableRawBufferPointer) in
            self.prefix(MemoryLayout<UInt64>.size).copyBytes(to: destination)
        }
        return CFSwapInt64HostToBig(value)
    }

    /// Interprets the first eight bytes as a big-endian IEEE 754 `Double`.
    ///
    /// - Returns: The value, or `nil` if the buffer contains fewer than 8 bytes.
    public var double: Double? {
        guard self.count >= MemoryLayout<UInt64>.size else { return nil }
        var bitPattern: UInt64 = 0
        _ = Swift.withUnsafeMutableBytes(of: &bitPattern) { (destination: UnsafeMutableRawBufferPointer) in
            self.prefix(MemoryLayout<UInt64>.size).copyBytes(to: destination)
        }
        return CFConvertDoubleSwappedToHost(CFSwappedFloat64(v: bitPattern))
    }

    /// Interprets the first 16 bytes as a UUID.
    ///
    /// - Returns: An `NSUUID`, or `nil` if the buffer contains fewer than 16 bytes.
    public var uuid: NSUUID? {
        guard self.count >= 16 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 16)
        self.copyBytes(to: &bytes, count: 16)
        return NSUUID(uuidBytes: bytes)
    }

    /// Decodes the bytes as an ASCII string.
    ///
    /// - Returns: The decoded `String`, or `nil` if the bytes are not valid ASCII.
    public var stringASCII: String? {
        NSString(data: self, encoding: String.Encoding.ascii.rawValue) as String?
    }

    /// Decodes the bytes as a UTF-8 string.
    ///
    /// - Returns: The decoded `String`, or `nil` if the bytes are not valid UTF-8.
    public var stringUTF8: String? {
        NSString(data: self, encoding: String.Encoding.utf8.rawValue) as String?
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
