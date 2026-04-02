import Foundation
import XCTest
import WiredSwift
@testable import wired3Lib
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum IntegrationTestError: Error {
    case socketCreationFailed
    case bindFailed
    case getsocknameFailed
    case connectTimedOut(port: Int, timeout: TimeInterval)
    case serverStopTimedOut
}

private var streamSocketType: Int32 {
    #if canImport(Darwin)
    return SOCK_STREAM
    #else
    return Int32(SOCK_STREAM.rawValue)
    #endif
}

private let integrationServerLock = NSLock()
private let installSIGPIPEIgnore: Void = {
    #if canImport(Darwin)
    _ = Darwin.signal(SIGPIPE, SIG_IGN)
    #else
    _ = Glibc.signal(SIGPIPE, SIG_IGN)
    #endif
}()

class SerializedIntegrationTestCase: XCTestCase {
    private static let executionLock = NSLock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        SerializedIntegrationTestCase.executionLock.lock()
    }

    override func tearDownWithError() throws {
        SerializedIntegrationTestCase.executionLock.unlock()
        try super.tearDownWithError()
    }
}

func integrationPackageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

func findAvailableLoopbackPort() throws -> Int {
    let fd = socket(AF_INET, streamSocketType, 0)
    guard fd >= 0 else { throw IntegrationTestError.socketCreationFailed }
    defer { _ = close(fd) }

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(0)
    address.sin_addr = in_addr(s_addr: in_addr_t(UInt32(0x7f000001).bigEndian))

    let bindResult = withUnsafePointer(to: &address) { ptr -> Int32 in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else { throw IntegrationTestError.bindFailed }

    var assignedAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &assignedAddress) { ptr -> Int32 in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            getsockname(fd, sockaddrPtr, &length)
        }
    }
    guard nameResult == 0 else { throw IntegrationTestError.getsocknameFailed }

    return Int(UInt16(bigEndian: assignedAddress.sin_port))
}

func waitForLoopbackPort(_ port: Int, timeout: TimeInterval) throws {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        let fd = socket(AF_INET, streamSocketType, 0)
        if fd >= 0 {
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = UInt16(port).bigEndian
            address.sin_addr = in_addr(s_addr: in_addr_t(UInt32(0x7f000001).bigEndian))

            let connected = withUnsafePointer(to: &address) { ptr -> Bool in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
            _ = close(fd)

            if connected {
                return
            }
        }

        usleep(50_000)
    }

    throw IntegrationTestError.connectTimedOut(port: port, timeout: timeout)
}

final class IntegrationServerRuntime {
    let rootURL: URL
    let filesURL: URL
    let dbPath: String
    let configPath: String
    let specPath: String
    let port: Int

    private let app: AppController
    private let serverStopped = DispatchSemaphore(value: 0)
    private var started = false
    private var cleaned = false

    init(existingRoot: URL? = nil, port: Int? = nil) throws {
        let resolvedRoot = existingRoot ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("wired3-integration-\(UUID().uuidString)", isDirectory: true)
        let resolvedPort = try port ?? findAvailableLoopbackPort()

        self.rootURL = resolvedRoot
        self.filesURL = resolvedRoot.appendingPathComponent("files", isDirectory: true)
        self.dbPath = resolvedRoot.appendingPathComponent("wired3.sqlite").path
        self.configPath = resolvedRoot.appendingPathComponent("config.ini").path
        self.specPath = try XCTUnwrap(WiredProtocolSpec.bundledSpecURL()).path
        self.port = resolvedPort

        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        let config = """
        [server]
        files = \(filesURL.path)
        name = Integration Test Server
        description = In-process integration test instance
        port = \(self.port)

        [settings]
        reindex_interval = 0

        [advanced]
        compression = ALL
        cipher = SECURE_ONLY
        checksum = SECURE_ONLY

        [security]
        strict_identity = yes
        """
        try config.write(toFile: configPath, atomically: true, encoding: .utf8)

        self.app = AppController(
            specPath: specPath,
            dbPath: dbPath,
            rootPath: filesURL.path,
            configPath: configPath,
            workingDirectoryPath: rootURL.path
        )
    }

    func start() throws {
        guard !started else { return }
        _ = installSIGPIPEIgnore

        // Keep integration logs actionable without flooding the in-process logger
        // pipeline between tests.
        Logger.setMaxLevel(.INFO)

        integrationServerLock.lock()
        var didStart = false
        defer {
            if !didStart {
                integrationServerLock.unlock()
            }
        }

        App = app

        DispatchQueue.global(qos: .userInitiated).async {
            self.app.start()
            self.serverStopped.signal()
        }

        try waitForLoopbackPort(port, timeout: 10)
        started = true
        didStart = true
    }

