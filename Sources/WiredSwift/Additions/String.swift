//
//  String.swift
//  Wired
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation

extension String {
    /// Returns the string encoded as UTF-8 with a trailing NUL byte appended,
    /// as required by P7 wire-format string fields.
    ///
    /// - Returns: UTF-8 encoded `Data` with a `0x00` sentinel, or `nil` if
    ///   UTF-8 encoding fails.
    public var nullTerminated: Data? {
        if var data = self.data(using: String.Encoding.utf8) {
            data.append(0)
            return data
        }
        return nil
    }

    /// Returns a copy of the string with `prefix` removed from the beginning,
    /// or the original string unchanged if it does not start with `prefix`.
    ///
    /// - Parameter prefix: The prefix string to strip.
    /// - Returns: The string with `prefix` removed, or `self` if not present.
    public func deletingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }

    /// Returns `true` when the string is empty or consists entirely of
    /// whitespace characters.
    public var isBlank: Bool {
        return allSatisfy({ $0.isWhitespace })
    }

    /// Parses the string as a hexadecimal representation and returns the
    /// corresponding raw bytes.
    ///
    /// Strips surrounding angle brackets and spaces before parsing.
    /// Returns `nil` if the string contains non-hex characters or has an odd
    /// number of digits.
    ///
    /// - Returns: The decoded `Data`, or `nil` if the string is not valid hex.
    public func dataFromHexadecimalString() -> Data? {
        let trimmedString = self.trimmingCharacters(
            in: CharacterSet(charactersIn: "<> ")).replacingOccurrences(
                of: " ", with: "")

        // make sure the cleaned up string consists solely of hex digits,
        // and that we have even number of them

        let regex = try! NSRegularExpression(pattern: "^[0-9a-f]*$", options: .caseInsensitive)

        let found = regex.firstMatch(in: trimmedString, options: [],
                                     range: NSRange(location: 0,
                                                    length: trimmedString.count))
        guard found != nil &&
            found?.range.location != NSNotFound &&
            trimmedString.count % 2 == 0 else {
                return nil
        }

        // everything ok, so now let's build Data

        var data = Data(capacity: trimmedString.count / 2)
        var index: String.Index? = trimmedString.startIndex

        while let i = index {
            let byteString = String(trimmedString[i ..< trimmedString.index(i, offsetBy: 2)])
            let num = UInt8(byteString.withCString { strtoul($0, nil, 16) })
            data.append([num] as [UInt8], count: 1)

            index = trimmedString.index(i, offsetBy: 2, limitedBy: trimmedString.endIndex)
            if index == trimmedString.endIndex { break }
        }

        return data
    }
}

extension String {

    /// The last path component of the string (bridges `NSString.lastPathComponent`).
    public var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }
    /// The path extension of the string (bridges `NSString.pathExtension`).
    public var pathExtension: String {
        (self as NSString).pathExtension
    }
    /// The path with its last component removed (bridges `NSString.deletingLastPathComponent`).
    public var stringByDeletingLastPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }
    /// The path with its extension removed (bridges `NSString.deletingPathExtension`).
    public var stringByDeletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
    /// The individual components of the path (bridges `NSString.pathComponents`).
    public var pathComponents: [String] {
        (self as NSString).pathComponents
    }

    /// Returns a new path string formed by appending `path` as a path component
    /// (bridges `NSString.appendingPathComponent`).
    ///
    /// - Parameter path: The path component to append.
    /// - Returns: The combined path string.
    public func stringByAppendingPathComponent(path: String) -> String {

        let nsSt = self as NSString

        return nsSt.appendingPathComponent(path)
    }

    /// Returns a new path string formed by appending `ext` as the path extension
    /// (bridges `NSString.appendingPathExtension`).
    ///
    /// - Parameter ext: The file extension to append (without leading dot).
    /// - Returns: The combined path string, or `nil` if the extension is invalid.
    public func stringByAppendingPathExtension(ext: String) -> String? {

        let nsSt = self as NSString

        return nsSt.appendingPathExtension(ext)
    }
}

extension Optional where Wrapped == String {
  /// Returns `true` when the optional is `nil` or the wrapped string is blank.
  public var isBlank: Bool {
    return self?.isBlank ?? true
  }
}
