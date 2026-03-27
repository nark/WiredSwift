import XCTest
@testable import WiredSwift
import SocketSwift

final class NetworkLayerTests: XCTestCase {
    private var spec: P7Spec!

    override func setUpWithError() throws {
        let xmlURL = try XCTUnwrap(
            Bundle.module.url(forResource: "wired", withExtension: "xml"),
            "wired.xml not found in test bundle"
        )
        spec = try XCTUnwrap(
            P7Spec(withUrl: xmlURL),
            "Failed to load P7Spec from wired.xml"
        )
    }

    func testConnectionAddAndRemoveDelegateAvoidsDuplicates() {
        let connection = Connection(withSpec: spec)
        let spy = DelegateSpy()

        connection.addDelegate(spy)
        connection.addDelegate(spy)
        XCTAssertEqual(connection.delegates.count, 1)

        connection.removeDelegate(spy)
        XCTAssertEqual(connection.delegates.count, 0)
    }

    func testConnectionHasPrivilegeAndAdministrationPrivileges() {
        let connection = Connection(withSpec: spec)
        connection.privileges = ["wired.account.user.get_users"]

        XCTAssertTrue(connection.hasPrivilege(key: "wired.account.user.get_users"))
        XCTAssertFalse(connection.hasPrivilege(key: "wired.account.log.view_log"))
        XCTAssertTrue(connection.hasAdministrationPrivileges())
    }

    func testConnectionHasAdministrationPrivilegesFalseWhenNoAdminFlags() {
        let connection = Connection(withSpec: spec)
        connection.privileges = ["wired.chat.say"]
        XCTAssertFalse(connection.hasAdministrationPrivileges())
    }

    func testConnectionSendDisconnectedReturnsFalseAndKeepsTransactionCounter() {
        let connection = Connection(withSpec: spec)
        connection.socket = makeSocket(connected: false)

        let message = P7Message(withName: "wired.send_ping", spec: spec)
        let initialCounter = connection.transactionCounter

        XCTAssertFalse(connection.send(message: message))
        XCTAssertEqual(connection.transactionCounter, initialCounter)
        XCTAssertNil(message.uint32(forField: "wired.transaction"))
    }

    func testConnectionSendConnectedIncrementsTransactionAndNotifiesDelegate() {
        let connection = Connection(withSpec: spec)
        let spy = DelegateSpy()
        let didSend = expectation(description: "delegate did send")
        spy.onDidSend = { _ in didSend.fulfill() }
        connection.addDelegate(spy)
        connection.socket = makeSocket(connected: true)

        let message = P7Message(withName: "wired.send_ping", spec: spec)
        let initialCounter = connection.transactionCounter

        XCTAssertFalse(connection.send(message: message), "Socket write is expected to fail in tests")
        XCTAssertEqual(connection.transactionCounter, initialCounter + 1)
        XCTAssertEqual(message.uint32(forField: "wired.transaction"), initialCounter)

        wait(for: [didSend], timeout: 1.0)
    }

    func testConnectionJoinChatDisconnectedReturnsFalse() {
        let connection = Connection(withSpec: spec)
        connection.socket = makeSocket(connected: false)
        XCTAssertFalse(connection.joinChat(chatID: 99))
    }

    func testConnectionJoinChatConnectedSendsExpectedMessage() {
        let connection = Connection(withSpec: spec)
        connection.socket = makeSocket(connected: true)
        let spy = DelegateSpy()
        let didSend = expectation(description: "join chat sent")
        spy.onDidSend = { message in
            XCTAssertEqual(message.name, "wired.chat.join_chat")
            XCTAssertEqual(message.uint32(forField: "wired.chat.id"), 12)
            didSend.fulfill()
        }
        connection.addDelegate(spy)

        XCTAssertFalse(connection.joinChat(chatID: 12), "socket write is expected to fail in test mode")
        wait(for: [didSend], timeout: 1.0)
    }

