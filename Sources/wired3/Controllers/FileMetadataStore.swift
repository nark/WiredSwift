import Foundation
import WiredSwift
#if os(macOS)
import Darwin
#endif

final class FileMetadataStore {
    private static let metadataDirectoryName = ".wired"
    private static let commentFieldSeparator = "\u{1C}"
    private static let commentRecordSeparator = "\u{1D}"

    enum MetadataError: Error {
        case io(Error)
        case finderMirror(Error)
    }

    func comment(forPath path: String) -> String? {
        let key = URL(fileURLWithPath: path).lastPathComponent
        let metadataPath = commentsMetadataPath(forPath: path)

        if let dictionary = readCommentDictionary(from: metadataPath) {
            return dictionary[key]
        }

        return nil
    }

    func setComment(_ comment: String, forPath path: String) throws {
        let key = URL(fileURLWithPath: path).lastPathComponent
        let metadataPath = commentsMetadataPath(forPath: path)
        var dictionary = readCommentDictionary(from: metadataPath) ?? [:]
        dictionary[key] = comment

        do {
            try ensureMetadataDirectoryExists(forPath: path)
            try writePropertyList(dictionary, to: metadataPath)
        } catch {
            throw MetadataError.io(error)
        }

        #if os(macOS)
        do {
            try mirrorFinderComment(comment, forPath: path)
        } catch {
            throw MetadataError.finderMirror(error)
        }
        #endif
    }

    func removeComment(forPath path: String) throws {
        let key = URL(fileURLWithPath: path).lastPathComponent
        let metadataPath = commentsMetadataPath(forPath: path)
        var dictionary = readCommentDictionary(from: metadataPath) ?? [:]
        dictionary.removeValue(forKey: key)

        do {
            try writeOrDelete(dictionary, at: metadataPath)
        } catch {
            throw MetadataError.io(error)
        }

        #if os(macOS)
        do {
            try mirrorFinderComment("", forPath: path)
        } catch {
            throw MetadataError.finderMirror(error)
        }
        #endif
    }

    func moveComment(from sourcePath: String, to destinationPath: String) throws {
        guard let comment = comment(forPath: sourcePath) else { return }

        try? removeComment(forPath: sourcePath)
        try setComment(comment, forPath: destinationPath)
    }

    func label(forPath path: String) -> File.FileLabel {
        let key = URL(fileURLWithPath: path).lastPathComponent
        let metadataPath = labelsMetadataPath(forPath: path)
        guard let dictionary = readLabelDictionary(from: metadataPath),
              let rawValue = dictionary[key],
              let label = File.FileLabel(rawValue: rawValue) else {
            return .LABEL_NONE
        }

        return label
    }

    func setLabel(_ label: File.FileLabel, forPath path: String) throws {
        let key = URL(fileURLWithPath: path).lastPathComponent
        let metadataPath = labelsMetadataPath(forPath: path)
        var dictionary = readLabelDictionary(from: metadataPath) ?? [:]
        dictionary[key] = label.rawValue

        do {
            try ensureMetadataDirectoryExists(forPath: path)
            try writePropertyList(dictionary, to: metadataPath)
        } catch {
            throw MetadataError.io(error)
        }

        #if os(macOS)
        do {
            try mirrorFinderLabel(label, forPath: path)
        } catch {
            throw MetadataError.finderMirror(error)
        }
        #endif
    }

    func removeLabel(forPath path: String) throws {
        let key = URL(fileURLWithPath: path).lastPathComponent
        let metadataPath = labelsMetadataPath(forPath: path)
        var dictionary = readLabelDictionary(from: metadataPath) ?? [:]
        dictionary.removeValue(forKey: key)

        do {
            try writeOrDelete(dictionary, at: metadataPath)
        } catch {
            throw MetadataError.io(error)
        }

        #if os(macOS)
        do {
            try mirrorFinderLabel(.LABEL_NONE, forPath: path)
        } catch {
            throw MetadataError.finderMirror(error)
        }
        #endif
    }

    func moveLabel(from sourcePath: String, to destinationPath: String) throws {
        let label = label(forPath: sourcePath)
        guard label != .LABEL_NONE else { return }

        try? removeLabel(forPath: sourcePath)
        try setLabel(label, forPath: destinationPath)
    }

    private func metadataDirectoryPath(forPath path: String) -> String {
        URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .appendingPathComponent(Self.metadataDirectoryName, isDirectory: true)
            .path
    }

    private func commentsMetadataPath(forPath path: String) -> String {
        URL(fileURLWithPath: metadataDirectoryPath(forPath: path))
            .appendingPathComponent("comments")
            .path
    }

    private func labelsMetadataPath(forPath path: String) -> String {
        URL(fileURLWithPath: metadataDirectoryPath(forPath: path))
            .appendingPathComponent("labels")
            .path
    }

