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
    /// Sets the POSIX permission mode of the file or directory at `path`.
    ///
    /// - Parameters:
    ///   - mode: POSIX mode value, e.g. `0o755`.
    ///   - path: Absolute filesystem path of the target item.
    /// - Returns: `true` on success, `false` if the attributes could not be applied.
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

    /// Returns the byte size of the file at `path` as reported by filesystem attributes.
    ///
    /// - Parameter path: Absolute filesystem path to the file.
    /// - Returns: File size in bytes, or `nil` if the path does not exist or
    ///   the size attribute is unavailable.
    public static func sizeOfFile(atPath path: String) -> UInt64? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)

            return attributes[.size] as? UInt64

        } catch { }

        return nil
    }

    /// Returns the HFS+ named-fork path used to access the resource fork of a file.
    ///
    /// Appends `..namedfork/rsrc` to `path`, which is the POSIX path convention
    /// for accessing the resource fork on macOS.
    ///
    /// - Parameter path: Absolute filesystem path of the file whose resource fork is needed.
    /// - Returns: The resource-fork path string, e.g. `/path/to/file/..namedfork/rsrc`.
    public static func resourceForkPath(forPath path: String) -> String {
        var nspath = path as NSString

        nspath = nspath.appendingPathComponent("..namedfork") as NSString
        nspath = nspath.appendingPathComponent("rsrc") as NSString

        return nspath as String
    }

    /// Writes Finder info extended attribute data to the file at `path`.
    ///
    /// Currently a no-op placeholder; always returns `true`.
    ///
    /// - Parameters:
    ///   - finderInfo: 32-byte Finder info blob to write.
    ///   - path: Absolute filesystem path of the target file.
    /// - Returns: `true`.
    public func setFinderInfo(_ finderInfo: Data, atPath path: String) -> Bool {
        return true
    }

    /// Reads the `com.apple.FinderInfo` extended attribute of the file at `path`.
    ///
    /// Returns a 32-byte blob normalised to exactly 32 bytes (padded with
    /// zeroes if the attribute is shorter, truncated if longer). Returns `nil`
    /// on Linux, when the file does not exist, or when the attribute is absent.
    ///
    /// - Parameter path: Absolute filesystem path of the file to inspect.
    /// - Returns: A 32-byte `Data` blob, or `nil` if unavailable.
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
