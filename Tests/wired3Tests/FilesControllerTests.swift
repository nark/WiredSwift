import XCTest
import WiredSwift
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

    func testRealAndVirtualMapping() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let controller = FilesController(rootPath: root.path)
        let real = controller.real(path: "/docs/readme.txt")
        XCTAssertEqual(real, root.path + "/docs/readme.txt")
        XCTAssertEqual(controller.virtual(path: real), "//docs/readme.txt")
        XCTAssertEqual(controller.virtual(path: root.path), "/")
    }

    func testCreateDefaultDirectoryIfMissingCreatesDropboxAndPrivileges() throws {
        let root = try makeTemporaryDirectory()
        let path = root.appendingPathComponent("shared-dropbox")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        var mode: File.FilePermissions = []
        mode.insert(.ownerRead)
        mode.insert(.ownerWrite)
        mode.insert(.everyoneRead)
        let privilege = FilePrivilege(owner: "alice", group: "staff", mode: mode)

        let controller = FilesController(rootPath: root.path)
        controller.createDefaultDirectoryIfMissing(path: path.path, type: .dropbox, privileges: privilege)

        XCTAssertEqual(File.FileType.type(path: path.path), .dropbox)
        let loaded = try XCTUnwrap(FilePrivilege(path: path.path))
        XCTAssertEqual(loaded.owner, "alice")
        XCTAssertEqual(loaded.group, "staff")
        XCTAssertEqual(loaded.mode, mode)
    }

    func testCreateDefaultDirectoryIfMissingLeavesRegularFileUntouched() throws {
        let root = try makeTemporaryDirectory()
        let path = root.appendingPathComponent("existing-file")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try Data("hello".utf8).write(to: path)

        let controller = FilesController(rootPath: root.path)
        controller.createDefaultDirectoryIfMissing(path: path.path, type: .dropbox, privileges: nil)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)
        XCTAssertEqual(File.FileType.type(path: path.path), .file)
    }

    func testDropBoxPrivilegesReturnsNilWhenNoDropboxInPath() throws {
        let root = try makeTemporaryDirectory()
        let docs = root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let controller = FilesController(rootPath: root.path)
        XCTAssertNil(controller.dropBoxPrivileges(forVirtualPath: "/docs/file.txt"))
    }

    func testDropBoxPrivilegesDefaultsToEveryoneWriteWhenPermissionFileMissing() throws {
        let root = try makeTemporaryDirectory()
        let dropbox = root.appendingPathComponent("dropbox")
        try FileManager.default.createDirectory(at: dropbox, withIntermediateDirectories: true)
        XCTAssertTrue(File.FileType.set(type: .dropbox, path: dropbox.path))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let controller = FilesController(rootPath: root.path)
        let privilege = try XCTUnwrap(controller.dropBoxPrivileges(forVirtualPath: "/dropbox/inner/file.txt"))
        XCTAssertEqual(privilege.owner, "")
        XCTAssertEqual(privilege.group, "")
        XCTAssertEqual(privilege.mode, .everyoneWrite)
    }

    func testDropBoxPrivilegesReturnsStoredPrivilegesForNestedPath() throws {
        let root = try makeTemporaryDirectory()
        let dropbox = root.appendingPathComponent("dropbox")
        try FileManager.default.createDirectory(at: dropbox, withIntermediateDirectories: true)
        XCTAssertTrue(File.FileType.set(type: .dropbox, path: dropbox.path))

        var mode: File.FilePermissions = []
        mode.insert(.ownerRead)
        mode.insert(.groupRead)
        let privilege = FilePrivilege(owner: "bob", group: "engineering", mode: mode)
        XCTAssertTrue(FilePrivilege.set(privileges: privilege, path: dropbox.path))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let controller = FilesController(rootPath: root.path)
        let loaded = try XCTUnwrap(controller.dropBoxPrivileges(forVirtualPath: "/dropbox/a/b/c.txt"))
        XCTAssertEqual(loaded.owner, "bob")
        XCTAssertEqual(loaded.group, "engineering")
        XCTAssertEqual(loaded.mode, mode)
    }
}
