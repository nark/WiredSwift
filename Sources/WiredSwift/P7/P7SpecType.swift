//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation


public enum P7SpecType : UInt32 {
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
    
    
    public static func specType(forString: String) -> P7SpecType {
        switch forString {
        case "bool":
            return .bool
        case "enum32":
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
            return .uint32
        }
    }
    
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
