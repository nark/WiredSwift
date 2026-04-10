import XCTest
import WiredSwift
@testable import wired3Lib

final class FileMetadataStoreTests: XCTestCase {
    func testCommentRoundTripAndRemoval() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("note.txt")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))

        let store = FileMetadataStore()
        try store.setComment("hello", forPath: fileURL.path)

        XCTAssertEqual(store.comment(forPath: fileURL.path), "hello")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".wired/comments").path))

        try store.removeComment(forPath: fileURL.path)

        XCTAssertNil(store.comment(forPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".wired/comments").path))
    }

    func testLabelRoundTripAndRemoval() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("note.txt")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))

        let store = FileMetadataStore()
        try store.setLabel(.LABEL_GREEN, forPath: fileURL.path)

        XCTAssertEqual(store.label(forPath: fileURL.path), .LABEL_GREEN)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".wired/labels").path))

        try store.removeLabel(forPath: fileURL.path)

        XCTAssertEqual(store.label(forPath: fileURL.path), .LABEL_NONE)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".wired/labels").path))
    }

    func testMovePreservesCommentAndLabelAcrossParents() throws {
        let directory = try makeTemporaryDirectory()
        let sourceParent = directory.appendingPathComponent("a", isDirectory: true)
        let destinationParent = directory.appendingPathComponent("b", isDirectory: true)
        let sourceURL = sourceParent.appendingPathComponent("note.txt")
        let destinationURL = destinationParent.appendingPathComponent("renamed.txt")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: sourceParent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("x".utf8))

        let store = FileMetadataStore()
        try store.setComment("hello", forPath: sourceURL.path)
        try store.setLabel(.LABEL_BLUE, forPath: sourceURL.path)
        try store.moveComment(from: sourceURL.path, to: destinationURL.path)
        try store.moveLabel(from: sourceURL.path, to: destinationURL.path)

        XCTAssertNil(store.comment(forPath: sourceURL.path))
        XCTAssertEqual(store.comment(forPath: destinationURL.path), "hello")
        XCTAssertEqual(store.label(forPath: sourceURL.path), .LABEL_NONE)
        XCTAssertEqual(store.label(forPath: destinationURL.path), .LABEL_BLUE)
    }

    func testLegacyCommentFormatIsReadable() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("note.txt")
        let metadataDirectory = directory.appendingPathComponent(".wired", isDirectory: true)
        let commentsURL = metadataDirectory.appendingPathComponent("comments")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))

        let payload = "note.txt\u{1C}legacy comment\u{1D}"
        try payload.data(using: .utf8)?.write(to: commentsURL)

        let store = FileMetadataStore()
        XCTAssertEqual(store.comment(forPath: fileURL.path), "legacy comment")
    }
}
