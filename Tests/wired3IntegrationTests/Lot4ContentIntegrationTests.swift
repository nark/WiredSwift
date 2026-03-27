import Foundation
import XCTest
import WiredSwift

final class Lot4ContentIntegrationTests: SerializedIntegrationTestCase {
    func testBoardsLifecycleAddThreadPostSearchAndDelete() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let (socket, _) = try connectAndAuthenticate(runtime: runtime, username: "it_admin", password: "secret")
        defer { socket.disconnect() }

        let boardPath = "integration-board-\(UUID().uuidString.prefix(8))"
        let subject = "Subject \(UUID().uuidString.prefix(6))"
        let body = "Thread body"
        let replyText = "Post body \(UUID().uuidString.prefix(6))"
        let query = "needle-\(UUID().uuidString.prefix(8))"

        let addBoard = P7Message(withName: "wired.board.add_board", spec: socket.spec)
        addBoard.addParameter(field: "wired.board.board", value: boardPath)
        addBoard.addParameter(field: "wired.board.owner", value: "admin")
        addBoard.addParameter(field: "wired.board.owner.read", value: true)
        addBoard.addParameter(field: "wired.board.owner.write", value: true)
        addBoard.addParameter(field: "wired.board.group", value: "admin")
        addBoard.addParameter(field: "wired.board.group.read", value: true)
        addBoard.addParameter(field: "wired.board.group.write", value: true)
        addBoard.addParameter(field: "wired.board.everyone.read", value: true)
        addBoard.addParameter(field: "wired.board.everyone.write", value: false)
        XCTAssertTrue(socket.write(addBoard))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let addThread = P7Message(withName: "wired.board.add_thread", spec: socket.spec)
        addThread.addParameter(field: "wired.board.board", value: boardPath)
        addThread.addParameter(field: "wired.board.subject", value: subject)
        addThread.addParameter(field: "wired.board.text", value: "\(body) \(query)")
        XCTAssertTrue(socket.write(addThread))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let getThreads = P7Message(withName: "wired.board.get_threads", spec: socket.spec)
        getThreads.addParameter(field: "wired.board.board", value: boardPath)
        XCTAssertTrue(socket.write(getThreads))

        var threadID: String?
        var sawThreadListDone = false
        for _ in 0..<60 {
            let message = try socket.readMessage(timeout: 1, enforceDeadline: true)
            if message.name == "wired.board.thread_list",
               message.string(forField: "wired.board.subject") == subject {
                threadID = message.uuid(forField: "wired.board.thread")
            }
            if message.name == "wired.board.thread_list.done" {
                sawThreadListDone = true
                break
            }
        }
        XCTAssertTrue(sawThreadListDone)
        let createdThreadID = try XCTUnwrap(threadID)

        let addPost = P7Message(withName: "wired.board.add_post", spec: socket.spec)
        addPost.addParameter(field: "wired.board.thread", value: createdThreadID)
        addPost.addParameter(field: "wired.board.text", value: replyText)
        XCTAssertTrue(socket.write(addPost))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let search = P7Message(withName: "wired.board.search", spec: socket.spec)
        search.addParameter(field: "wired.board.query", value: query)
        search.addParameter(field: "wired.board.board", value: boardPath)
        XCTAssertTrue(socket.write(search))

        var sawSearchResult = false
        for _ in 0..<80 {
            let message = try socket.readMessage(timeout: 1, enforceDeadline: true)
            if message.name == "wired.board.search_list",
               message.uuid(forField: "wired.board.thread") == createdThreadID {
                sawSearchResult = true
            }
            if message.name == "wired.board.search_list.done" {
                break
            }
        }
        XCTAssertTrue(sawSearchResult)

        let getThread = P7Message(withName: "wired.board.get_thread", spec: socket.spec)
        getThread.addParameter(field: "wired.board.thread", value: createdThreadID)
        XCTAssertTrue(socket.write(getThread))