    func testConnectionHandleErrorMessageNotifiesErrorDelegate() {
        let connection = Connection(withSpec: spec)
        let spy = DelegateSpy()
        let didReceiveError = expectation(description: "delegate did receive error")
        spy.onDidReceiveError = { _ in didReceiveError.fulfill() }
        connection.addDelegate(spy)

        let message = P7Message(withName: "wired.error", spec: spec)
        message.addParameter(field: "wired.error", value: "wired.error.invalid_message")

        connection.handleMessage(message)
        wait(for: [didReceiveError], timeout: 1.0)
    }

    func testConnectionHandleServerInfoUpdatesStateAndNotifies() {
        let connection = Connection(withSpec: spec)
        let delegateSpy = DelegateSpy()
        let serverInfoSpy = ServerInfoSpy()
        let didReceive = expectation(description: "delegate did receive")
        let didChange = expectation(description: "server info did change")

        delegateSpy.onDidReceiveMessage = { _ in didReceive.fulfill() }
        serverInfoSpy.onDidChange = { didChange.fulfill() }

        connection.addDelegate(delegateSpy)
        connection.serverInfoDelegate = serverInfoSpy

        let message = P7Message(withName: "wired.server_info", spec: spec)
        message.addParameter(field: "wired.info.name", value: "My Server")
        message.addParameter(field: "wired.info.application.version", value: "3.0")

        connection.handleMessage(message)

        wait(for: [didReceive, didChange], timeout: 1.0)
        XCTAssertEqual(connection.serverInfo?.serverName, "My Server")
        XCTAssertEqual(connection.serverInfo?.applicationVersion, "3.0")
    }

    func testConnectionHandleRegularMessageNotifiesReceiveDelegate() {
        let connection = Connection(withSpec: spec)
        let spy = DelegateSpy()
        let didReceive = expectation(description: "did receive regular message")
        spy.onDidReceiveMessage = { message in
            XCTAssertEqual(message.name, "wired.chat.get_chats")
            didReceive.fulfill()
        }
        connection.addDelegate(spy)

        let message = P7Message(withName: "wired.chat.get_chats", spec: spec)
        connection.handleMessage(message)

        wait(for: [didReceive], timeout: 1.0)
    }

    func testConnectionHandlePingTriggersPingReplySend() {
        let connection = Connection(withSpec: spec)
        connection.socket = makeSocket(connected: true)
        let spy = DelegateSpy()
        let didSend = expectation(description: "did send ping reply")
        spy.onDidSend = { message in
            XCTAssertEqual(message.name, "wired.ping")
            didSend.fulfill()
        }
        connection.addDelegate(spy)

        let ping = P7Message(withName: "wired.send_ping", spec: spec)
        connection.handleMessage(ping)

        wait(for: [didSend], timeout: 1.0)
    }

    func testConnectionDisconnectPostsNotificationsEvenWhenSocketIsNil() {
        let connection = Connection(withSpec: spec)
        connection.socket = nil

        let willDisconnect = expectation(forNotification: .linkConnectionWillDisconnect, object: connection)
        let didClose = expectation(forNotification: .linkConnectionDidClose, object: connection)

        connection.disconnect()
        wait(for: [willDisconnect, didClose], timeout: 1.0)
    }

    func testConnectionURIRendersLoginHostAndPort() {
        let connection = Connection(withSpec: spec)
        connection.url = Url(withString: "wired://alice:secret@localhost:4871")
        XCTAssertEqual(connection.URI, "alice@localhost:4871")
    }

    func testConnectionRemoveDelegateIgnoresUnknownDelegate() {
        let connection = Connection(withSpec: spec)
        let first = DelegateSpy()
        let second = DelegateSpy()
        connection.addDelegate(first)
        connection.removeDelegate(second)
        XCTAssertEqual(connection.delegates.count, 1)
    }

