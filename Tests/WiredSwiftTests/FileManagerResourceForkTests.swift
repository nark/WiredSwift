import XCTest
@testable import WiredSwift
#if !os(Linux)
import Darwin
#endif

final class FileManagerResourceForkTests: XCTestCase {
    func testResourceForkPathAppendsNamedforkAndRsrc() {
        let path = FileManager.resourceForkPath(forPath: "/tmp/example.txt")
        XCTAssertEqual(path, "/tmp/example.txt/..namedfork/rsrc")
    }

    func testSizeOfFileReturnsSizeForExistingFileAndNilForMissing() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("data.bin").path
        FileManager.default.createFile(atPath: filePath, contents: Data(repeating: 0xAA, count: 12))

        XCTAssertEqual(FileManager.sizeOfFile(atPath: filePath), 12)
        XCTAssertNil(FileManager.sizeOfFile(atPath: root.appendingPathComponent("missing.bin").path))
    }

    func testSetModeAppliesPOSIXPermissions() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("mode.txt").path
        FileManager.default.createFile(atPath: filePath, contents: Data("hello".utf8))

        XCTAssertTrue(FileManager.set(mode: 0o600, toPath: filePath))

        let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
        let perms = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testFinderInfoReturnsNilForInvalidInputsAndMissingAttributes() throws {
        let fm = FileManager.default
        XCTAssertNil(fm.finderInfo(atPath: nil))
        XCTAssertNil(fm.finderInfo(atPath: ""))

        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let filePath = root.appendingPathComponent("no-finder-info.txt").path
        FileManager.default.createFile(atPath: filePath, contents: Data("x".utf8))

        XCTAssertNil(fm.finderInfo(atPath: root.appendingPathComponent("missing.txt").path))
        XCTAssertNil(fm.finderInfo(atPath: filePath))
    }

    func testSetFinderInfoReturnsTrue() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("finder.bin").path
        FileManager.default.createFile(atPath: filePath, contents: Data([0x01, 0x02, 0x03]))

        let result = FileManager.default.setFinderInfo(Data(repeating: 0xAB, count: 32), atPath: filePath)
        XCTAssertTrue(result)
    }

    func testFinderInfoReturnsPaddedDataWhenAttributeIsShorterThan32Bytes() throws {
        #if os(Linux)
        throw XCTSkip("Extended attributes branch is disabled on Linux in finderInfo(atPath:).")
        #else
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("finder-short.bin").path
        FileManager.default.createFile(atPath: filePath, contents: Data([0x00]))

        let short = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xAA, 0xBB, 0xCC, 0xDD])
        try requireFinderInfoXattr(short, atPath: filePath)

        guard let finderInfo = FileManager.default.finderInfo(atPath: filePath) else {
            XCTFail("Expected padded FinderInfo")
            return
        }

        XCTAssertEqual(finderInfo.count, 32)
        XCTAssertEqual(finderInfo.prefix(short.count), short)
        XCTAssertEqual(finderInfo.dropFirst(short.count), Data(repeating: 0, count: 32 - short.count))
        #endif
    }

    func testFinderInfoReturnsFirst32BytesWhenAttributeIsLonger() throws {
        #if os(Linux)
        throw XCTSkip("Extended attributes branch is disabled on Linux in finderInfo(atPath:).")
        #else
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("finder-long.bin").path
        FileManager.default.createFile(atPath: filePath, contents: Data([0x00]))

        let payload = Data((0..<48).map { UInt8($0) })
        try requireFinderInfoXattr(payload, atPath: filePath)

        guard let finderInfo = FileManager.default.finderInfo(atPath: filePath) else {
            XCTFail("Expected FinderInfo")
            return
        }

        XCTAssertEqual(finderInfo.count, 32)
        XCTAssertEqual(finderInfo, payload.prefix(32))
        #endif
    }

    func testFinderInfoReturnsNilWhenAttributeExistsButHasZeroLength() throws {
        #if os(Linux)
        throw XCTSkip("Extended attributes branch is disabled on Linux in finderInfo(atPath:).")
        #else
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("finder-empty.bin").path
        FileManager.default.createFile(atPath: filePath, contents: Data([0x00]))

        try requireFinderInfoXattr(Data(), atPath: filePath)
        XCTAssertNil(FileManager.default.finderInfo(atPath: filePath))
        #endif
    }

    func testSetFinderUserTagWritesModernFinderTagXattr() throws {
        #if os(Linux)
        throw XCTSkip("Finder user tags are only supported on macOS.")
        #else
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("finder-tag.bin").path
        FileManager.default.createFile(atPath: filePath, contents: Data([0x00]))

        let result = FileManager.default.setFinderUserTag(labelNumber: 6, atPath: filePath, tagName: "Red")
        if !result {
            throw XCTSkip("Finder user tags xattr not supported in this environment (errno \(errno))")
        }

        XCTAssertEqual(FileManager.default.finderUserTags(atPath: filePath), ["Red\n6"])
        #endif
    }

    func testSetFinderUserTagPreservesNonColourTags() throws {
        #if os(Linux)
        throw XCTSkip("Finder user tags are only supported on macOS.")
        #else
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("finder-tag-preserve.bin").path
        FileManager.default.createFile(atPath: filePath, contents: Data([0x00]))

        try requireFinderUserTagsXattr(["Project X", "Old Red\n6"], atPath: filePath)
        XCTAssertTrue(FileManager.default.setFinderUserTag(labelNumber: 2, atPath: filePath, tagName: "Green"))

        XCTAssertEqual(FileManager.default.finderUserTags(atPath: filePath), ["Green\n2", "Project X"])
        #endif
    }

    func testSetFinderUserTagRemovesColouredEntryWhenLabelNumberIsZero() throws {
        #if os(Linux)
        throw XCTSkip("Finder user tags are only supported on macOS.")
        #else
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let filePath = root.appendingPathComponent("finder-tag-clear.bin").path
        FileManager.default.createFile(atPath: filePath, contents: Data([0x00]))

        try requireFinderUserTagsXattr(["Inbox", "Red\n6"], atPath: filePath)
        XCTAssertTrue(FileManager.default.setFinderUserTag(labelNumber: 0, atPath: filePath))

        XCTAssertEqual(FileManager.default.finderUserTags(atPath: filePath), ["Inbox"])
        #endif
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiredswift-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    #if !os(Linux)
    @discardableResult
    private func setFinderInfoXattr(_ data: Data, atPath path: String) -> Int32 {
        let name = "com.apple.FinderInfo"
        return data.withUnsafeBytes { rawBuffer in
            let base = rawBuffer.baseAddress
            return setxattr(path, name, base, rawBuffer.count, 0, 0)
        }
    }

    private func requireFinderInfoXattr(_ data: Data, atPath path: String) throws {
        if setFinderInfoXattr(data, atPath: path) == 0 {
            return
        }
        throw XCTSkip("FinderInfo xattr not supported in this environment (errno \(errno))")
    }

    private func requireFinderUserTagsXattr(_ tags: [String], atPath path: String) throws {
        let name = "com.apple.metadata:_kMDItemUserTags"
        let data = try PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)

        let result = data.withUnsafeBytes { rawBuffer -> Int32 in
            guard let base = rawBuffer.baseAddress else { return -1 }
            return setxattr(path, name, base, rawBuffer.count, 0, 0)
        }

        if result == 0 {
            return
        }

        throw XCTSkip("Finder user tags xattr not supported in this environment (errno \(errno))")
    }
    #endif
}
