import XCTest
@testable import WiredSwift

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

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiredswift-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
