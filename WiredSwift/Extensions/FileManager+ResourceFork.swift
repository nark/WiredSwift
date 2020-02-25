//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 25/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

extension FileManager {
    public static func sizeOfFile(atPath path:String) -> UInt64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            
            return attributes[.size] as? UInt64 ?? UInt64(0)
            
        } catch let error as NSError {
            print("FileAttribute error: \(error)")
        }
        
        return 0
    }
    
    public static func resourceForkPath(forPath path:String) -> String {
        var nspath = path as NSString
        
        nspath = nspath.appendingPathComponent("..namedfork") as NSString
        nspath = nspath.appendingPathComponent("rsrc") as NSString
        
        return nspath as String
    }
    
        
    public func setFinderInfo(_ finderInfo: Data, atPath path:String) -> Bool {
        return true
    }
}
