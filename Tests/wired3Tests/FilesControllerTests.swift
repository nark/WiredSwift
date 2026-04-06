import XCTest
import WiredSwift
@testable import wired3Lib

final class FilesControllerTests: XCTestCase {
    func testResolvedVirtualPathFollowsSymlinkOutsideRoot() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let external = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: external) }

        let target = external.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: target)

        let controller = FilesController(rootPath: root.path)
        let resolved = controller.resolvedVirtualPath(for: "/linked")

        XCTAssertEqual(resolved.normalizedVirtualPath, "/linked")
        XCTAssertEqual(resolved.joinedRealPath, root.appendingPathComponent("linked").path)
        XCTAssertEqual(resolved.resolvedRealPath, target.path)
        XCTAssertEqual(resolved.linkKind, .symlink)
    }

    func testRealAndVirtualMapping() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let controller = FilesController(rootPath: root.path)
        let real = controller.real(path: "/docs/readme.txt")
        XCTAssertEqual(real, root.path + "/docs/readme.txt")
        XCTAssertEqual(controller.virtual(path: real), "/docs/readme.txt")
        XCTAssertEqual(controller.virtual(path: root.path), "/")
    }

    func testResolvedVirtualPathByResolvingParentPreservesFinalComponent() throws {
        let root = try makeTemporaryDirectory()
        let external = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        addTeardownBlock { try? FileManager.default.removeItem(at: external) }

        let target = external.appendingPathComponent("uploads", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("drop"), withDestinationURL: target)

        let controller = FilesController(rootPath: root.path)
        let resolved = controller.resolvedVirtualPathByResolvingParent(for: "/drop/new-folder")

        XCTAssertEqual(resolved.normalizedVirtualPath, "/drop/new-folder")
        XCTAssertEqual(resolved.resolvedRealPath, target.appendingPathComponent("new-folder").path)
    }

    func testExactLinkKindDetectsSymlink() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let symlink = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

        let controller = FilesController(rootPath: root.path)
        XCTAssertEqual(controller.exactLinkKind(atPath: symlink.path), .symlink)
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

    func testDropBoxPrivilegesAlsoResolvesSyncDirectoryPrivileges() throws {
        let root = try makeTemporaryDirectory()
        let syncDir = root.appendingPathComponent("sync")
        try FileManager.default.createDirectory(at: syncDir, withIntermediateDirectories: true)
        XCTAssertTrue(File.FileType.set(type: .sync, path: syncDir.path))

        var mode: File.FilePermissions = []
        mode.insert(.ownerRead)
        mode.insert(.ownerWrite)
        let privilege = FilePrivilege(owner: "eve", group: "ops", mode: mode)
        XCTAssertTrue(FilePrivilege.set(privileges: privilege, path: syncDir.path))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let controller = FilesController(rootPath: root.path)
        let loaded = try XCTUnwrap(controller.dropBoxPrivileges(forVirtualPath: "/sync/sub/file.txt"))
        XCTAssertEqual(loaded.owner, "eve")
        XCTAssertEqual(loaded.group, "ops")
        XCTAssertEqual(loaded.mode, mode)
    }
}
