//
//  File.swift
//  Server
//
//  Created by Rafael Warnault on 25/03/2021.
//

import Foundation
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#else
import Glibc
#endif

/// Represents a Wired filesystem entry and provides helpers for reading and
/// writing Wired-specific metadata stored as hidden `.wired/` sub-files.
public class File {
    /// Relative path of the per-directory type metadata file.
    public static let wiredFileMetaType: String          = "/.wired/type"
    /// Relative path of the per-directory comments metadata file.
    public static let wiredFileMetaComments: String      = "/.wired/comments"
    /// Relative path of the per-directory permissions metadata file.
    public static let wiredFileMetaPermissions: String   = "/.wired/permissions"
    /// Relative path of the per-directory labels metadata file.
    public static let wiredFileMetaLabels: String        = "/.wired/labels"
    /// Relative path of the per-directory sync policy metadata file.
    public static let wiredFileMetaSyncPolicy: String    = "/.wired/sync_policy.json"

    /// Unicode field-separator (U+001C) used to delimit owner, group and mode
    /// within the permissions metadata file.
    public static let wiredPermissionsFieldSeparator    = "\u{1C}"

    fileprivate static func readData(atPath path: String) -> Data? {
        let fd = path.withCString { open($0, O_RDONLY) }
        guard fd >= 0 else {
            return nil
        }
        defer { close(fd) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)

        while true {
            let readCount: Int
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            readCount = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return -1 }
                return Darwin.read(fd, base, rawBuffer.count)
            }
            #else
            readCount = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return -1 }
                return Glibc.read(fd, base, rawBuffer.count)
            }
            #endif
            if readCount > 0 {
                data.append(contentsOf: buffer.prefix(readCount))
            } else if readCount == 0 {
                return data
            } else {
                return nil
            }
        }
    }

    /// Wired file-system entry type, mirroring the `wired.file.type` field values.
    public enum FileType: UInt32 {
        case file       = 0
        case directory  = 1
        case uploads    = 2
        case dropbox    = 3
        case sync       = 4

        /// Persists `type` to the `.wired/type` metadata file inside `path`.
        ///
        /// - Parameters:
        ///   - type: The desired `FileType`; must not be `.file` (only directories may carry a custom type).
        ///   - path: Absolute filesystem path of the directory to annotate.
        /// - Returns: `true` on success, `false` if the path does not exist, is not a directory,
        ///   or if any I/O error occurs.
        public static func set(type: File.FileType, path: String) -> Bool {
            var isDir: ObjCBool = false

            if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                return false
            }

            // wired.file.set_type applies to directories only, and may not be .file.
            if !isDir.boolValue || type == .file {
                return false
            }

            let typePath = path.stringByAppendingPathComponent(path: wiredFileMetaType)
            let wiredPath = typePath.stringByDeletingLastPathComponent

            if type == .directory {
                if FileManager.default.fileExists(atPath: typePath) {
                    do {
                        try FileManager.default.removeItem(atPath: typePath)
                    } catch {
                        print(error)
                        return false
                    }
                }

                return true
            }

            do {
                try FileManager.default.createDirectory(atPath: wiredPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print(error)
                return false
            }

            do {
                let value = "\(type.rawValue)\n"
                try value.write(to: URL(fileURLWithPath: typePath), atomically: true, encoding: .utf8)
            } catch {
                print(error)
                return false
            }

            return true
        }

        /// Reads the effective `FileType` for the item at `path`.
        ///
        /// Returns `.file` for regular files, `.directory` for plain directories,
        /// or the value stored in the `.wired/type` metadata file for annotated directories.
        ///
        /// - Parameter path: Absolute filesystem path to inspect.
        /// - Returns: The resolved `FileType`, or `nil` if the path does not exist.
        public static func type(path: String) -> FileType? {
            var isDir: ObjCBool = false
            var type: FileType? = .file

            if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                return nil
            }

            if isDir.boolValue == true {
                type = .directory
            }

            let typePath = path.stringByAppendingPathComponent(path: wiredFileMetaType)
            isDir = false

            if !FileManager.default.fileExists(atPath: typePath, isDirectory: &isDir) {
                return type
            }

            let typeData = File.readData(atPath: typePath)

            if  let typeString = typeData?.stringUTF8?.trimmingCharacters(in: .whitespacesAndNewlines),
                let value = UInt32(typeString) {
                type = FileType(rawValue: value)
            }

            return type
        }
    }

    /// Unix-style read/write permission flags for owner, group and everyone,
    /// stored in `wired.file.permissions` as a bitmask.
    public struct FilePermissions: OptionSet {
        public let rawValue: UInt32

        /// Creates a `FilePermissions` from a raw bitmask value.
        ///
        /// - Parameter rawValue: The bitmask representing combined permission flags.
        public init(rawValue: UInt32 ) {
            self.rawValue = rawValue
        }

        /// Owner has write permission.
        public static let ownerWrite       = FilePermissions(rawValue: 2 << 6)
        /// Owner has read permission.
        public static let ownerRead        = FilePermissions(rawValue: 4 << 6)
        /// Group has write permission.
        public static let groupWrite       = FilePermissions(rawValue: 2 << 3)
        /// Group has read permission.
        public static let groupRead        = FilePermissions(rawValue: 4 << 3)
        /// Everyone has read permission.
        public static let everyoneRead     = FilePermissions(rawValue: 2 << 0)
        /// Everyone has write permission.
        public static let everyoneWrite    = FilePermissions(rawValue: 4 << 0)
    }

    /// Finder-style colour labels that can be attached to a Wired directory.
    public enum FileLabel: UInt32 {
        case LABEL_NONE     = 0
        case LABEL_RED
        case LABEL_ORANGE
        case LABEL_YELLOW
        case LABEL_GREEN
        case LABEL_BLUE
        case LABEL_PURPLE
        case LABEL_GRAY
    }

    /// Returns whether `path` is safe to use as a Wired virtual path.
    ///
    /// Rejects null bytes, URL-encoded traversal sequences and any form of
    /// `../` that could escape the server root, both before and after
    /// percent-decoding.
    ///
    /// - Parameter path: The client-supplied virtual path to validate.
    /// - Returns: `true` if the path contains no traversal or injection hazards.
    public static func isValid(path: String) -> Bool {
        // Reject null bytes (can truncate path in C-level APIs)
        if path.contains("\0") {
            return false
        }

        // Reject URL-encoded traversal sequences
        let decodedPath = path.removingPercentEncoding ?? path

        // Standardize path before checks to prevent bypass via non-canonical forms
        let standardized = NSString(string: decodedPath).standardizingPath

        if standardized.hasPrefix(".") {
            return false
        }

        if standardized.contains("/..") {
            return false
        }

        if standardized.contains("../") {
            return false
        }

        // Also check the original (non-decoded) path
        if path.hasPrefix(".") {
            return false
        }

        if path.contains("/..") {
            return false
        }

        if path.contains("../") {
            return false
        }

        return true
    }

    /// Returns the byte size of the file at `path`, or `0` if unavailable.
    ///
    /// - Parameter path: Absolute filesystem path to the file.
    /// - Returns: File size in bytes.
    public static func size(path: String) -> UInt64 {
        return FileManager.sizeOfFile(atPath: path) ?? 0
    }

    /// Returns the number of visible (non-dot) items inside the directory at `path`.
    ///
    /// - Parameter path: Absolute filesystem path to a directory.
    /// - Returns: Item count, or `0` if the path does not exist or is not a directory.
    public static func count(path: String) -> UInt32 {
        var isDir: ObjCBool = false

        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return 0
        }

        if !isDir.boolValue {
            return 0
        }

        var content: [String] = []

        do {
            content = try FileManager.default.contentsOfDirectory(atPath: path)
            content = content.filter({ (string) -> Bool in
                !string.hasPrefix(".")
            })
        } catch {
            return 0
        }

        return UInt32(content.count)
    }
}

