import XCTest
@testable import wired3Lib

final class FilesControllerTests: XCTestCase {
    func testIsWithinJailAcceptsRootAndChildrenOnly() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let inside = root.appendingPathComponent("sub/child", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)

        let outside = root.deletingLastPathComponent().appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let controller = FilesController(rootPath: root.path)
        XCTAssertTrue(controller.isWithinJail(root.path))
        XCTAssertTrue(controller.isWithinJail(inside.path))
        XCTAssertFalse(controller.isWithinJail(outside.path))
    }
}
