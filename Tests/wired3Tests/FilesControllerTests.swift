import XCTest
import SocketSwift
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

    func testPreviewFileRepliesWithPreviewDataForReadableFile() throws {
        let context = try makeAppContext()
        let sockets = try makeConnectedP7Pair(spec: context.app.spec)
        defer {
            closeSockets(sockets)
            try? FileManager.default.removeItem(at: context.workingDir)
            App = context.previous
        }

        let payload = Data("QuickLook".utf8)
        FileManager.default.createFile(
            atPath: context.rootDir.appendingPathComponent("preview.txt").path,
            contents: payload
        )

        let client = makePreviewClient(socket: sockets.server, username: "alice", canDownload: true)
        let request = P7Message(withName: "wired.file.preview_file", spec: context.app.spec)
        request.addParameter(field: "wired.file.path", value: "/preview.txt")
        request.addParameter(field: "wired.transaction", value: UInt32(7))

        context.app.filesController.previewFile(client: client, message: request)

        let reply = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(reply.name, "wired.file.preview")
        XCTAssertEqual(reply.string(forField: "wired.file.path"), "/preview.txt")
        XCTAssertEqual(reply.data(forField: "wired.file.preview"), payload)
        XCTAssertEqual(reply.uint32(forField: "wired.transaction"), 7)
    }

    func testPreviewFileRejectsDirectories() throws {
        let context = try makeAppContext()
        let sockets = try makeConnectedP7Pair(spec: context.app.spec)
        defer {
            closeSockets(sockets)
            try? FileManager.default.removeItem(at: context.workingDir)
            App = context.previous
        }

        try FileManager.default.createDirectory(
            at: context.rootDir.appendingPathComponent("folder", isDirectory: true),
            withIntermediateDirectories: true
        )

        let client = makePreviewClient(socket: sockets.server, username: "alice", canDownload: true)
        let request = P7Message(withName: "wired.file.preview_file", spec: context.app.spec)
        request.addParameter(field: "wired.file.path", value: "/folder")

        context.app.filesController.previewFile(client: client, message: request)

        let reply = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(reply.name, "wired.error")
        XCTAssertEqual(reply.enumeration(forField: "wired.error"), 14)
    }

    func testPreviewFileRejectsOversizedFiles() throws {
        let context = try makeAppContext()
        let sockets = try makeConnectedP7Pair(spec: context.app.spec)
        defer {
            closeSockets(sockets)
            try? FileManager.default.removeItem(at: context.workingDir)
            App = context.previous
        }

        let largeData = Data(repeating: 0xAA, count: Int(FilesController.maxPreviewSizeBytes + 1))
        FileManager.default.createFile(
            atPath: context.rootDir.appendingPathComponent("too-big.bin").path,
            contents: largeData
        )

        let client = makePreviewClient(socket: sockets.server, username: "alice", canDownload: true)
        let request = P7Message(withName: "wired.file.preview_file", spec: context.app.spec)
        request.addParameter(field: "wired.file.path", value: "/too-big.bin")

        context.app.filesController.previewFile(client: client, message: request)

        let reply = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(reply.name, "wired.error")
        XCTAssertEqual(reply.enumeration(forField: "wired.error"), 5)
    }

    func testPreviewFileRequiresDownloadPrivilege() throws {
        let context = try makeAppContext()
        let sockets = try makeConnectedP7Pair(spec: context.app.spec)
        defer {
            closeSockets(sockets)
            try? FileManager.default.removeItem(at: context.workingDir)
            App = context.previous
        }

        FileManager.default.createFile(
            atPath: context.rootDir.appendingPathComponent("preview.txt").path,
            contents: Data("QuickLook".utf8)
        )

        let client = makePreviewClient(socket: sockets.server, username: "alice", canDownload: false)
        let request = P7Message(withName: "wired.file.preview_file", spec: context.app.spec)
        request.addParameter(field: "wired.file.path", value: "/preview.txt")

        context.app.filesController.previewFile(client: client, message: request)

        let reply = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(reply.name, "wired.error")
        XCTAssertEqual(reply.enumeration(forField: "wired.error"), 5)
    }

    private typealias P7Pair = (server: P7Socket, peer: P7Socket, listener: Socket)

    private func makeAppContext() throws -> (app: AppController, workingDir: URL, rootDir: URL, previous: AppController?) {
        let previous = App
        let workingDir = try makeTemporaryDirectory()
        let rootDir = workingDir.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)

        let app = AppController(
            specPath: wiredSpecPath(),
            dbPath: workingDir.appendingPathComponent("wired3.sqlite").path,
            rootPath: rootDir.path,
            configPath: configPath(),
            workingDirectoryPath: workingDir.path
        )

        App = app
        app.clientsController = ClientsController()
        app.filesController = FilesController(rootPath: rootDir.path)
        app.serverController = ServerController(port: 0, spec: app.spec)
        return (app, workingDir, rootDir, previous)
    }

    private func makeConnectedP7Pair(spec: P7Spec) throws -> P7Pair {
        let listener = try Socket.tcpListening(port: 0, address: "127.0.0.1")
        let port = Int(try listener.port())

        var acceptedSocket: Socket?
        let accepted = expectation(description: "accepted")
        DispatchQueue.global().async {
            acceptedSocket = try? listener.accept()
            accepted.fulfill()
        }

        let peer = P7Socket(hostname: "127.0.0.1", port: port, spec: spec)
        try peer.connect(withHandshake: false)

        wait(for: [accepted], timeout: 2.0)
        let native = try XCTUnwrap(acceptedSocket)
        let server = P7Socket(socket: native, spec: spec)
        return (server, peer, listener)
    }

    private func closeSockets(_ pair: P7Pair) {
        pair.server.disconnect()
        pair.peer.disconnect()
        pair.listener.close()
    }

    private func makePreviewClient(socket: P7Socket, username: String, canDownload: Bool) -> Client {
        let client = Client(userID: 1, socket: socket)
        client.state = .LOGGED_IN

        let user = User(username: username, password: "password")
        user.id = 1
        user.privileges = [
            UserPrivilege(name: "wired.account.transfer.download_files", value: canDownload, userId: 1)
        ]
        client.user = user
        return client
    }

    private func wiredSpecPath() -> String {
        WiredProtocolSpec.bundledSpecURL()!.path
    }

    private func configPath() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/wired3/config.ini")
            .path
    }
}