    func stop(cleanup: Bool = false) throws {
        guard started else { return }

        app.stop()

        let timeoutResult = serverStopped.wait(timeout: .now() + 20)
        guard timeoutResult == .success else {
            integrationServerLock.unlock()
            throw IntegrationTestError.serverStopTimedOut
        }

        // Give background client loops a short grace period to unwind before
        // allowing the next in-process runtime to replace the global App.
        usleep(200_000)

        integrationServerLock.unlock()
        started = false

        if cleanup {
            try cleanupArtifacts()
        }
    }

    func cleanupArtifacts() throws {
        if cleaned { return }
        cleaned = true
        try? FileManager.default.removeItem(at: rootURL)
    }

    func ensurePrivilegedUser(username: String, password plainPassword: String) {
        if let existing = app.usersController.user(withUsername: username) {
            _ = app.usersController.delete(user: existing)
        }

        let user = User(username: username, password: plainPassword.sha256())
        user.passwordSalt = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        user.group = "admin"
        user.groups = "admin"
        user.color = "1"
        XCTAssertTrue(app.usersController.save(user: user))

        guard let refreshed = app.usersController.user(withUsername: username) else {
            XCTFail("Could not reload privileged integration user")
            return
        }

        for privilege in app.spec.accountPrivileges ?? [] {
            XCTAssertTrue(app.usersController.setUserPrivilege(privilege, value: true, for: refreshed))
        }
    }

    func connectClient(username: String, password plainPassword: String) throws -> P7Socket {
        let spec = P7Spec(withPath: specPath)
        let socket = P7Socket(hostname: "127.0.0.1", port: port, spec: spec)
        socket.cipherType = .ECDH_AES256_SHA256
        socket.checksum = .SHA2_256
        socket.compression = .NONE
        socket.username = username
        socket.password = plainPassword
        try socket.connect()
        return socket
    }

    func chatMemberIDs(chatID: UInt32) -> Set<UInt32> {
        guard let chat = app.chatsController.chat(withID: chatID) else {
            return []
        }

        var memberIDs = Set<UInt32>()
        chat.withClients { client in
            memberIDs.insert(client.userID)
        }
        return memberIDs
    }
}

func sendClientInfoAndExpectServerInfo(socket: P7Socket) throws {
    let message = P7Message(withName: "wired.client_info", spec: socket.spec)
    message.addParameter(field: "wired.info.application.name", value: "wired3IntegrationTests")
    message.addParameter(field: "wired.info.application.version", value: "1.0")
    XCTAssertTrue(socket.write(message))

    let serverInfo = try readMessage(from: socket, expectedName: "wired.server_info", maxReads: 8)
    XCTAssertEqual(serverInfo.string(forField: "wired.info.application.name"), "Wired Server 3")
}

func sendLoginAndExpectSuccess(socket: P7Socket, username: String, password plainPassword: String) throws -> P7Message {
    let login = P7Message(withName: "wired.send_login", spec: socket.spec)
    login.addParameter(field: "wired.user.login", value: username)
    login.addParameter(field: "wired.user.password", value: plainPassword.sha256())
    XCTAssertTrue(socket.write(login))
    return try readMessage(from: socket, expectedName: "wired.login", maxReads: 12)
}

func sendLoginAndExpectError(socket: P7Socket, username: String, password plainPassword: String) throws -> P7Message {
    let login = P7Message(withName: "wired.send_login", spec: socket.spec)
    login.addParameter(field: "wired.user.login", value: username)
    login.addParameter(field: "wired.user.password", value: plainPassword.sha256())
    XCTAssertTrue(socket.write(login))
    return try readMessage(from: socket, expectedNames: ["wired.error", "wired.banned"], maxReads: 12)
}

@discardableResult
func readMessage(
    from socket: P7Socket,
    expectedName: String,
    maxReads: Int,
    timeout: TimeInterval = 3
) throws -> P7Message {
    try readMessage(from: socket, expectedNames: [expectedName], maxReads: maxReads, timeout: timeout)
}

@discardableResult
func readMessage(
    from socket: P7Socket,
    expectedNames: Set<String>,
    maxReads: Int,
    timeout: TimeInterval = 3
) throws -> P7Message {
    var seenNames: [String] = []
    for _ in 0..<maxReads {
        do {
            let message = try socket.readMessage(timeout: timeout, enforceDeadline: true)
            if let name = message.name {
                if seenNames.count < 40 {
                    seenNames.append(name)
                }
            } else if seenNames.count < 40 {
                seenNames.append("<nil>")
            }

            if let name = message.name, expectedNames.contains(name) {
                return message
            }
        } catch {
            // Integration streams can be briefly idle between async server pushes.
            // Keep polling until maxReads is reached.
            continue
        }
    }

    XCTFail(
        """
        Expected one of \(expectedNames.sorted()) within \(maxReads) reads (timeout=\(timeout)s).
        Seen: \(seenNames)
        """
    )
    return P7Message(withName: "wired.error", spec: socket.spec)
}

