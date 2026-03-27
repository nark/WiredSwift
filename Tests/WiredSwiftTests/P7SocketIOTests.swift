import XCTest
import SocketSwift
@testable import WiredSwift

final class P7SocketIOTests: XCTestCase {
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

    func testWriteAndReadMessageRoundTripAcrossLocalSocketPair() throws {
        let pair = try makeConnectedPair()

        let outgoing = P7Message(withName: "wired.user.get_info", spec: spec)
        outgoing.addParameter(field: "wired.user.id", value: UInt32(42))

        XCTAssertTrue(pair.client.write(outgoing))
        let incoming = try pair.server.readMessage(timeout: 1.0, enforceDeadline: true)

        XCTAssertEqual(incoming.name, "wired.user.get_info")
        XCTAssertEqual(incoming.uint32(forField: "wired.user.id"), 42)
    }

    func testWriteAndReadOOBRoundTripAcrossLocalSocketPair() throws {
        let pair = try makeConnectedPair()
        let payload = Data("hello-oob".utf8)

        try pair.client.writeOOB(data: payload, timeout: 1.0)
        let received = try pair.server.readOOB(timeout: 1.0)

        XCTAssertEqual(received, payload)
    }

    func testReadMessageRejectsFrameSmallerThanMessageID() throws {
        let pair = try makeConnectedPair()
        var rawLength = Data()
        rawLength.append(uint32: UInt32(0), bigEndian: true)

        try pair.client.getNativeSocket()?.write(Array(rawLength))

        XCTAssertThrowsError(try pair.server.readMessage(timeout: 1.0, enforceDeadline: true))
    }

    func testReadMessageThrowsWhenSerializationIsNotBinary() {
        let socket = P7Socket(hostname: "localhost", port: 0, spec: spec)
        socket.connected = true
        socket.serialization = .XML

        XCTAssertThrowsError(try socket.readMessage(timeout: 0.1, enforceDeadline: true))
    }

    func testWriteOOBThrowsWhenDisconnected() {
        let socket = P7Socket(hostname: "localhost", port: 0, spec: spec)
        socket.connected = false

        XCTAssertThrowsError(try socket.writeOOB(data: Data([0x01]), timeout: 0.1))
    }

    func testChecksumLengthForAllSupportedAlgorithms() {
        let socket = P7Socket(hostname: "localhost", port: 0, spec: spec)

        XCTAssertEqual(socket.checksumLength(.NONE), 0)
        XCTAssertEqual(socket.checksumLength(.SHA2_256), 32)
        XCTAssertEqual(socket.checksumLength(.SHA2_384), 48)
        XCTAssertEqual(socket.checksumLength(.SHA3_256), 32)
        XCTAssertEqual(socket.checksumLength(.SHA3_384), 48)
        XCTAssertEqual(socket.checksumLength(.HMAC_256), 32)
        XCTAssertEqual(socket.checksumLength(.HMAC_384), 48)
    }

    func testSetInteractiveWithoutNativeSocketStillUpdatesFlag() throws {
        let socket = P7Socket(hostname: "localhost", port: 0, spec: spec)
        XCTAssertTrue(socket.isInteractive())

        try socket.set(interactive: false)
        XCTAssertFalse(socket.isInteractive())

        try socket.set(interactive: true)
        XCTAssertTrue(socket.isInteractive())
    }

    func testDisconnectResetsRuntimeStateFlags() {
        let socket = P7Socket(hostname: "localhost", port: 0, spec: spec)
        socket.connected = true
        socket.compressionEnabled = true
        socket.compressionConfigured = true
        socket.encryptionEnabled = true
        socket.checksumEnabled = true
        socket.localCompatibilityCheck = true
        socket.remoteCompatibilityCheck = true
        socket.ecdh = ECDH()

        socket.disconnect()

        XCTAssertFalse(socket.connected)
        XCTAssertFalse(socket.compressionEnabled)
        XCTAssertFalse(socket.compressionConfigured)
        XCTAssertFalse(socket.encryptionEnabled)
        XCTAssertFalse(socket.checksumEnabled)
        XCTAssertFalse(socket.localCompatibilityCheck)
        XCTAssertFalse(socket.remoteCompatibilityCheck)
        XCTAssertNil(socket.ecdh)
    }

    func testClientAddressAndPeerHelpersReturnNilWhenSocketIsMissing() {
        let socket = P7Socket(hostname: "localhost", port: 0, spec: spec)
        XCTAssertNil(socket.clientAddress())
        XCTAssertNil(socket.getClientIP())
        XCTAssertNil(socket.getClientHostname())
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
}
