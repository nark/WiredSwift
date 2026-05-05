import XCTest
import SocketSwift
@testable import WiredSwift

final class P7SocketIOTests: XCTestCase {
    private var spec: P7Spec!

    override func setUpWithError() throws {
        spec = try XCTUnwrap(P7Spec(withUrl: TestResources.specURL),
                              "Failed to load bundled wired.xml")
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

    func testWriteAndReadMessageWithDeflateCompression() throws {
        let pair = try makeConnectedPair()
        pair.client.compression = .DEFLATE
        pair.server.compression = .DEFLATE
        pair.client.compressionEnabled = true
        pair.server.compressionEnabled = true

        let outgoing = P7Message(withName: "wired.user.get_info", spec: spec)
        outgoing.addParameter(field: "wired.user.id", value: UInt32(77))

        XCTAssertTrue(pair.client.write(outgoing))
        let incoming = try pair.server.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(incoming.uint32(forField: "wired.user.id"), 77)
    }

    func testWriteAndReadMessageWithLZ4Compression() throws {
        let pair = try makeConnectedPair()
        pair.client.compression = .LZ4
        pair.server.compression = .LZ4
        pair.client.compressionEnabled = true
        pair.server.compressionEnabled = true

        let outgoing = P7Message(withName: "wired.user.get_info", spec: spec)
        outgoing.addParameter(field: "wired.user.id", value: UInt32(88))

        XCTAssertTrue(pair.client.write(outgoing))
        let incoming = try pair.server.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(incoming.uint32(forField: "wired.user.id"), 88)
    }

    func testWriteAndReadMessageWithChecksum() throws {
        let pair = try makeConnectedPair()
        pair.client.checksum = .SHA2_256
        pair.server.checksum = .SHA2_256
        pair.client.checksumEnabled = true
        pair.server.checksumEnabled = true

        let outgoing = P7Message(withName: "wired.user.get_info", spec: spec)
        outgoing.addParameter(field: "wired.user.id", value: UInt32(91))

        XCTAssertTrue(pair.client.write(outgoing))
        let incoming = try pair.server.readMessage(timeout: 1.0, enforceDeadline: true)
        XCTAssertEqual(incoming.uint32(forField: "wired.user.id"), 91)
    }

    func testWriteAndReadOOBRoundTripAcrossLocalSocketPair() throws {
        let pair = try makeConnectedPair()
        let payload = Data("hello-oob".utf8)

        try pair.client.writeOOB(data: payload, timeout: 1.0)
        let received = try pair.server.readOOB(timeout: 1.0)

        XCTAssertEqual(received, payload)
    }

    func testWriteAndReadOOBWithChecksum() throws {
        let pair = try makeConnectedPair()
        pair.client.checksum = .SHA2_256
        pair.server.checksum = .SHA2_256
        pair.client.checksumEnabled = true
        pair.server.checksumEnabled = true

        let payload = Data("hello-oob-checksum".utf8)
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

    func testReadMessageRejectsFrameLargerThanMaximum() throws {
        let pair = try makeConnectedPair()
        var rawLength = Data()
        rawLength.append(uint32: (64 * 1024 * 1024) + 1, bigEndian: true)

        try pair.client.getNativeSocket()?.write(Array(rawLength))
        XCTAssertThrowsError(try pair.server.readMessage(timeout: 1.0, enforceDeadline: true))
    }

    func testReadMessageChecksumMismatchThrows() throws {
        let pair = try makeConnectedPair()
        pair.server.checksum = .SHA2_256
        pair.server.checksumEnabled = true

        let payload = P7Message(withName: "wired.user.get_info", spec: spec).bin()
        var length = Data()
        length.append(uint32: UInt32(payload.count), bigEndian: true)

        var bogusChecksum = Data(repeating: 0, count: pair.server.checksumLength(.SHA2_256))
        bogusChecksum[0] = 0xFF

        try pair.client.getNativeSocket()?.write(Array(length))
        try pair.client.getNativeSocket()?.write(Array(payload))
        try pair.client.getNativeSocket()?.write(Array(bogusChecksum))

        XCTAssertThrowsError(try pair.server.readMessage(timeout: 1.0, enforceDeadline: true))
    }

    func testReadMessageThrowsWhenSerializationIsNotBinary() {
        let socket = P7Socket(hostname: "localhost", port: 0, spec: spec)
        socket.connected = true
        socket.serialization = .XML

        XCTAssertThrowsError(try socket.readMessage(timeout: 0.1, enforceDeadline: true))
    }

    func testReadMessageThrowsWhenDisconnected() {
        let socket = P7Socket(hostname: "localhost", port: 0, spec: spec)
        socket.connected = false
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

    func testDisconnectIsIdempotent() throws {
        let pair = try makeConnectedPair()
        pair.client.disconnect()
        pair.client.disconnect()
        XCTAssertFalse(pair.client.connected)
    }

    func testClientAddressAndPeerHelpersReturnNilWhenSocketIsMissing() {
        let socket = P7Socket(hostname: "localhost", port: 0, spec: spec)
        XCTAssertNil(socket.clientAddress())
        XCTAssertNil(socket.getClientIP())
        XCTAssertNil(socket.getClientHostname())
    }

    func testConnectAndAcceptHandshakeSucceedsWithNoCrypto() throws {
        let listener = try Socket.tcpListening(port: 0, address: "127.0.0.1")
        let port = Int(try listener.port())
        let serverSpec = try XCTUnwrap(loadSpec())

        var serverError: Error?
        var serverSocket: P7Socket?
        let accepted = expectation(description: "server accept finished")

        DispatchQueue.global().async {
            defer { accepted.fulfill() }
            do {
                let native = try listener.accept()
                let server = P7Socket(socket: native, spec: serverSpec)
                serverSocket = server
                try server.accept(compression: .NONE, cipher: .NONE, checksum: .NONE)
            } catch {
                serverError = error
            }
        }

        let client = P7Socket(hostname: "127.0.0.1", port: port, spec: spec)
        try client.connect()
        wait(for: [accepted], timeout: 3.0)

        XCTAssertNil(serverError)
        XCTAssertEqual(client.remoteName, "Wired")
        XCTAssertEqual(client.remoteVersion, "3.1")
        XCTAssertFalse(client.compressionEnabled)
        XCTAssertFalse(client.encryptionEnabled)
        XCTAssertFalse(client.checksumEnabled)
        XCTAssertNotNil(serverSocket)

        client.disconnect()
        serverSocket?.disconnect()
        listener.close()
    }

    func testAcceptRejectsClientWhenServerRequiresEncryptionAndClientRequestsNone() throws {
        let listener = try Socket.tcpListening(port: 0, address: "127.0.0.1")
        let port = Int(try listener.port())
        let serverSpec = try XCTUnwrap(loadSpec())

        var serverError: Error?
        let accepted = expectation(description: "server accept rejected")

        DispatchQueue.global().async {
            defer { accepted.fulfill() }
            do {
                let native = try listener.accept()
                let server = P7Socket(socket: native, spec: serverSpec)
                do {
                    try server.accept(compression: .NONE, cipher: .ECDH_AES256_SHA256, checksum: .SHA2_256)
                } catch {
                    serverError = error
                }
                server.disconnect()
            } catch {
                serverError = error
            }
        }

        let client = P7Socket(hostname: "127.0.0.1", port: port, spec: spec)
        XCTAssertThrowsError(try client.connect())
        wait(for: [accepted], timeout: 3.0)

        XCTAssertNotNil(serverError)
        client.disconnect()
        listener.close()
    }

    func testConnectAndAcceptWithCompatibilityCheckEnabledFailsOnMajorMismatch() throws {
        let listener = try Socket.tcpListening(port: 0, address: "127.0.0.1")
        let port = Int(try listener.port())
        let serverSpec = try XCTUnwrap(loadSpec())
        // Force protocol mismatch vs client hardcoded "Wired 3.0" in connectHandshake.
        serverSpec.protocolVersion = "4.0"

        var serverError: Error?
        let accepted = expectation(description: "server accept compat failed")

        DispatchQueue.global().async {
            defer { accepted.fulfill() }
            do {
                let native = try listener.accept()
                let server = P7Socket(socket: native, spec: serverSpec)
                do {
                    try server.accept(compression: .NONE, cipher: .NONE, checksum: .NONE)
                } catch {
                    serverError = error
                }
                server.disconnect()
            } catch {
                serverError = error
            }
        }

        let client = P7Socket(hostname: "127.0.0.1", port: port, spec: spec)
        XCTAssertThrowsError(try client.connect())
        wait(for: [accepted], timeout: 3.0)
        XCTAssertNotNil(serverError)
        client.disconnect()
        listener.close()
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

    private func loadSpec() -> P7Spec? {
        P7Spec(withUrl: TestResources.specURL)
    }
}
