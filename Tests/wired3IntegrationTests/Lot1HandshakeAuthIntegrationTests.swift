import XCTest
import WiredSwift

final class Lot1HandshakeAuthIntegrationTests: SerializedIntegrationTestCase {
    func testHandshakeClientInfoAndGuestLoginSucceed() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "guest", password: "")
        defer { socket.disconnect() }

        try sendClientInfoAndExpectServerInfo(socket: socket)
        let login = try sendLoginAndExpectSuccess(socket: socket, username: "guest", password: "")
        XCTAssertNotNil(login.uint32(forField: "wired.user.id"))
    }

    func testConnectionWithoutRequiredEncryptionIsRejected() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        defer { try? runtime.stop() }

        let spec = P7Spec(withPath: runtime.specPath)
        let insecure = P7Socket(hostname: "127.0.0.1", port: runtime.port, spec: spec)
        insecure.cipherType = .NONE
        insecure.checksum = .NONE
        insecure.compression = .NONE
        insecure.username = "guest"
        insecure.password = ""

        XCTAssertThrowsError(try insecure.connect())
    }

    func testLoginWithBadPasswordReturnsWiredError() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "guest", password: "")
        defer { socket.disconnect() }

        try sendClientInfoAndExpectServerInfo(socket: socket)
        let response = try sendLoginAndExpectError(socket: socket, username: "guest", password: "wrong")
        XCTAssertEqual(response.name, "wired.error")
    }

    func testOutOfSequenceMessageBeforeClientInfoReturnsError() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "guest", password: "")
        defer { socket.disconnect() }

        let message = P7Message(withName: "wired.chat.get_chats", spec: socket.spec)
        XCTAssertTrue(socket.write(message))

        let response = try readMessage(from: socket, expectedName: "wired.error", maxReads: 6)
        XCTAssertEqual(response.name, "wired.error")
    }

    func testSecondLoginAttemptAfterSuccessfulLoginReturnsOutOfSequenceError() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "guest", password: "")
        defer { socket.disconnect() }

        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "guest", password: "")
        drainMessages(socket: socket)

        let retry = try sendLoginAndExpectError(socket: socket, username: "guest", password: "")
        XCTAssertEqual(retry.name, "wired.error")
        XCTAssertEqual(retry.string(forField: "wired.error.string"), "wired.error.message_out_of_sequence")
    }
}