    private func ensureMetadataDirectoryExists(forPath path: String) throws {
        try FileManager.default.createDirectory(
            atPath: metadataDirectoryPath(forPath: path),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func readCommentDictionary(from path: String) -> [String: String]? {
        if let dictionary = readStringPropertyList(from: path) {
            return dictionary
        }

        return readLegacyCommentDictionary(from: path)
    }

    private func readLabelDictionary(from path: String) -> [String: UInt32]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return nil
        }

        if let dictionary = plist as? [String: NSNumber] {
            return dictionary.mapValues { UInt32(truncating: $0) }
        }

        if let dictionary = plist as? [String: UInt32] {
            return dictionary
        }

        if let dictionary = plist as? [String: Int] {
            return dictionary.reduce(into: [:]) { partialResult, entry in
                partialResult[entry.key] = UInt32(clamping: entry.value)
            }
        }

        return nil
    }

    private func readStringPropertyList(from path: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return nil
        }

        if let dictionary = plist as? [String: String] {
            return dictionary
        }

        if let dictionary = plist as? [String: NSString] {
            return dictionary.mapValues { $0 as String }
        }

        return nil
    }

    private func readLegacyCommentDictionary(from path: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        let fieldSeparator = Character(Self.commentFieldSeparator)
        let recordSeparator = Character(Self.commentRecordSeparator)
        var result: [String: String] = [:]

        for record in string.split(separator: recordSeparator, omittingEmptySubsequences: true) {
            let parts = record.split(separator: fieldSeparator, maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            result[String(parts[0])] = String(parts[1])
        }

        return result.isEmpty ? nil : result
    }

    private func writePropertyList<T>(_ dictionary: [String: T], to path: String) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func writeOrDelete<T>(_ dictionary: [String: T], at path: String) throws {
        if dictionary.isEmpty {
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
            return
        }

        try writePropertyList(dictionary, to: path)
    }

    #if os(macOS)
    private func mirrorFinderComment(_ comment: String, forPath path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { return }

        let xattrName = "com.apple.metadata:kMDItemFinderComment"

        if comment.isEmpty {
            let result = removexattr(path, xattrName, 0)
            if result != 0 && errno != ENOATTR {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            return
        }

        let plist = try PropertyListSerialization.data(fromPropertyList: comment, format: .binary, options: 0)
        let result = plist.withUnsafeBytes { rawBuffer -> Int32 in
            guard let base = rawBuffer.baseAddress else { return -1 }
            return setxattr(path, xattrName, base, rawBuffer.count, 0, 0)
        }

        if result != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func mirrorFinderLabel(_ label: File.FileLabel, forPath path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { return }

        // Wired rawValue order: NONE=0 RED=1 ORANGE=2 YELLOW=3 GREEN=4 BLUE=5 PURPLE=6 GRAY=7
        // Finder labelNumber:   None=0  Red=6  Orange=7 Yellow=5 Green=2 Blue=4 Purple=3 Gray=1
        let finderNumbers: [UInt16] = [0, 6, 7, 5, 2, 4, 3, 1]
        let xattrName = "com.apple.FinderInfo"
        let labelBitMask: UInt16 = 0x000E  // bits 1-3
        let labelBits = finderNumbers[Int(label.rawValue)] << 1

        // Read existing FinderInfo (32 bytes) or start from zero
        var finderInfo = [UInt8](repeating: 0, count: 32)
        let getResult = getxattr(path, xattrName, &finderInfo, 32, 0, 0)
        if getResult < 0 && errno != ENOATTR {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        // Flags are at bytes 8-9, big-endian (same layout for files and directories)
        let existingFlags = (UInt16(finderInfo[8]) << 8) | UInt16(finderInfo[9])
        let newFlags = (existingFlags & ~labelBitMask) | (labelBits & labelBitMask)
        finderInfo[8] = UInt8(newFlags >> 8)
        finderInfo[9] = UInt8(newFlags & 0xFF)

        let setResult = setxattr(path, xattrName, &finderInfo, 32, 0, 0)
        if setResult != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        if !FileManager.default.setFinderUserTag(
            labelNumber: Int(finderNumbers[Int(label.rawValue)]),
            atPath: path,
            tagName: finderUserTagName(for: label)
        ) {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func finderUserTagName(for label: File.FileLabel) -> String? {
        switch label {
        case .LABEL_NONE:   return nil
        case .LABEL_RED:    return "Red"
        case .LABEL_ORANGE: return "Orange"
        case .LABEL_YELLOW: return "Yellow"
        case .LABEL_GREEN:  return "Green"
        case .LABEL_BLUE:   return "Blue"
        case .LABEL_PURPLE: return "Purple"
        case .LABEL_GRAY:   return "Gray"
        }
    }
    #endif
}