/// Owner + group + permission-mode triplet for a Wired directory.
///
/// Serialised to / deserialised from the `/.wired/permissions` extended
/// attribute file using U+001C as a field separator.
public class FilePrivilege {
    public var owner: String?
    public var group: String?
    public var mode: File.FilePermissions?

    /// Creates a `FilePrivilege` with explicit owner, group and mode values.
    ///
    /// - Parameters:
    ///   - owner: Account name of the directory owner.
    ///   - group: Group name associated with the directory.
    ///   - mode: Combined `FilePermissions` bitmask for owner, group and everyone.
    public init(owner: String, group: String, mode: File.FilePermissions) {
        self.owner = owner
        self.group = group
        self.mode = mode
    }

    /// Reads a `FilePrivilege` from the `.wired/permissions` metadata file
    /// inside the directory at `path`.
    ///
    /// - Parameter path: Absolute filesystem path to a directory.
    /// - Returns: A populated `FilePrivilege`, or `nil` if the path does not
    ///   exist, is not a directory, or the metadata file is absent or malformed.
    public init?(path: String) {
        var isDir: ObjCBool = false

        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return nil
        }

        if !isDir.boolValue {
            return nil
        }

        guard let data = File.readData(atPath: path.stringByAppendingPathComponent(path: File.wiredFileMetaPermissions)) else {
            return nil
        }