    func testConnectionConnectCompletesHandshakeUserSetupAndLoginFlow() throws {
        let listener = try Socket.tcpListening(port: 0, address: "127.0.0.1")
        let port = Int(try listener.port())
        let serverSpec = try XCTUnwrap(P7Spec(withUrl: try XCTUnwrap(Bundle.module.url(forResource: "wired", withExtension: "xml"))))

        var serverError: Error?
        let serverDone = expectation(description: "server done")
        DispatchQueue.global().async {
            defer { serverDone.fulfill() }
            do {
                let native = try listener.accept()
                let serverSocket = P7Socket(socket: native, spec: serverSpec)
                try serverSocket.accept(compression: .NONE, cipher: .NONE, checksum: .NONE)
                try self.serveOneConnectionSession(socket: serverSocket, spec: serverSpec, userID: 123)
                serverSocket.disconnect()
            } catch {
                serverError = error
            }
        }

        let spy = DelegateSpy()
        let didLogin = expectation(description: "did login")
        let didPrivileges = expectation(description: "did privileges")
        spy.onDidLogin = { message in
            XCTAssertEqual(message.uint32(forField: "wired.user.id"), 123)
            didLogin.fulfill()
        }
        spy.onDidReceivePrivileges = { _ in
            didPrivileges.fulfill()
        }

        let connection = Connection(withSpec: spec, delegate: spy)
        connection.interactive = false
        let url = Url(withString: "wired://alice:secret@127.0.0.1:\(port)")
        try connection.connect(withUrl: url, cipher: .NONE, compression: .NONE, checksum: .NONE)

        wait(for: [didLogin, didPrivileges, serverDone], timeout: 5.0)
        XCTAssertNil(serverError)
        XCTAssertEqual(connection.userID, 123)
        XCTAssertEqual(connection.serverInfo?.serverName, "Test Wired")
        XCTAssertTrue(connection.privileges.contains("wired.account.settings.get_settings"))

        connection.disconnect()
        listener.close()
    }

    func testConnectionReconnectReestablishesSession() throws {
        let listener = try Socket.tcpListening(port: 0, address: "127.0.0.1")
        let port = Int(try listener.port())
        let serverSpec = try XCTUnwrap(P7Spec(withUrl: try XCTUnwrap(Bundle.module.url(forResource: "wired", withExtension: "xml"))))

        var serverError: Error?
        let serverDone = expectation(description: "server done twice")
        DispatchQueue.global().async {
            defer { serverDone.fulfill() }
            do {
                for userID: UInt32 in [101, 202] {
                    let native = try listener.accept()
                    let serverSocket = P7Socket(socket: native, spec: serverSpec)
                    try serverSocket.accept(compression: .NONE, cipher: .NONE, checksum: .NONE)
                    try self.serveOneConnectionSession(socket: serverSocket, spec: serverSpec, userID: userID)
                    serverSocket.disconnect()
                }
            } catch {
                serverError = error
            }
        }

        let connection = Connection(withSpec: spec)
        connection.interactive = false
        let url = Url(withString: "wired://alice:secret@127.0.0.1:\(port)")

        try connection.connect(withUrl: url, cipher: .NONE, compression: .NONE, checksum: .NONE)
        XCTAssertEqual(connection.userID, 101)

        try connection.reconnect()
        XCTAssertEqual(connection.userID, 202)

        wait(for: [serverDone], timeout: 5.0)
        XCTAssertNil(serverError)

        connection.disconnect()
        listener.close()
    }

    func testConnectionDisconnectNotifiesDelegates() {
        let connection = Connection(withSpec: spec)
        let spy = DelegateSpy()
        let didDisconnect = expectation(description: "delegate disconnected")
        spy.onDisconnected = { error in
            XCTAssertNil(error)
            didDisconnect.fulfill()
        }
        connection.addDelegate(spy)

        connection.disconnect()
        wait(for: [didDisconnect], timeout: 1.0)
    }

    func testConnectionIsConnectedReflectsSocketState() {
        let connection = Connection(withSpec: spec)
        XCTAssertFalse(connection.isConnected())

        connection.socket = makeSocket(connected: false)
        XCTAssertFalse(connection.isConnected())

        connection.socket = makeSocket(connected: true)
        XCTAssertTrue(connection.isConnected())
    }

    func testBlockConnectionSendWhenDisconnectedCompletesWithNil() {
        let connection = BlockConnection(withSpec: spec)
        connection.socket = makeSocket(connected: false)

        let done = expectation(description: "completion called")
        let message = P7Message(withName: "wired.chat.get_chats", spec: spec)

        connection.send(message: message) { reply in
            XCTAssertNil(reply)
            done.fulfill()
        }

        wait(for: [done], timeout: 1.0)
    }

