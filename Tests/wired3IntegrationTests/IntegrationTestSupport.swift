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

private let integrationServerLock = NSLock()
private let installSIGPIPEIgnore: Void = {
    #if canImport(Darwin)
    _ = Darwin.signal(SIGPIPE, SIG_IGN)
    #else
    _ = Glibc.signal(SIGPIPE, SIG_IGN)
    #endif
}()

func integrationPackageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

func findAvailableLoopbackPort() throws -> Int {
    let fd = socket(AF_INET, Int32(SOCK_STREAM), 0)
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
        let fd = socket(AF_INET, Int32(SOCK_STREAM), 0)
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
        self.specPath = integrationPackageRoot().appendingPathComponent("Sources/wired3/wired.xml").path
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

        let timeoutResult = serverStopped.wait(timeout: .now() + 10)
        guard timeoutResult == .success else {
            integrationServerLock.unlock()
            throw IntegrationTestError.serverStopTimedOut
        }

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
    for _ in 0..<maxReads {
        do {
            let message = try socket.readMessage(timeout: timeout, enforceDeadline: true)
            if let name = message.name, expectedNames.contains(name) {
                return message
            }
        } catch {
            // Integration streams can be briefly idle between async server pushes.
            // Keep polling until maxReads is reached.
            continue
        }
    }

    XCTFail("Expected one of \(expectedNames.sorted()) within \(maxReads) reads")
    return P7Message(withName: "wired.error", spec: socket.spec)
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
