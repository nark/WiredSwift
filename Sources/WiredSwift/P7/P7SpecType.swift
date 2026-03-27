//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

/// The set of wire types defined by the P7 binary protocol.
///
/// Each case corresponds to a `<p7:type>` element in the spec XML and determines
/// how a field's value is encoded in a binary P7 frame:
///
/// | Case      | Wire size          | Description                              |
/// |-----------|--------------------|------------------------------------------|
/// | `bool`    | 1 byte             | Boolean (0 = false, 1 = true)            |
/// | `enum32`  | 4 bytes BE         | 32-bit enumeration discriminant          |
/// | `int32`   | 4 bytes BE         | Signed 32-bit integer                    |
/// | `uint32`  | 4 bytes BE         | Unsigned 32-bit integer                  |
/// | `int64`   | 8 bytes BE         | Signed 64-bit integer                    |
/// | `uint64`  | 8 bytes BE         | Unsigned 64-bit integer                  |
/// | `double`  | 8 bytes BE         | IEEE 754 double-precision float          |
/// | `string`  | 4B length + UTF-8  | Variable-length UTF-8 string             |
/// | `uuid`    | 16 bytes           | RFC 4122 UUID                            |
/// | `date`    | 8 bytes BE         | Unix timestamp as IEEE 754 double        |
/// | `data`    | 4B length + bytes  | Arbitrary binary payload                 |
/// | `oobdata` | 8 bytes            | Out-of-band data descriptor              |
/// | `list`    | 4B length + items  | Length-prefixed list of NUL-terminated strings |
public enum P7SpecType: UInt32 {
    case bool    = 1
    case enum32  = 2
    case int32   = 3
    case uint32  = 4
    case int64   = 5
    case uint64  = 6
    case double  = 7
    case string  = 8
    case uuid    = 9
    case date    = 10
    case data    = 11
    case oobdata = 12
    case list    = 13

    /// Returns the `P7SpecType` that corresponds to the given XML type-name string.
    ///
    /// Recognises both canonical names (`"uint32"`) and the spec alias `"enum"` for `.enum32`.
    ///
    /// - Parameter forString: The type name as it appears in the `<p7:type name="…">` attribute.
    /// - Returns: The matching case, or `nil` if the string is not a known P7 type.
    // SECURITY (FINDING_P_017): return nil for unknown type strings instead of silent .uint32 default
    public static func specType(forString: String) -> P7SpecType? {
        switch forString {
        case "bool":
            return .bool
        case "enum", "enum32":
            return .enum32
        case "int32":
            return .int32
        case "uint32":
            return .uint32
        case "int64":
            return .int64
        case "uint64":
            return .uint64
        case "double":
            return .double
        case "string":
            return .string
        case "uuid":
            return .uuid
        case "date":
            return .date
        case "data":
            return .data
        case "oobdata":
            return .oobdata
        case "list":
            return .list
        default:
            Logger.error("WARNING: Unknown P7 spec type '\(forString)' — field will have nil type")
            return nil
        }
    }

    /// Returns the fixed wire size in bytes for the given type.
    ///
    /// Variable-length types (`.string`, `.data`, `.list`) return `0` because
    /// their actual size is determined by a 4-byte length prefix on the wire.
    ///
    /// - Parameter forType: The wire type whose size is queried.
    /// - Returns: The fixed byte count, or `0` for variable-length types.
    public static func size(forType: P7SpecType) -> Int {
        switch forType {
        case bool:      return 1
        case enum32:    return 4
        case int32:     return 4
        case uint32:    return 4
        case int64:     return 8
        case uint64:    return 8
        case double:    return 8
        case uuid:      return 16
        case date:      return 8
        case oobdata:   return 8

        default:
            return 0
        }
    }
}
