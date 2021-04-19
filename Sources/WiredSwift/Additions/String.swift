//
//  String.swift
//  Wired
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation


extension String {
    public var nullTerminated: Data? {
        if var data = self.data(using: String.Encoding.utf8) {
            data.append(0)
            return data
        }
        return nil
    }
    
    public func deletingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }

    
    public var isBlank: Bool {
        return allSatisfy({ $0.isWhitespace })
    }
    
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
  
    public var lastPathComponent: String {
         
        get {
            return (self as NSString).lastPathComponent
        }
    }
    public var pathExtension: String {
         
        get {
             
            return (self as NSString).pathExtension
        }
    }
    public var stringByDeletingLastPathComponent: String {
         
        get {
             
            return (self as NSString).deletingLastPathComponent
        }
    }
    public var stringByDeletingPathExtension: String {
         
        get {
             
            return (self as NSString).deletingPathExtension
        }
    }
    public var pathComponents: [String] {
         
        get {
             
            return (self as NSString).pathComponents
        }
    }
  
    public func stringByAppendingPathComponent(path: String) -> String {
         
        let nsSt = self as NSString
         
        return nsSt.appendingPathComponent(path)
    }
  
    public func stringByAppendingPathExtension(ext: String) -> String? {
         
        let nsSt = self as NSString
         
        return nsSt.appendingPathExtension(ext)
    }
}


extension Optional where Wrapped == String {
  public var isBlank: Bool {
    return self?.isBlank ?? true
  }
}