        var sawThreadHeader = false
        var sawReplyPost = false
        for _ in 0..<80 {
            let message = try socket.readMessage(timeout: 1, enforceDeadline: true)
            if message.name == "wired.board.thread",
               message.uuid(forField: "wired.board.thread") == createdThreadID {
                sawThreadHeader = true
            }
            if message.name == "wired.board.post_list",
               message.string(forField: "wired.board.text") == replyText {
                sawReplyPost = true
            }
            if message.name == "wired.board.post_list.done" {
                break
            }
        }
        XCTAssertTrue(sawThreadHeader)
        XCTAssertTrue(sawReplyPost)

        let deleteThread = P7Message(withName: "wired.board.delete_thread", spec: socket.spec)
        deleteThread.addParameter(field: "wired.board.thread", value: createdThreadID)
        XCTAssertTrue(socket.write(deleteThread))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let deleteBoard = P7Message(withName: "wired.board.delete_board", spec: socket.spec)
        deleteBoard.addParameter(field: "wired.board.board", value: boardPath)
        XCTAssertTrue(socket.write(deleteBoard))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)
    }

    func testGuestCannotAddBoard() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        defer { try? runtime.stop() }

        let (guest, _) = try connectAndAuthenticate(runtime: runtime, username: "guest", password: "")
        defer { guest.disconnect() }

        let addBoard = P7Message(withName: "wired.board.add_board", spec: guest.spec)
        addBoard.addParameter(field: "wired.board.board", value: "guest-denied-\(UUID().uuidString.prefix(6))")
        addBoard.addParameter(field: "wired.board.owner", value: "admin")
        addBoard.addParameter(field: "wired.board.owner.read", value: true)
        addBoard.addParameter(field: "wired.board.owner.write", value: true)
        addBoard.addParameter(field: "wired.board.group", value: "admin")
        addBoard.addParameter(field: "wired.board.group.read", value: true)
        addBoard.addParameter(field: "wired.board.group.write", value: true)
        addBoard.addParameter(field: "wired.board.everyone.read", value: true)
        addBoard.addParameter(field: "wired.board.everyone.write", value: false)
        XCTAssertTrue(guest.write(addBoard))
        let denied = try readMessage(from: guest, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(denied.string(forField: "wired.error.string"), "wired.error.permission_denied")
    }

    func testDirectMessageAndBroadcastDelivery() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.ensurePrivilegedUser(username: "it_admin_2", password: "secret2")
        defer { try? runtime.stop() }

        let (sender, senderID) = try connectAndAuthenticate(runtime: runtime, username: "it_admin", password: "secret")
        defer { sender.disconnect() }
        let (recipient, recipientID) = try connectAndAuthenticate(runtime: runtime, username: "it_admin_2", password: "secret2")
        defer { recipient.disconnect() }

        let body = "direct-\(UUID().uuidString.prefix(8))"
        let direct = P7Message(withName: "wired.message.send_message", spec: sender.spec)
        direct.addParameter(field: "wired.user.id", value: recipientID)
        direct.addParameter(field: "wired.message.message", value: body)
        XCTAssertTrue(sender.write(direct))
        _ = try readMessage(from: sender, expectedName: "wired.okay", maxReads: 20)

        let directReceived = try readMessage(from: recipient, expectedName: "wired.message.message", maxReads: 40)
        XCTAssertEqual(directReceived.uint32(forField: "wired.user.id"), senderID)
        XCTAssertEqual(directReceived.string(forField: "wired.message.message"), body)

        let broadcastText = "broadcast-\(UUID().uuidString.prefix(8))"
        let broadcast = P7Message(withName: "wired.message.send_broadcast", spec: sender.spec)
        broadcast.addParameter(field: "wired.message.broadcast", value: broadcastText)
        XCTAssertTrue(sender.write(broadcast))
        _ = try readMessage(from: sender, expectedName: "wired.okay", maxReads: 20)

        let receivedBroadcast = try readMessage(from: recipient, expectedName: "wired.message.broadcast", maxReads: 60)
        XCTAssertEqual(receivedBroadcast.string(forField: "wired.message.broadcast"), broadcastText)
    }

    func testGuestBroadcastIsDenied() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        defer { try? runtime.stop() }

        let (guest, _) = try connectAndAuthenticate(runtime: runtime, username: "guest", password: "")
        defer { guest.disconnect() }

        let broadcast = P7Message(withName: "wired.message.send_broadcast", spec: guest.spec)
        broadcast.addParameter(field: "wired.message.broadcast", value: "guest message")
        XCTAssertTrue(guest.write(broadcast))
        let denied = try readMessage(from: guest, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(denied.string(forField: "wired.error.string"), "wired.error.permission_denied")
    }

    func testFilesTypePermissionsAndInfoRoundTrip() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let (socket, _) = try connectAndAuthenticate(runtime: runtime, username: "it_admin", password: "secret")
        defer { socket.disconnect() }

        let directoryPath = "/dropbox-\(UUID().uuidString.prefix(8))"

        let create = P7Message(withName: "wired.file.create_directory", spec: socket.spec)
        create.addParameter(field: "wired.file.path", value: directoryPath)
        XCTAssertTrue(socket.write(create))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let setType = P7Message(withName: "wired.file.set_type", spec: socket.spec)
        setType.addParameter(field: "wired.file.path", value: directoryPath)
        setType.addParameter(field: "wired.file.type", value: UInt32(File.FileType.dropbox.rawValue))
        XCTAssertTrue(socket.write(setType))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let setPermissions = P7Message(withName: "wired.file.set_permissions", spec: socket.spec)
        setPermissions.addParameter(field: "wired.file.path", value: directoryPath)
        setPermissions.addParameter(field: "wired.file.owner", value: "admin")
        setPermissions.addParameter(field: "wired.file.group", value: "admin")
        setPermissions.addParameter(field: "wired.file.owner.read", value: UInt8(1))
        setPermissions.addParameter(field: "wired.file.owner.write", value: UInt8(1))
        setPermissions.addParameter(field: "wired.file.group.read", value: UInt8(1))
        setPermissions.addParameter(field: "wired.file.group.write", value: UInt8(1))
        setPermissions.addParameter(field: "wired.file.everyone.read", value: UInt8(0))
        setPermissions.addParameter(field: "wired.file.everyone.write", value: UInt8(0))
        XCTAssertTrue(socket.write(setPermissions))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let getInfo = P7Message(withName: "wired.file.get_info", spec: socket.spec)
        getInfo.addParameter(field: "wired.file.path", value: directoryPath)
        XCTAssertTrue(socket.write(getInfo))
        let info = try readMessage(from: socket, expectedName: "wired.file.info", maxReads: 20)
        XCTAssertEqual(info.string(forField: "wired.file.path"), directoryPath)
        XCTAssertEqual(info.enumeration(forField: "wired.file.type"), UInt32(File.FileType.dropbox.rawValue))
    }

    func testTransfersUploadDirectoryAndErrorPaths() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let (admin, _) = try connectAndAuthenticate(runtime: runtime, username: "it_admin", password: "secret")
        defer { admin.disconnect() }

        let createdDir = "/uploaded-dir-\(UUID().uuidString.prefix(8))"
        let uploadDirectory = P7Message(withName: "wired.transfer.upload_directory", spec: admin.spec)
        uploadDirectory.addParameter(field: "wired.file.path", value: createdDir)
        XCTAssertTrue(admin.write(uploadDirectory))
        _ = try readMessage(from: admin, expectedName: "wired.okay", maxReads: 20)

        let createdOnDisk = runtime.filesURL.appendingPathComponent(String(createdDir.dropFirst())).path
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdOnDisk, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        let fixturePath = runtime.filesURL.appendingPathComponent("fixture.txt")
        try "fixture".write(to: fixturePath, atomically: true, encoding: .utf8)

        let missingOffsets = P7Message(withName: "wired.transfer.download_file", spec: admin.spec)
        missingOffsets.addParameter(field: "wired.file.path", value: "/fixture.txt")
        XCTAssertTrue(admin.write(missingOffsets))
        let invalid = try readMessage(from: admin, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(invalid.string(forField: "wired.error.string"), "wired.error.invalid_message")

        let (guest, _) = try connectAndAuthenticate(runtime: runtime, username: "guest", password: "")
        defer { guest.disconnect() }

        let guestUploadDir = P7Message(withName: "wired.transfer.upload_directory", spec: guest.spec)
        guestUploadDir.addParameter(field: "wired.file.path", value: "/guest-upload-dir")
        XCTAssertTrue(guest.write(guestUploadDir))
        let deniedUploadDir = try readMessage(from: guest, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(deniedUploadDir.string(forField: "wired.error.string"), "wired.error.permission_denied")

        let guestDownload = P7Message(withName: "wired.transfer.download_file", spec: guest.spec)
        guestDownload.addParameter(field: "wired.file.path", value: "/fixture.txt")
        guestDownload.addParameter(field: "wired.transfer.data_offset", value: UInt64(0))
        guestDownload.addParameter(field: "wired.transfer.rsrc_offset", value: UInt64(0))
        XCTAssertTrue(guest.write(guestDownload))
        let deniedDownload = try readMessage(from: guest, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(deniedDownload.string(forField: "wired.error.string"), "wired.error.permission_denied")
    }

    func testTransferUploadFileRoundTripWritesExpectedBytes() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let (admin, _) = try connectAndAuthenticate(runtime: runtime, username: "it_admin", password: "secret")
        defer { admin.disconnect() }

        let remotePath = "/upload-\(UUID().uuidString.prefix(8)).bin"
        let payload = Data((0..<1024).map { UInt8($0 % 251) })

        let uploadFile = P7Message(withName: "wired.transfer.upload_file", spec: admin.spec)
        uploadFile.addParameter(field: "wired.file.path", value: remotePath)
        uploadFile.addParameter(field: "wired.transfer.data_size", value: UInt64(payload.count))
        uploadFile.addParameter(field: "wired.transfer.rsrc_size", value: UInt64(0))
        XCTAssertTrue(admin.write(uploadFile))

        let uploadReady = try readMessage(from: admin, expectedName: "wired.transfer.upload_ready", maxReads: 40)
        XCTAssertEqual(uploadReady.string(forField: "wired.file.path"), remotePath)
        XCTAssertEqual(uploadReady.uint64(forField: "wired.transfer.data_offset"), UInt64(0))
        XCTAssertEqual(uploadReady.uint64(forField: "wired.transfer.rsrc_offset"), UInt64(0))

        let uploadGo = P7Message(withName: "wired.transfer.upload", spec: admin.spec)
        uploadGo.addParameter(field: "wired.transfer.data", value: UInt64(payload.count))
        uploadGo.addParameter(field: "wired.transfer.rsrc", value: UInt64(0))
        XCTAssertTrue(admin.write(uploadGo))
        try admin.writeOOB(data: payload, timeout: 3)

        // Barrier: force a follow-up request so transfer processing has completed on server side.
        let getInfo = P7Message(withName: "wired.file.get_info", spec: admin.spec)
        getInfo.addParameter(field: "wired.file.path", value: remotePath)
        XCTAssertTrue(admin.write(getInfo))
        _ = try readMessage(from: admin, expectedNames: ["wired.file.info", "wired.error"], maxReads: 30)

        let finalPath = runtime.filesURL.appendingPathComponent(String(remotePath.dropFirst())).path
        let partialPath = "\(finalPath).WiredTransfer"

        let receivedPath = try XCTUnwrap(waitForExistingPath([finalPath, partialPath], timeout: 3))
        let received = try Data(contentsOf: URL(fileURLWithPath: receivedPath))
        XCTAssertEqual(received, payload)
    }

    func testTransferUploadRejectsInvalidFollowUpMessage() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let (admin, _) = try connectAndAuthenticate(runtime: runtime, username: "it_admin", password: "secret")
        defer { admin.disconnect() }

        let remotePath = "/upload-invalid-\(UUID().uuidString.prefix(8)).bin"
        let uploadFile = P7Message(withName: "wired.transfer.upload_file", spec: admin.spec)
        uploadFile.addParameter(field: "wired.file.path", value: remotePath)
        uploadFile.addParameter(field: "wired.transfer.data_size", value: UInt64(8))
        uploadFile.addParameter(field: "wired.transfer.rsrc_size", value: UInt64(0))
        XCTAssertTrue(admin.write(uploadFile))
        _ = try readMessage(from: admin, expectedName: "wired.transfer.upload_ready", maxReads: 40)

        let invalid = P7Message(withName: "wired.chat.get_chats", spec: admin.spec)
        XCTAssertTrue(admin.write(invalid))

        var sawInvalidMessageError = false
        var disconnected = false
        for _ in 0..<12 {
            do {
                let reply = try admin.readMessage(timeout: 0.5, enforceDeadline: true)
                if reply.name == "wired.error",
                   reply.string(forField: "wired.error.string") == "wired.error.invalid_message" {
                    sawInvalidMessageError = true
                    break
                }
            } catch {
                disconnected = true
                break
            }
        }

        XCTAssertTrue(
            sawInvalidMessageError || disconnected,
            "Expected wired.error.invalid_message or disconnect after invalid upload follow-up message"
        )
    }

    func testTransferDownloadStreamsExpectedBytes() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let fixturePath = runtime.filesURL.appendingPathComponent("download-\(UUID().uuidString.prefix(8)).bin")
        let payload = Data((0..<2048).map { UInt8($0 % 247) })
        try payload.write(to: fixturePath)

        let (admin, _) = try connectAndAuthenticate(runtime: runtime, username: "it_admin", password: "secret")
        defer { admin.disconnect() }

        let request = P7Message(withName: "wired.transfer.download_file", spec: admin.spec)
        request.addParameter(field: "wired.file.path", value: "/\(fixturePath.lastPathComponent)")
        request.addParameter(field: "wired.transfer.data_offset", value: UInt64(0))
        request.addParameter(field: "wired.transfer.rsrc_offset", value: UInt64(0))
        XCTAssertTrue(admin.write(request))

        let header = try readMessage(from: admin, expectedName: "wired.transfer.download", maxReads: 40)
        let expectedSize = try XCTUnwrap(header.uint64(forField: "wired.transfer.data"))
        XCTAssertEqual(expectedSize, UInt64(payload.count))

        var received = Data()
        while received.count < Int(expectedSize) {
            let chunk = try admin.readOOB(timeout: 3)
            received.append(chunk)
        }

        XCTAssertEqual(received.prefix(Int(expectedSize)), payload)
    }

    private func waitForExistingPath(_ candidates: [String], timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for path in candidates where FileManager.default.fileExists(atPath: path) {
                return path
            }
            usleep(50_000)
        }
        return nil
    }

    private func connectAndAuthenticate(
        runtime: IntegrationServerRuntime,
        username: String,
        password: String
    ) throws -> (P7Socket, UInt32) {
        let socket = try runtime.connectClient(username: username, password: password)
        try sendClientInfoAndExpectServerInfo(socket: socket)
        let login = try sendLoginAndExpectSuccess(socket: socket, username: username, password: password)
        drainMessages(socket: socket)
        let userID = try XCTUnwrap(login.uint32(forField: "wired.user.id"))
        return (socket, userID)
    }
}