func tryReadMessage(
    from socket: P7Socket,
    expectedNames: Set<String>,
    maxReads: Int,
    timeout: TimeInterval = 3
) -> P7Message? {
    for _ in 0..<maxReads {
        do {
            let message = try socket.readMessage(timeout: timeout, enforceDeadline: true)
            if let name = message.name, expectedNames.contains(name) {
                return message
            }
        } catch {
            continue
        }
    }

    return nil
}

func drainMessages(socket: P7Socket, count: Int = 12) {
    for _ in 0..<count {
        do {
            _ = try socket.readMessage(timeout: 0.05, enforceDeadline: true)
        } catch {
            break
        }
    }
}

struct SyncUserClient {
    let username: String
    let userID: UInt32
    let socket: P7Socket
}

struct SyncTreeEntry {
    let relativePath: String
    let isDirectory: Bool
    let size: UInt64
}

final class ConcurrentStartBarrier {
    private let participantCount: Int
    private let condition = NSCondition()
    private var arrived = 0
    private var generation = 0

    init(participantCount: Int) {
        precondition(participantCount > 0)
        self.participantCount = participantCount
    }

    func wait() {
        condition.lock()
        let currentGeneration = generation
        arrived += 1
        if arrived == participantCount {
            arrived = 0
            generation += 1
            condition.broadcast()
            condition.unlock()
            return
        }

        while generation == currentGeneration {
            condition.wait()
        }
        condition.unlock()
    }
}

func connectAndAuthenticate(
    runtime: IntegrationServerRuntime,
    username: String,
    password: String
) throws -> SyncUserClient {
    let socket = try runtime.connectClient(username: username, password: password)
    try sendClientInfoAndExpectServerInfo(socket: socket)
    let login = try sendLoginAndExpectSuccess(socket: socket, username: username, password: password)
    drainMessages(socket: socket)
    let userID = try XCTUnwrap(login.uint32(forField: "wired.user.id"))
    return SyncUserClient(username: username, userID: userID, socket: socket)
}

func createDirectory(socket: P7Socket, path: String) throws {
    let create = P7Message(withName: "wired.file.create_directory", spec: socket.spec)
    create.addParameter(field: "wired.file.path", value: path)
    XCTAssertTrue(socket.write(create))
    let reply = try readMessage(from: socket, expectedNames: ["wired.okay", "wired.error"], maxReads: 20)
    if reply.name == "wired.error" {
        let errorString = reply.string(forField: "wired.error.string") ?? "wired.error.unknown"
        throw NSError(domain: "IntegrationCreateDirectory", code: 1, userInfo: [NSLocalizedDescriptionKey: "create_directory failed for \(path): \(errorString)"])
    }
}

func movePath(socket: P7Socket, from oldPath: String, to newPath: String) throws {
    let move = P7Message(withName: "wired.file.move", spec: socket.spec)
    move.addParameter(field: "wired.file.path", value: oldPath)
    move.addParameter(field: "wired.file.new_path", value: newPath)
    XCTAssertTrue(socket.write(move))
    let reply = try readMessage(from: socket, expectedNames: ["wired.okay", "wired.error"], maxReads: 20)
    if reply.name == "wired.error" {
        let errorString = reply.string(forField: "wired.error.string") ?? "wired.error.unknown"
        throw NSError(domain: "IntegrationMovePath", code: 1, userInfo: [NSLocalizedDescriptionKey: "move failed from \(oldPath) to \(newPath): \(errorString)"])
    }
}

func deletePath(socket: P7Socket, path: String) throws {
    let delete = P7Message(withName: "wired.file.delete", spec: socket.spec)
    delete.addParameter(field: "wired.file.path", value: path)
    XCTAssertTrue(socket.write(delete))
    let reply = try readMessage(from: socket, expectedNames: ["wired.okay", "wired.error"], maxReads: 20)
    if reply.name == "wired.error" {
        let errorString = reply.string(forField: "wired.error.string") ?? "wired.error.unknown"
        throw NSError(domain: "IntegrationDeletePath", code: 1, userInfo: [NSLocalizedDescriptionKey: "delete failed for \(path): \(errorString)"])
    }
}

