import XCTest
@testable import WiredSwift

final class FileDataTests: XCTestCase {
    func testIsValidAcceptsRegularPaths() {
        XCTAssertTrue(File.isValid(path: "/"))
        XCTAssertTrue(File.isValid(path: "/public/uploads"))
        XCTAssertTrue(File.isValid(path: "/boards/general/topic.txt"))
    }

    func testIsValidRejectsTraversalAndDotPrefixesIncludingEncoded() {
        XCTAssertFalse(File.isValid(path: "../secret"))
        XCTAssertFalse(File.isValid(path: "/safe/../secret"))
        XCTAssertFalse(File.isValid(path: "./relative"))
    }

    func testIsValidRejectsNullByte() {
        XCTAssertFalse(File.isValid(path: "/tmp/abc\0def"))
    }

    func testFileTypeReturnsNilForMissingPath() {
        XCTAssertNil(File.FileType.type(path: "/path/that/does/not/exist"))
    }

    func testFileTypeDefaultsToDirectoryForRegularDirectory() throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(File.FileType.type(path: root.path), .directory)
    }

    func testFileTypeSetDropboxThenReadBack() throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        XCTAssertTrue(File.FileType.set(type: .dropbox, path: root.path))
        XCTAssertEqual(File.FileType.type(path: root.path), .dropbox)
    }

    func testFileTypeSetSyncThenReadBack() throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        XCTAssertTrue(File.FileType.set(type: .sync, path: root.path))
        XCTAssertEqual(File.FileType.type(path: root.path), .sync)
    }

    func testFileTypeSetDirectoryRemovesMetadataMarker() throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        XCTAssertTrue(File.FileType.set(type: .uploads, path: root.path))
        XCTAssertEqual(File.FileType.type(path: root.path), .uploads)

        XCTAssertTrue(File.FileType.set(type: .directory, path: root.path))
        XCTAssertEqual(File.FileType.type(path: root.path), .directory)
    }

    func testFileTypeSetRejectsRegularFilesAndFileTypeFile() throws {
        let root = try makeTempDirectory()
        let regularFile = root.appendingPathComponent("a.txt")
        try Data("hello".utf8).write(to: regularFile)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(File.FileType.set(type: .dropbox, path: regularFile.path))
        XCTAssertFalse(File.FileType.set(type: .file, path: root.path))
    }

    func testFileCountIgnoresHiddenEntries() throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appendingPathComponent("visible"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("file.txt"))

        XCTAssertEqual(File.count(path: root.path), 2)
    }

    func testFileCountReturnsZeroForMissingPathAndRegularFile() throws {
        let root = try makeTempDirectory()
        let regularFile = root.appendingPathComponent("a.txt")
        try Data("hello".utf8).write(to: regularFile)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(File.count(path: "/path/that/does/not/exist"), 0)
        XCTAssertEqual(File.count(path: regularFile.path), 0)
    }

    func testFileSizeReturnsBytesOrZero() throws {
        let root = try makeTempDirectory()
        let regularFile = root.appendingPathComponent("a.bin")
        let bytes = Data([1, 2, 3, 4, 5, 6, 7])
        try bytes.write(to: regularFile)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(File.size(path: regularFile.path), UInt64(bytes.count))
        XCTAssertEqual(File.size(path: "/path/that/does/not/exist"), 0)
    }

    func testFilePrivilegeRoundTripAfterDropboxSetup() throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(File.FileType.set(type: .dropbox, path: root.path))

        var mode: File.FilePermissions = []
        mode.insert(.ownerRead)
        mode.insert(.groupWrite)
        mode.insert(.everyoneRead)
        let expected = FilePrivilege(owner: "alice", group: "staff", mode: mode)

        XCTAssertTrue(FilePrivilege.set(privileges: expected, path: root.path))
        let loaded = try XCTUnwrap(FilePrivilege(path: root.path))
        XCTAssertEqual(loaded.owner, "alice")
        XCTAssertEqual(loaded.group, "staff")
        XCTAssertEqual(loaded.mode, mode)
    }

    func testFilePrivilegeInitFailsForMissingOrMalformedMetadata() throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(FilePrivilege(path: root.path))

        let wired = root.appendingPathComponent(".wired")
        try FileManager.default.createDirectory(at: wired, withIntermediateDirectories: true)
        let malformed = wired.appendingPathComponent("permissions")
        try Data("too-short".utf8).write(to: malformed)

        XCTAssertNil(FilePrivilege(path: root.path))
    }

    func testFilePrivilegeSetFailsForMissingPathOrRegularFile() throws {
        let root = try makeTempDirectory()
        let regularFile = root.appendingPathComponent("a.txt")
        try Data("hello".utf8).write(to: regularFile)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let privilege = FilePrivilege(owner: "o", group: "g", mode: .ownerRead)
        XCTAssertFalse(FilePrivilege.set(privileges: privilege, path: "/path/that/does/not/exist"))
        XCTAssertFalse(FilePrivilege.set(privileges: privilege, path: regularFile.path))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiredswift-file-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
