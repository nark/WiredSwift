//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 25/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

struct FileManagerFinderInfo {
    var length: UInt32 = 0
    var data: [UInt32?] = [UInt32?](repeating: nil, count: 8)
}

extension FileManager {
    public static func set(mode: Int, toPath path: String) -> Bool {
        var attributes = [FileAttributeKey: Any]()

        attributes[.posixPermissions] = mode // ex: 0o777

        do {
            try FileManager.default.setAttributes(attributes, ofItemAtPath: path)
        } catch let error {
            Logger.error("Cannot set mode to file \(path) error: \(error)")
            return false
        }

        return true
    }

    public static func sizeOfFile(atPath path: String) -> UInt64? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)

            return attributes[.size] as? UInt64

        } catch { }

        return nil
    }

    public static func resourceForkPath(forPath path: String) -> String {
        var nspath = path as NSString

        nspath = nspath.appendingPathComponent("..namedfork") as NSString
        nspath = nspath.appendingPathComponent("rsrc") as NSString

        return nspath as String
    }

    public func setFinderInfo(_ finderInfo: Data, atPath path: String) -> Bool {
        return true
    }

    public func finderInfo(atPath path: String?) -> Data? {
        guard let path, !path.isEmpty else { return nil }
        guard fileExists(atPath: path) else { return nil }

        #if os(Linux)
            return nil
        #else
        let name = "com.apple.FinderInfo"

        // 1) Query size
        let size = getxattr(path, name, nil, 0, 0, 0)
        if size < 0 {
            // ENOATTR: attribute absent -> normal
            return nil
        }

        // FinderInfo is normally 32 bytes, but we accept >= 32 and truncate, or reject weird values if you prefer.
        if size == 0 { return nil }

        // 2) Read attribute
        var data = Data(count: Int(size))
        let readCount: Int = data.withUnsafeMutableBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return -1 }
            return getxattr(path, name, base, rawBuf.count, 0, 0)
        }

        guard readCount >= 0 else { return nil }
        if readCount == 0 { return nil }

        // Normaliser à 32 bytes si tu veux rester conforme FinderInfo
        if data.count >= 32 {
            return data.prefix(32)
        } else {
            // Si tu veux être strict: return nil
            // ou padding:
            var padded = Data(count: 32)
            padded.replaceSubrange(0..<data.count, with: data)
            return padded
        }

        #endif

        return nil
    }

}