    func testBlockConnectionHandleDoneCallsCompletionAndClearsBlocks() {
        let connection = BlockConnection(withSpec: spec)
        let done = expectation(description: "completion called")
        let transaction: UInt32 = 99

        connection.completionBlocks[transaction] = { message in
            XCTAssertEqual(message?.name, "wired.okay")
            done.fulfill()
        }

        let message = P7Message(withName: "wired.okay", spec: spec)
        message.addParameter(field: "wired.transaction", value: transaction)

        connection.handleMessage(message)
        wait(for: [done], timeout: 1.0)
        XCTAssertNil(connection.completionBlocks[transaction])
        XCTAssertNil(connection.progressBlocks[transaction])
    }

    func testBlockConnectionHandleProgressCallsProgressBlock() {
        let connection = BlockConnection(withSpec: spec)
        let progress = expectation(description: "progress called")
        let transaction: UInt32 = 7

        connection.progressBlocks[transaction] = { message in
            XCTAssertEqual(message.name, "wired.chat.chat")
            progress.fulfill()
        }
        connection.completionBlocks[transaction] = { _ in
            XCTFail("completion should not be called on progress message")
        }

        let message = P7Message(withName: "wired.chat.chat", spec: spec)
        message.addParameter(field: "wired.transaction", value: transaction)

        connection.handleMessage(message)
        wait(for: [progress], timeout: 1.0)
    }

    func testAsyncConnectionSendAndWaitManyThrowsWhenDisconnected() {
        let connection = AsyncConnection(withSpec: spec)
        connection.socket = makeSocket(connected: false)

        let message = P7Message(withName: "wired.chat.get_chats", spec: spec)
        XCTAssertThrowsError(try connection.sendAndWaitMany(message)) { error in
            guard case AsyncConnectionError.notConnected = error else {
                return XCTFail("Expected notConnected, got \(error)")
            }
        }
    }

    func testAsyncConnectionSendAndWaitManyWriteFailureFinishesWithError() async throws {
        let connection = AsyncConnection(withSpec: spec)
        connection.socket = makeSocket(connected: true)

        let message = P7Message(withName: "wired.chat.get_chats", spec: spec)
        let stream = try connection.sendAndWaitMany(message)
        var iterator = stream.makeAsyncIterator()

        do {
            _ = try await iterator.next()
            XCTFail("Expected writeFailed error")
        } catch {
            guard case AsyncConnectionError.writeFailed = error else {
                return XCTFail("Expected writeFailed, got \(error)")
            }
        }
    }

