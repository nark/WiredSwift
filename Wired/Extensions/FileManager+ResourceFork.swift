//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 25/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

struct FileManagerFinderInfo {
    var length:UInt32 = 0
    var data:[UInt32?] = [UInt32?](repeating: nil, count: 8)
}

extension FileManager {
    public static func sizeOfFile(atPath path:String) -> UInt64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            
            print(attributes)
            print(attributes[.size])
            
            return attributes[.size] as! UInt64
            
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
    
    
    
    public func finderInfo(atPath path:String) -> Data? {
        var attrs:attrlist = attrlist()
        var finderinfo:FileManagerFinderInfo = FileManagerFinderInfo()
        
        attrs.bitmapcount   = u_short(ATTR_BIT_MAP_COUNT)
        attrs.reserved      = 0
        attrs.commonattr    = attrgroup_t(ATTR_CMN_FNDRINFO)
        attrs.volattr       = 0
        attrs.dirattr       = 0
        attrs.fileattr      = 0
        attrs.forkattr      = 0
        
        var mpath = path
        let attrOK = mpath.withCString { (cstr) -> Bool in
            if getattrlist(cstr, &attrs, &finderinfo, MemoryLayout<FileManagerFinderInfo>.size, UInt32(FSOPT_NOFOLLOW)) < 0 {
                return true
            }
            return false
        }
        
        if !attrOK {
            return nil
        }
        
        let data = finderinfo.data.withUnsafeBytes { (bytes) -> Data in
            return Data(bytes: bytes)
        }
        
        
        print("finderinfo: \(data.toHex())")
        
        return data
    }
    
    
}