func createSyncDirectory(
    socket: P7Socket,
    path: String,
    owner: String = "admin",
    group: String = "admin",
    userMode: String = "bidirectional",
    groupMode: String = "bidirectional",
    everyoneMode: String = "bidirectional",
    maxFileSizeBytes: UInt64 = 0,
    maxTreeSizeBytes: UInt64 = 0,
    excludePatterns: String = ""
) throws {
    try createDirectory(socket: socket, path: path)

    let setType = P7Message(withName: "wired.file.set_type", spec: socket.spec)
    setType.addParameter(field: "wired.file.path", value: path)
    setType.addParameter(field: "wired.file.type", value: UInt32(File.FileType.sync.rawValue))
    XCTAssertTrue(socket.write(setType))
    _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

    let setPermissions = P7Message(withName: "wired.file.set_permissions", spec: socket.spec)
    setPermissions.addParameter(field: "wired.file.path", value: path)
    setPermissions.addParameter(field: "wired.file.owner", value: owner)
    setPermissions.addParameter(field: "wired.file.group", value: group)
    setPermissions.addParameter(field: "wired.file.owner.read", value: true)
    setPermissions.addParameter(field: "wired.file.owner.write", value: true)
    setPermissions.addParameter(field: "wired.file.group.read", value: true)
    setPermissions.addParameter(field: "wired.file.group.write", value: true)
    setPermissions.addParameter(field: "wired.file.everyone.read", value: true)
    setPermissions.addParameter(field: "wired.file.everyone.write", value: true)
    XCTAssertTrue(socket.write(setPermissions))
    _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

    let setPolicy = P7Message(withName: "wired.file.set_sync_policy", spec: socket.spec)
    setPolicy.addParameter(field: "wired.file.path", value: path)
    setPolicy.addParameter(field: "wired.file.sync.user_mode", value: userMode)
    setPolicy.addParameter(field: "wired.file.sync.group_mode", value: groupMode)
    setPolicy.addParameter(field: "wired.file.sync.everyone_mode", value: everyoneMode)
    setPolicy.addParameter(field: "wired.file.sync.max_file_size_bytes", value: maxFileSizeBytes)
    setPolicy.addParameter(field: "wired.file.sync.max_tree_size_bytes", value: maxTreeSizeBytes)
    if !excludePatterns.isEmpty {
        setPolicy.addParameter(field: "wired.file.sync.exclude_patterns", value: excludePatterns)
    }
    XCTAssertTrue(socket.write(setPolicy))
    _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)
}

@discardableResult
func uploadFile(socket: P7Socket, path: String, data: Data) throws -> String {
    let uploadFile = P7Message(withName: "wired.transfer.upload_file", spec: socket.spec)
    uploadFile.addParameter(field: "wired.file.path", value: path)
    uploadFile.addParameter(field: "wired.transfer.data_size", value: UInt64(data.count))
    uploadFile.addParameter(field: "wired.transfer.rsrc_size", value: UInt64(0))
    XCTAssertTrue(socket.write(uploadFile))

    let uploadReady = try readMessage(from: socket, expectedNames: ["wired.transfer.upload_ready", "wired.error"], maxReads: 40)
    if uploadReady.name == "wired.error" {
        let errorString = uploadReady.string(forField: "wired.error.string") ?? "wired.error.unknown"
        throw NSError(domain: "IntegrationUpload", code: 1, userInfo: [NSLocalizedDescriptionKey: "upload_file failed for \(path): \(errorString)"])
    }
    let resolvedPath = uploadReady.string(forField: "wired.file.path") ?? path
    let offset = uploadReady.uint64(forField: "wired.transfer.data_offset") ?? 0
    XCTAssertLessThanOrEqual(offset, UInt64(data.count))

    let uploadGo = P7Message(withName: "wired.transfer.upload", spec: socket.spec)
    uploadGo.addParameter(field: "wired.transfer.data", value: UInt64(data.count) - offset)
    uploadGo.addParameter(field: "wired.transfer.rsrc", value: UInt64(0))
    XCTAssertTrue(socket.write(uploadGo))
    let payload = data.subdata(in: Int(offset)..<data.count)
    try socket.writeOOB(data: payload, timeout: 5)
    usleep(100_000)
    return resolvedPath
}

func waitForExistingPath(_ candidates: [String], timeout: TimeInterval) -> String? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        usleep(50_000)
    }
    return nil
}

func snapshotTree(rootURL: URL) throws -> [String: SyncTreeEntry] {
    var result: [String: SyncTreeEntry] = [:]
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
        return result
    }

    for case let url as URL in enumerator {
        let relativePath = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        if relativePath.contains("/.wired") || relativePath.hasPrefix(".wired") {
            continue
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        result["/" + relativePath] = SyncTreeEntry(
            relativePath: "/" + relativePath,
            isDirectory: values.isDirectory ?? false,
            size: UInt64(values.fileSize ?? 0)
        )
    }
    return result
}

func waitForNoPartialTransferFiles(rootURL: URL, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil)
        var foundPartial = false
        while let item = enumerator?.nextObject() as? URL {
            if item.lastPathComponent.hasSuffix(".WiredTransfer") {
                foundPartial = true
                break
            }
        }
        if !foundPartial {
            return true
        }
        usleep(50_000)
    }
    return false
}