    func testAsyncConnectionSendAndWaitManyYieldsAndFinishesOnOkay() async throws {
        let pair = try makeConnectedPair()
        let connection = AsyncConnection(withSpec: spec)
        connection.socket = pair.client

        let request = P7Message(withName: "wired.chat.get_chats", spec: spec)
        let stream = try connection.sendAndWaitMany(request)
        let transaction = try XCTUnwrap(request.uint32(forField: "wired.transaction"))

        let reply = P7Message(withName: "wired.okay", spec: spec)
        reply.addParameter(field: "wired.transaction", value: transaction)
        // Dispatch after iterator.next() suspends so the registration Task runs first
        Task { connection.handleMessage(reply) }

        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first?.name, "wired.okay")
        let second = try await iterator.next()
        XCTAssertNil(second)
    }

    func testAsyncConnectionSendAndWaitManyYieldsAndFinishesOnDoneMessage() async throws {
        let pair = try makeConnectedPair()
        let connection = AsyncConnection(withSpec: spec)
        connection.socket = pair.client

        let request = P7Message(withName: "wired.chat.get_chats", spec: spec)
        let stream = try connection.sendAndWaitMany(request)
        let transaction = try XCTUnwrap(request.uint32(forField: "wired.transaction"))

        let done = P7Message(withName: "wired.chat.chat_list.done", spec: spec)
        done.addParameter(field: "wired.transaction", value: transaction)
        // Dispatch after iterator.next() suspends so the registration Task runs first
        Task { connection.handleMessage(done) }

        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first?.name, "wired.chat.chat_list.done")
        let second = try await iterator.next()
        XCTAssertNil(second)
    }

    func testAsyncConnectionSendAndWaitManyPropagatesServerError() async throws {
        let pair = try makeConnectedPair()
        let connection = AsyncConnection(withSpec: spec)
        connection.socket = pair.client

        let request = P7Message(withName: "wired.chat.get_chats", spec: spec)
        let stream = try connection.sendAndWaitMany(request)
        let transaction = try XCTUnwrap(request.uint32(forField: "wired.transaction"))

        let errorMessage = P7Message(withName: "wired.error", spec: spec)
        errorMessage.addParameter(field: "wired.transaction", value: transaction)
        errorMessage.addParameter(field: "wired.error", value: "wired.error.invalid_message")
        connection.handleMessage(errorMessage)

        var iterator = stream.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            XCTFail("Expected AsyncConnectionError.serverError")
        } catch let error as AsyncConnectionError {
            guard case .serverError(let message) = error else {
                return XCTFail("Expected serverError, got \(error)")
            }
            XCTAssertEqual(message.name, "wired.error")
            XCTAssertEqual(message.string(forField: "wired.error"), "wired.error.invalid_message")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransactionManagerRegisterYieldAndFinish() async throws {
        let manager = TransactionManager()
        let message = P7Message(withName: "wired.okay", spec: spec)
        let transaction: UInt32 = 42

        var continuation: AsyncThrowingStream<P7Message, Error>.Continuation?
        let stream = AsyncThrowingStream<P7Message, Error> { c in
            continuation = c
        }
        let cont = try XCTUnwrap(continuation)
        await manager.register(transaction: transaction, continuation: cont)
        await manager.yield(transaction: transaction, message: message)

        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first?.name, "wired.okay")

        await manager.finish(transaction: transaction)
        let second = try await iterator.next()
        XCTAssertNil(second)
    }

    func testTransactionManagerFailPropagatesThrownError() async throws {
        enum Marker: Error { case boom }

        let manager = TransactionManager()
        let transaction: UInt32 = 43

        var continuation: AsyncThrowingStream<P7Message, Error>.Continuation?
        let stream = AsyncThrowingStream<P7Message, Error> { c in
            continuation = c
        }
        let cont = try XCTUnwrap(continuation)
        await manager.register(transaction: transaction, continuation: cont)
        await manager.fail(transaction: transaction, error: Marker.boom)

        var iterator = stream.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            XCTFail("Expected thrown Marker.boom")
        } catch {
            guard case Marker.boom = error else {
                return XCTFail("Expected Marker.boom, got \(error)")
            }
        }
    }

    func testSpeedCalculatorUsesRollingWindowAndAverage() {
        let calculator = SpeedCalculator()

        for i in 1...60 {
            calculator.add(bytes: i, time: 1)
        }

        // Keeps only the last 50 values: 11...60
        XCTAssertEqual(calculator.speed(), 35.5, accuracy: 0.0001)
    }

    func testNetworkErrorFromErrnoMappingsAndDescriptions() {
        XCTAssertEqual(NetworkError.fromErrno(ECONNREFUSED, host: "h", port: 1), .connectionRefused(host: "h", port: 1))
        XCTAssertEqual(NetworkError.fromErrno(ETIMEDOUT, host: "h", port: 1), .connectionTimedOut(host: "h", port: 1))
        XCTAssertEqual(NetworkError.fromErrno(ENETUNREACH, host: "h", port: 1), .networkUnreachable)
        XCTAssertEqual(NetworkError.fromErrno(EHOSTUNREACH, host: "h", port: 1), .hostUnreachable(host: "h"))
        XCTAssertEqual(NetworkError.fromErrno(EPIPE, host: "h", port: 1), .brokenPipe)
        XCTAssertEqual(NetworkError.fromErrno(EINTR, host: "h", port: 1), .interrupted)
        XCTAssertEqual(NetworkError.fromErrno(EACCES, host: "h", port: 1), .permissionDenied)
        XCTAssertEqual(NetworkError.fromErrno(ENOMEM, host: "h", port: 1), .noMemory)
        XCTAssertEqual(NetworkError.fromErrno(-12345, host: "h", port: 1), .unknown(errno: -12345))

        XCTAssertEqual(NetworkError.connectionRefused(host: "x", port: 4871).errorDescription, "Connection refused by x:4871")
        XCTAssertEqual(NetworkError.networkUnreachable.errorDescription, "Network is unreachable")
        XCTAssertEqual(NetworkError.notConnected.errorDescription, "Socket is not connected")
        XCTAssertEqual(NetworkError.unknown(errno: 99).errorDescription, "Unknown network error (errno 99)")
    }

    private func makeSocket(connected: Bool) -> P7Socket {
        let socket = P7Socket(hostname: "localhost", port: 0, spec: spec)
        socket.connected = connected
        return socket
    }

    private func makeConnectedPair() throws -> (client: P7Socket, server: P7Socket, listener: Socket) {
        let listener = try Socket.tcpListening(port: 0, address: "127.0.0.1")
        let port = Int(try listener.port())

        var acceptedSocket: Socket?
        let accepted = expectation(description: "accepted")
        DispatchQueue.global().async {
            acceptedSocket = try? listener.accept()
            accepted.fulfill()
        }

        let client = P7Socket(hostname: "127.0.0.1", port: port, spec: spec)
        try client.connect(withHandshake: false)

        wait(for: [accepted], timeout: 2.0)
        let serverNative = try XCTUnwrap(acceptedSocket)
        let server = P7Socket(socket: serverNative, spec: spec)

        addTeardownBlock {
            client.disconnect()
            server.disconnect()
            listener.close()
        }

        return (client, server, listener)
    }

    private func serveOneConnectionSession(socket: P7Socket, spec: P7Spec, userID: UInt32) throws {
        _ = try socket.readMessage(timeout: 2.0, enforceDeadline: true) // wired.client_info

        let serverInfo = P7Message(withName: "wired.server_info", spec: spec)
        serverInfo.addParameter(field: "wired.info.name", value: "Test Wired")
        serverInfo.addParameter(field: "wired.info.application.version", value: "3.1")
        _ = socket.write(serverInfo)

        for _ in 0..<3 { // set_nick, set_status, set_icon
            _ = try socket.readMessage(timeout: 2.0, enforceDeadline: true)
            _ = socket.write(P7Message(withName: "wired.okay", spec: spec))
        }

        _ = try socket.readMessage(timeout: 2.0, enforceDeadline: true) // wired.send_login
        let loginReply = P7Message(withName: "wired.okay", spec: spec)
        loginReply.addParameter(field: "wired.user.id", value: userID)
        _ = socket.write(loginReply)

        let privileges = P7Message(withName: "wired.okay", spec: spec)
        privileges.addParameter(field: "wired.account.settings.get_settings", value: UInt32(1))
        _ = socket.write(privileges)
    }
}

