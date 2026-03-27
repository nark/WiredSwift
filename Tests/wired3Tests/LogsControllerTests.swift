import XCTest
import SocketSwift
import WiredSwift
@testable import wired3Lib

final class LogsControllerTests: XCTestCase {
    func testGetLogReplaysEntriesThenDoneForPrivilegedUser() throws {
        let appContext = try makeAppContext()
        let sockets = try makeConnectedP7Pair(spec: appContext.app.spec)
        defer { closeSockets(sockets) }

        let controller = LogsController()
        let client = makeLoggedInClient(socket: sockets.server, username: "admin", canViewLog: true)

        let date1 = Date(timeIntervalSince1970: 1_000)
        let date2 = Date(timeIntervalSince1970: 2_000)
        controller.loggerDidLog(level: .INFO, message: "first", date: date1)
        controller.loggerDidLog(level: .ERROR, message: "second", date: date2)

        let request = P7Message(withName: "wired.log.get_log", spec: appContext.app.spec)
        request.addParameter(field: "wired.transaction", value: UInt32(9))

        controller.getLog(client: client, message: request)

        let first = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        let second = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        let done = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)

        XCTAssertEqual(first.name, "wired.log.list")
        XCTAssertEqual(first.string(forField: "wired.log.message"), "first")
        XCTAssertEqual(first.uint32(forField: "wired.log.level"), 1)
        XCTAssertEqual(first.uint32(forField: "wired.transaction"), 9)

        XCTAssertEqual(second.name, "wired.log.list")
        XCTAssertEqual(second.string(forField: "wired.log.message"), "second")
        XCTAssertEqual(second.uint32(forField: "wired.log.level"), 3)
        XCTAssertEqual(second.uint32(forField: "wired.transaction"), 9)

        XCTAssertEqual(done.name, "wired.log.list.done")
        XCTAssertEqual(done.uint32(forField: "wired.transaction"), 9)
    }

    func testSubscribeAndUnsubscribeValidatePermissionsAndState() throws {
        let appContext = try makeAppContext()
        let sockets = try makeConnectedP7Pair(spec: appContext.app.spec)
        defer { closeSockets(sockets) }

        let controller = LogsController()
        let request = P7Message(withName: "wired.log.subscribe", spec: appContext.app.spec)
        request.addParameter(field: "wired.transaction", value: UInt32(3))

        let noUserClient = Client(userID: 1, socket: sockets.server)
        noUserClient.state = .LOGGED_IN
        controller.subscribe(client: noUserClient, message: request)
        let noUserReply = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(noUserReply.name, "wired.error")

        let noPrivilegeClient = makeLoggedInClient(socket: sockets.server, username: "user", canViewLog: false)
        controller.subscribe(client: noPrivilegeClient, message: request)
        let noPrivilegeReply = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(noPrivilegeReply.name, "wired.error")

        let allowedClient = makeLoggedInClient(socket: sockets.server, username: "admin", canViewLog: true)
        controller.subscribe(client: allowedClient, message: request)
        let okReply = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(okReply.name, "wired.okay")
        XCTAssertTrue(allowedClient.isSubscribedToLog)

        controller.subscribe(client: allowedClient, message: request)
        let alreadySubscribedReply = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(alreadySubscribedReply.name, "wired.error")

        let unsubscribeRequest = P7Message(withName: "wired.log.unsubscribe", spec: appContext.app.spec)
        unsubscribeRequest.addParameter(field: "wired.transaction", value: UInt32(4))
        controller.unsubscribe(client: allowedClient, message: unsubscribeRequest)
        let unsubscribeOK = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(unsubscribeOK.name, "wired.okay")
        XCTAssertFalse(allowedClient.isSubscribedToLog)

        controller.unsubscribe(client: allowedClient, message: unsubscribeRequest)
        let notSubscribedReply = try sockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(notSubscribedReply.name, "wired.error")
    }

    func testLoggerDidLogBroadcastsOnlyToSubscribedPrivilegedClients() throws {
        let appContext = try makeAppContext()

        let subscriberSockets = try makeConnectedP7Pair(spec: appContext.app.spec)
        let otherSockets = try makeConnectedP7Pair(spec: appContext.app.spec)
        defer {
            closeSockets(subscriberSockets)
            closeSockets(otherSockets)
        }

        let subscriber = makeLoggedInClient(userID: 10, socket: subscriberSockets.server, username: "admin", canViewLog: true)
        subscriber.isSubscribedToLog = true

        let other = makeLoggedInClient(userID: 11, socket: otherSockets.server, username: "other", canViewLog: true)
        other.isSubscribedToLog = false

        appContext.app.clientsController.addClient(client: subscriber)
        appContext.app.clientsController.addClient(client: other)

        let controller = LogsController()
        controller.loggerDidLog(level: .WARNING, message: "watch", date: Date(timeIntervalSince1970: 42))

        let broadcast = try subscriberSockets.peer.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(broadcast.name, "wired.log.message")
        XCTAssertEqual(broadcast.string(forField: "wired.log.message"), "watch")
        XCTAssertEqual(broadcast.uint32(forField: "wired.log.level"), 2)

        XCTAssertThrowsError(try otherSockets.peer.readMessage(timeout: 0.2, enforceDeadline: true))
    }

    func testLoggerDidLogTrimsCircularBufferAfterOverflowThreshold() {
        _ = try? makeAppContext()
        let controller = LogsController()

        for i in 0..<650 {
            controller.loggerDidLog(level: .DEBUG, message: "m\(i)", date: Date())
        }

        let mirror = Mirror(reflecting: controller)
        let entries = mirror.children.first(where: { $0.label == "entries" })?.value as? [LogsController.LogEntry]
        XCTAssertEqual(entries?.count, 550)
    }

    private typealias P7Pair = (server: P7Socket, peer: P7Socket, listener: Socket)

    private func makeAppContext() throws -> (app: AppController, workingDir: URL, previous: AppController?) {
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
        app.serverController = ServerController(port: 0, spec: app.spec)

        addTeardownBlock {
            App = previous
            try? FileManager.default.removeItem(at: workingDir)
        }

        return (app, workingDir, previous)
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

    private func makeLoggedInClient(userID: UInt32 = 1, socket: P7Socket, username: String, canViewLog: Bool) -> Client {
        let client = Client(userID: userID, socket: socket)
        client.state = .LOGGED_IN

        let user = User(username: username, password: "password")
        user.id = 1
        if canViewLog {
            user.privileges = [UserPrivilege(name: "wired.account.log.view_log", value: true, userId: 1)]
        } else {
            user.privileges = [UserPrivilege(name: "wired.account.log.view_log", value: false, userId: 1)]
        }
        client.user = user
        return client
    }

    private func wiredSpecPath() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/wired3/wired.xml")
            .path
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