        guard let string = data.stringUTF8 else {
            return nil
        }

        let components = string.split(separator: Character(File.wiredPermissionsFieldSeparator), omittingEmptySubsequences: false)

        guard components.count >= 3 else {
            return nil
        }

        self.owner  = String(components[0])
        self.group  = String(components[1])
        self.mode   = File.FilePermissions(rawValue: UInt32(String(components[2])) ?? 0)
    }

    /// Persists `privileges` to the `.wired/permissions` metadata file inside `path`.
    ///
    /// - Parameters:
    ///   - privileges: The `FilePrivilege` value to write.
    ///   - path: Absolute filesystem path of the target directory.
    /// - Returns: `true` on success, `false` if the path does not exist or an I/O error occurs.
    public static func set(privileges: FilePrivilege, path: String) -> Bool {
        var isDir: ObjCBool = false

        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return false
        }

        let permissionsPath = path.stringByAppendingPathComponent(path: File.wiredFileMetaPermissions)

        let string1 = privileges.owner ?? ""
        let string2 = privileges.group ?? ""
        let string3 = (privileges.mode != nil) ? String(Int(privileges.mode!.rawValue)) : "0"

        let array: [String] = [string1, string2, string3]
        let final = array.joined(separator: File.wiredPermissionsFieldSeparator)
        let data = final.data(using: .utf8)

        do {
            try data?.write(to: URL.init(fileURLWithPath: permissionsPath))
        } catch {
            print(error)
            return false
        }

        return true
    }
}

/// Quota and retention policy attached to a `wired.file.type.sync` directory.
public struct SyncPolicy: Codable, Equatable {
    public var maxFileSizeBytes: UInt64
    public var maxTreeSizeBytes: UInt64
    public var maxItems: UInt64
    public var retentionDays: UInt32

    public init(
        maxFileSizeBytes: UInt64 = 0,
        maxTreeSizeBytes: UInt64 = 0,
        maxItems: UInt64 = 0,
        retentionDays: UInt32 = 0
    ) {
        self.maxFileSizeBytes = maxFileSizeBytes
        self.maxTreeSizeBytes = maxTreeSizeBytes
        self.maxItems = maxItems
        self.retentionDays = retentionDays
    }

    public static func load(path: String) -> SyncPolicy? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        let policyPath = path.stringByAppendingPathComponent(path: File.wiredFileMetaSyncPolicy)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: policyPath)) else {
            return nil
        }
        return try? JSONDecoder().decode(SyncPolicy.self, from: data)
    }

    @discardableResult
    public static func save(_ policy: SyncPolicy, path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        let policyPath = path.stringByAppendingPathComponent(path: File.wiredFileMetaSyncPolicy)
        let wiredPath = policyPath.stringByDeletingLastPathComponent

        do {
            try FileManager.default.createDirectory(atPath: wiredPath, withIntermediateDirectories: true, attributes: nil)
            let data = try JSONEncoder().encode(policy)
            try data.write(to: URL(fileURLWithPath: policyPath), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
