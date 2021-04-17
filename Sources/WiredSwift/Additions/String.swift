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
