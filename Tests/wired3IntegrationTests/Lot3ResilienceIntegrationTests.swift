import XCTest
import WiredSwift

final class Lot3ResilienceIntegrationTests: SerializedIntegrationTestCase {
    func testReconnectWorksForSameUser() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        do {
            let socket = try runtime.connectClient(username: "it_admin", password: "secret")
            try sendClientInfoAndExpectServerInfo(socket: socket)
            _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
            socket.disconnect()
        }

        let reconnect = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { reconnect.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: reconnect)
        let login = try sendLoginAndExpectSuccess(socket: reconnect, username: "it_admin", password: "secret")
        XCTAssertNotNil(login.uint32(forField: "wired.user.id"))
    }

    func testConcurrentClientsCanQueryChatsSimultaneously() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let clients = try (0..<3).map { _ in try runtime.connectClient(username: "it_admin", password: "secret") }
        defer { clients.forEach { $0.disconnect() } }

        for client in clients {
            try sendClientInfoAndExpectServerInfo(socket: client)
            _ = try sendLoginAndExpectSuccess(socket: client, username: "it_admin", password: "secret")
            drainMessages(socket: client)
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var failures = 0

        for client in clients {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }

                let message = P7Message(withName: "wired.chat.get_chats", spec: client.spec)
                guard client.write(message) else {
                    lock.lock(); failures += 1; lock.unlock()
                    return
                }

                do {
                    _ = try readMessage(from: client, expectedName: "wired.chat.chat_list.done", maxReads: 20)
                } catch {
                    lock.lock(); failures += 1; lock.unlock()
                }
            }
        }

        group.wait()
        XCTAssertEqual(failures, 0)
    }

    func testPersistenceAcrossRestartKeepsFilesystemState() throws {
        let runtime1 = try IntegrationServerRuntime()
        try runtime1.start()
        runtime1.ensurePrivilegedUser(username: "it_admin", password: "secret")

        do {
            let socket = try runtime1.connectClient(username: "it_admin", password: "secret")
            defer { socket.disconnect() }
            try sendClientInfoAndExpectServerInfo(socket: socket)
            _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
            drainMessages(socket: socket)

            let createDir = P7Message(withName: "wired.file.create_directory", spec: socket.spec)
            createDir.addParameter(field: "wired.file.path", value: "/persisted_dir")
            XCTAssertTrue(socket.write(createDir))
            _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 10)
        }

        try runtime1.stop(cleanup: false)

        let runtime2 = try IntegrationServerRuntime(existingRoot: runtime1.rootURL, port: runtime1.port)
        try runtime2.start()
        defer { try? runtime2.stop() }

        let socket = try runtime2.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let list = P7Message(withName: "wired.file.list_directory", spec: socket.spec)
        list.addParameter(field: "wired.file.path", value: "/")
        XCTAssertTrue(socket.write(list))

        var sawPersistedDir = false
        for _ in 0..<32 {
            let message = try socket.readMessage(timeout: 3, enforceDeadline: true)
            if message.name == "wired.file.file_list",
               message.string(forField: "wired.file.path") == "/persisted_dir" {
                sawPersistedDir = true
            }
            if message.name == "wired.file.file_list.done" {
                break
            }
        }

        XCTAssertTrue(sawPersistedDir)
    }
}