private final class DelegateSpy: ConnectionDelegate {
    var onDidSend: ((P7Message) -> Void)?
    var onDidReceiveMessage: ((P7Message) -> Void)?
    var onDidReceiveError: ((P7Message) -> Void)?
    var onDisconnected: ((Error?) -> Void)?
    var onDidLogin: ((P7Message) -> Void)?
    var onDidReceivePrivileges: ((P7Message) -> Void)?

    func connectionDidConnect(connection: Connection) {}
    func connectionDidFailToConnect(connection: Connection, error: Error) {}
    func connectionDisconnected(connection: Connection, error: Error?) {
        onDisconnected?(error)
    }
    func connectionDidLogin(connection: Connection, message: P7Message) {
        onDidLogin?(message)
    }
    func connectionDidReceivePriviledges(connection: Connection, message: P7Message) {
        onDidReceivePrivileges?(message)
    }

    func connectionDidSendMessage(connection: Connection, message: P7Message) {
        onDidSend?(message)
    }

    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        onDidReceiveMessage?(message)
    }

    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        onDidReceiveError?(message)
    }
}

private final class ServerInfoSpy: ServerInfoDelegate {
    var onDidChange: (() -> Void)?

    func serverInfoDidChange(for connection: Connection) {
        onDidChange?()
    }
}
