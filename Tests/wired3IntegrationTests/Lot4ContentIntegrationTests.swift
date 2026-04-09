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

        let syncPath = "/sync-\(UUID().uuidString.prefix(8))"
        let createSync = P7Message(withName: "wired.file.create_directory", spec: socket.spec)
        createSync.addParameter(field: "wired.file.path", value: syncPath)
        XCTAssertTrue(socket.write(createSync))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let setSyncType = P7Message(withName: "wired.file.set_type", spec: socket.spec)
        setSyncType.addParameter(field: "wired.file.path", value: syncPath)
        setSyncType.addParameter(field: "wired.file.type", value: UInt32(File.FileType.sync.rawValue))
        XCTAssertTrue(socket.write(setSyncType))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let syncInfo = P7Message(withName: "wired.file.get_info", spec: socket.spec)
        syncInfo.addParameter(field: "wired.file.path", value: syncPath)
        XCTAssertTrue(socket.write(syncInfo))
        let syncReply = try readMessage(from: socket, expectedName: "wired.file.info", maxReads: 20)
        XCTAssertEqual(syncReply.enumeration(forField: "wired.file.type"), UInt32(File.FileType.sync.rawValue))
    }

    func testSyncDirectoryCountIsHiddenWhenDirectoryIsNotReadable() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.ensurePrivilegedUser(username: "it_bob", password: "secret2")
        defer { try? runtime.stop() }

        let (admin, _) = try connectAndAuthenticate(runtime: runtime, username: "it_admin", password: "secret")
        defer { admin.disconnect() }
        let (bob, _) = try connectAndAuthenticate(runtime: runtime, username: "it_bob", password: "secret2")
        defer { bob.disconnect() }

        let syncPath = "/sync-private-\(UUID().uuidString.prefix(8))"
        try createSyncDirectory(
            socket: admin,
            path: syncPath,
            owner: "it_admin",
            group: "admin",
            userMode: "bidirectional",
            groupMode: "disabled",
            everyoneMode: "client_to_server"
        )
        try createDirectory(socket: admin, path: "\(syncPath)/child")

        let setPermissions = P7Message(withName: "wired.file.set_permissions", spec: admin.spec)
        setPermissions.addParameter(field: "wired.file.path", value: syncPath)
        setPermissions.addParameter(field: "wired.file.owner", value: "it_admin")
        setPermissions.addParameter(field: "wired.file.group", value: "admin")
        setPermissions.addParameter(field: "wired.file.owner.read", value: true)
        setPermissions.addParameter(field: "wired.file.owner.write", value: true)
        setPermissions.addParameter(field: "wired.file.group.read", value: false)
        setPermissions.addParameter(field: "wired.file.group.write", value: false)
        setPermissions.addParameter(field: "wired.file.everyone.read", value: false)
        setPermissions.addParameter(field: "wired.file.everyone.write", value: false)
        XCTAssertTrue(admin.write(setPermissions))
        _ = try readMessage(from: admin, expectedName: "wired.okay", maxReads: 20)

        let listRoot = P7Message(withName: "wired.file.list_directory", spec: bob.spec)
        listRoot.addParameter(field: "wired.file.path", value: "/")
        XCTAssertTrue(bob.write(listRoot))

        var listedSyncCount: UInt32?
        for _ in 0..<40 {
            let message = try readMessage(
                from: bob,
                expectedNames: ["wired.file.file_list", "wired.file.file_list.done"],
                maxReads: 20
            )
            if message.name == "wired.file.file_list",
               message.string(forField: "wired.file.path") == syncPath {
                listedSyncCount = message.uint32(forField: "wired.file.directory_count")
            }
            if message.name == "wired.file.file_list.done" {
                break
            }
        }
        XCTAssertEqual(listedSyncCount, 0)

        let info = P7Message(withName: "wired.file.get_info", spec: bob.spec)
        info.addParameter(field: "wired.file.path", value: syncPath)
        XCTAssertTrue(bob.write(info))
        let reply = try readMessage(from: bob, expectedName: "wired.file.info", maxReads: 20)
        XCTAssertEqual(reply.uint32(forField: "wired.file.directory_count"), 0)
        XCTAssertEqual(reply.bool(forField: "wired.file.readable"), false)
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

    func testUserSetNickStatusIconIdleBroadcastsChatUserStatus() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.ensurePrivilegedUser(username: "it_admin_2", password: "secret2")
        defer { try? runtime.stop() }

        let (actor, actorID) = try connectAndAuthenticate(runtime: runtime, username: "it_admin", password: "secret")
        defer { actor.disconnect() }
        let (observer, _) = try connectAndAuthenticate(runtime: runtime, username: "it_admin_2", password: "secret2")
        defer { observer.disconnect() }

        let create = P7Message(withName: "wired.chat.create_public_chat", spec: actor.spec)
        create.addParameter(field: "wired.chat.name", value: "Status Room")
        XCTAssertTrue(actor.write(create))
        _ = try readMessage(from: actor, expectedName: "wired.okay", maxReads: 40)

        let getChats = P7Message(withName: "wired.chat.get_chats", spec: actor.spec)
        XCTAssertTrue(actor.write(getChats))
        var chatID: UInt32?
        for _ in 0..<60 {
            let message = try actor.readMessage(timeout: 1, enforceDeadline: true)
            if message.name == "wired.chat.chat_list",
               message.string(forField: "wired.chat.name") == "Status Room" {
                chatID = message.uint32(forField: "wired.chat.id")
            }
            if message.name == "wired.chat.chat_list.done" {
                break
            }
        }
        let roomID = try XCTUnwrap(chatID)

        let joinActor = P7Message(withName: "wired.chat.join_chat", spec: actor.spec)
        joinActor.addParameter(field: "wired.chat.id", value: roomID)
        XCTAssertTrue(actor.write(joinActor))
        _ = try readMessage(from: actor, expectedName: "wired.chat.user_list.done", maxReads: 20)
        _ = try readMessage(from: actor, expectedName: "wired.chat.topic", maxReads: 20)

        let joinObserver = P7Message(withName: "wired.chat.join_chat", spec: observer.spec)
        joinObserver.addParameter(field: "wired.chat.id", value: roomID)
        XCTAssertTrue(observer.write(joinObserver))
        _ = try readMessage(from: observer, expectedName: "wired.chat.user_list.done", maxReads: 20)
        _ = try readMessage(from: observer, expectedName: "wired.chat.topic", maxReads: 20)
        _ = try readMessage(from: actor, expectedName: "wired.chat.user_join", maxReads: 20)

        let setNick = P7Message(withName: "wired.user.set_nick", spec: actor.spec)
        setNick.addParameter(field: "wired.user.nick", value: "Captain Integration")
        XCTAssertTrue(actor.write(setNick))
        _ = try readMessage(from: actor, expectedName: "wired.okay", maxReads: 20)
        let nickStatus = try waitForUserStatusUpdate(from: observer, userID: actorID) { status in
            status.string(forField: "wired.user.nick") == "Captain Integration"
        }
        XCTAssertEqual(nickStatus.string(forField: "wired.user.nick"), "Captain Integration")

        let setStatus = P7Message(withName: "wired.user.set_status", spec: actor.spec)
        setStatus.addParameter(field: "wired.user.status", value: "On duty")
        XCTAssertTrue(actor.write(setStatus))
        _ = try readMessage(from: actor, expectedName: "wired.okay", maxReads: 20)
        let statusUpdate = try waitForUserStatusUpdate(from: observer, userID: actorID) { status in
            status.string(forField: "wired.user.status") == "On duty"
        }
        XCTAssertEqual(statusUpdate.string(forField: "wired.user.status"), "On duty")

        let setIcon = P7Message(withName: "wired.user.set_icon", spec: actor.spec)
        setIcon.addParameter(field: "wired.user.icon", value: Data([0x01, 0x02, 0x03]))
        XCTAssertTrue(actor.write(setIcon))
        _ = try readMessage(from: actor, expectedName: "wired.okay", maxReads: 20)
        let iconUpdate = try waitForUserStatusUpdate(from: observer, userID: actorID) { status in
            status.data(forField: "wired.user.icon") == Data([0x01, 0x02, 0x03])
        }
        XCTAssertEqual(iconUpdate.data(forField: "wired.user.icon"), Data([0x01, 0x02, 0x03]))

        let setIdle = P7Message(withName: "wired.user.set_idle", spec: actor.spec)
        XCTAssertTrue(actor.write(setIdle))
        _ = try readMessage(from: actor, expectedName: "wired.okay", maxReads: 20)
        let idleUpdate = try waitForUserStatusUpdate(from: observer, userID: actorID) { status in
            status.bool(forField: "wired.user.idle") == true
        }
        XCTAssertEqual(idleUpdate.bool(forField: "wired.user.idle"), true)
    }

    func testBoardReactionsLifecycleWithBroadcastAndList() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.ensurePrivilegedUser(username: "it_admin_2", password: "secret2")
        defer { try? runtime.stop() }

        let (actor, _) = try connectAndAuthenticate(runtime: runtime, username: "it_admin", password: "secret")
        defer { actor.disconnect() }
        let (observer, _) = try connectAndAuthenticate(runtime: runtime, username: "it_admin_2", password: "secret2")
        defer { observer.disconnect() }

        let boardPath = "reaction-board-\(UUID().uuidString.prefix(8))"
        let addBoard = P7Message(withName: "wired.board.add_board", spec: actor.spec)
        addBoard.addParameter(field: "wired.board.board", value: boardPath)
        addBoard.addParameter(field: "wired.board.owner", value: "admin")
        addBoard.addParameter(field: "wired.board.owner.read", value: true)
        addBoard.addParameter(field: "wired.board.owner.write", value: true)
        addBoard.addParameter(field: "wired.board.group", value: "admin")
        addBoard.addParameter(field: "wired.board.group.read", value: true)
        addBoard.addParameter(field: "wired.board.group.write", value: true)
        addBoard.addParameter(field: "wired.board.everyone.read", value: true)
        addBoard.addParameter(field: "wired.board.everyone.write", value: false)
        XCTAssertTrue(actor.write(addBoard))
        _ = try readMessage(from: actor, expectedName: "wired.okay", maxReads: 20)

        let subscribeObserver = P7Message(withName: "wired.board.subscribe_boards", spec: observer.spec)
        XCTAssertTrue(observer.write(subscribeObserver))
        _ = try readMessage(from: observer, expectedName: "wired.okay", maxReads: 20)

        let addThread = P7Message(withName: "wired.board.add_thread", spec: actor.spec)
        addThread.addParameter(field: "wired.board.board", value: boardPath)
        addThread.addParameter(field: "wired.board.subject", value: "Reaction thread")
        addThread.addParameter(field: "wired.board.text", value: "react here")
        XCTAssertTrue(actor.write(addThread))
        _ = try readMessage(from: actor, expectedName: "wired.okay", maxReads: 20)

        let getThreads = P7Message(withName: "wired.board.get_threads", spec: actor.spec)
        getThreads.addParameter(field: "wired.board.board", value: boardPath)
        XCTAssertTrue(actor.write(getThreads))
        var threadID: String?
        for _ in 0..<60 {
            let message = try actor.readMessage(timeout: 1, enforceDeadline: true)
            if message.name == "wired.board.thread_list" {
                threadID = message.uuid(forField: "wired.board.thread")
            }
            if message.name == "wired.board.thread_list.done" {
                break
            }
        }
        let createdThread = try XCTUnwrap(threadID)

        let addReaction = P7Message(withName: "wired.board.add_reaction", spec: actor.spec)
        addReaction.addParameter(field: "wired.board.thread", value: createdThread)
        addReaction.addParameter(field: "wired.board.reaction.emoji", value: ":+1:")
        XCTAssertTrue(actor.write(addReaction))
        _ = try readMessage(from: actor, expectedName: "wired.okay", maxReads: 20)

        let broadcastAdded = try readMessage(from: observer, expectedName: "wired.board.reaction_added", maxReads: 40)
        XCTAssertEqual(broadcastAdded.uuid(forField: "wired.board.thread"), createdThread)
        XCTAssertEqual(broadcastAdded.string(forField: "wired.board.reaction.emoji"), ":+1:")
        XCTAssertEqual(broadcastAdded.uint32(forField: "wired.board.reaction.count"), UInt32(1))

        let getReactions = P7Message(withName: "wired.board.get_reactions", spec: actor.spec)
        getReactions.addParameter(field: "wired.board.thread", value: createdThread)
        XCTAssertTrue(actor.write(getReactions))

        var sawList = false
        for _ in 0..<40 {
            let message = try actor.readMessage(timeout: 1, enforceDeadline: true)
            if message.name == "wired.board.reaction_list" {
                sawList = true
                XCTAssertEqual(message.string(forField: "wired.board.reaction.emoji"), ":+1:")
                XCTAssertEqual(message.uint32(forField: "wired.board.reaction.count"), UInt32(1))
            }
            if message.name == "wired.okay" {
                break
            }
        }
        XCTAssertTrue(sawList)

        let toggleOff = P7Message(withName: "wired.board.add_reaction", spec: actor.spec)
        toggleOff.addParameter(field: "wired.board.thread", value: createdThread)
        toggleOff.addParameter(field: "wired.board.reaction.emoji", value: ":+1:")
        XCTAssertTrue(actor.write(toggleOff))
        _ = try readMessage(from: actor, expectedName: "wired.okay", maxReads: 20)

        let removed = try readMessage(from: observer, expectedName: "wired.board.reaction_removed", maxReads: 40)
        XCTAssertEqual(removed.uuid(forField: "wired.board.thread"), createdThread)
        XCTAssertEqual(removed.string(forField: "wired.board.reaction.emoji"), ":+1:")
        XCTAssertEqual(removed.uint32(forField: "wired.board.reaction.count"), UInt32(0))
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

    private func waitForUserStatusUpdate(
        from socket: P7Socket,
        userID: UInt32,
        timeout: TimeInterval = 3,
        predicate: (P7Message) -> Bool
    ) throws -> P7Message {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            do {
                let message = try socket.readMessage(timeout: 0.5, enforceDeadline: true)
                guard message.name == "wired.chat.user_status" else { continue }
                guard message.uint32(forField: "wired.user.id") == userID else { continue }
                if predicate(message) {
                    return message
                }
            } catch {
                continue
            }
        }

        XCTFail("Expected matching wired.chat.user_status before timeout")
        return P7Message(withName: "wired.error", spec: socket.spec)
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
