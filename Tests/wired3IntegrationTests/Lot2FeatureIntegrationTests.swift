import XCTest
import WiredSwift

final class Lot2FeatureIntegrationTests: XCTestCase {
    func testChatCreateJoinSayLeaveWithTwoClients() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let c1 = try runtime.connectClient(username: "it_admin", password: "secret")
        let c2 = try runtime.connectClient(username: "it_admin", password: "secret")
        defer {
            c1.disconnect()
            c2.disconnect()
        }

        try sendClientInfoAndExpectServerInfo(socket: c1)
        _ = try sendLoginAndExpectSuccess(socket: c1, username: "it_admin", password: "secret")
        drainMessages(socket: c1)

        try sendClientInfoAndExpectServerInfo(socket: c2)
        _ = try sendLoginAndExpectSuccess(socket: c2, username: "it_admin", password: "secret")
        drainMessages(socket: c2)

        let create = P7Message(withName: "wired.chat.create_public_chat", spec: c1.spec)
        create.addParameter(field: "wired.chat.name", value: "Integration Room")
        XCTAssertTrue(c1.write(create))

        var chatID: UInt32?
        var sawOkay = false
        for _ in 0..<20 {
            let message = try c1.readMessage(timeout: 3, enforceDeadline: true)
            if message.name == "wired.chat.public_chat_created" {
                chatID = message.uint32(forField: "wired.chat.id")
            } else if message.name == "wired.okay" {
                sawOkay = true
            }
            if chatID != nil && sawOkay {
                break
            }
        }
        XCTAssertNotNil(chatID)
        XCTAssertTrue(sawOkay)

        let joinCreator = P7Message(withName: "wired.chat.join_chat", spec: c1.spec)
        joinCreator.addParameter(field: "wired.chat.id", value: chatID!)
        XCTAssertTrue(c1.write(joinCreator))
        _ = try readMessage(from: c1, expectedName: "wired.chat.user_list.done", maxReads: 20)
        _ = try readMessage(from: c1, expectedName: "wired.chat.topic", maxReads: 20)

        let join = P7Message(withName: "wired.chat.join_chat", spec: c2.spec)
        join.addParameter(field: "wired.chat.id", value: chatID!)
        XCTAssertTrue(c2.write(join))
        _ = try readMessage(from: c2, expectedName: "wired.chat.user_list.done", maxReads: 20)
        _ = try readMessage(from: c2, expectedName: "wired.chat.topic", maxReads: 20)
        _ = try readMessage(from: c1, expectedName: "wired.chat.user_join", maxReads: 20)

        let say = P7Message(withName: "wired.chat.send_say", spec: c2.spec)
        say.addParameter(field: "wired.chat.id", value: chatID!)
        say.addParameter(field: "wired.chat.say", value: "hello integration")
        XCTAssertTrue(c2.write(say))
        _ = try readMessage(from: c2, expectedName: "wired.okay", maxReads: 20)
        _ = try readMessage(from: c1, expectedName: "wired.chat.say", maxReads: 20)

        let leave = P7Message(withName: "wired.chat.leave_chat", spec: c2.spec)
        leave.addParameter(field: "wired.chat.id", value: chatID!)
        XCTAssertTrue(c2.write(leave))
        _ = try readMessage(from: c2, expectedName: "wired.okay", maxReads: 20)
        _ = try readMessage(from: c1, expectedName: "wired.chat.user_leave", maxReads: 20)
    }

    func testFilesCreateMoveDeleteAndJailValidation() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let createDir = P7Message(withName: "wired.file.create_directory", spec: socket.spec)
        createDir.addParameter(field: "wired.file.path", value: "/it_dir")
        XCTAssertTrue(socket.write(createDir))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 10)

        let list = P7Message(withName: "wired.file.list_directory", spec: socket.spec)
        list.addParameter(field: "wired.file.path", value: "/")
        XCTAssertTrue(socket.write(list))

        var sawDir = false
        for _ in 0..<32 {
            let message = try socket.readMessage(timeout: 3, enforceDeadline: true)
            if message.name == "wired.file.file_list",
               message.string(forField: "wired.file.path") == "/it_dir" {
                sawDir = true
            }
            if message.name == "wired.file.file_list.done" {
                break
            }
        }
        XCTAssertTrue(sawDir)

        let move = P7Message(withName: "wired.file.move", spec: socket.spec)
        move.addParameter(field: "wired.file.path", value: "/it_dir")
        move.addParameter(field: "wired.file.new_path", value: "/it_dir2")
        XCTAssertTrue(socket.write(move))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 10)

        let delete = P7Message(withName: "wired.file.delete", spec: socket.spec)
        delete.addParameter(field: "wired.file.path", value: "/it_dir2")
        XCTAssertTrue(socket.write(delete))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 10)

        let traversal = P7Message(withName: "wired.file.get_info", spec: socket.spec)
        traversal.addParameter(field: "wired.file.path", value: "/../etc/passwd")
        XCTAssertTrue(socket.write(traversal))
        _ = try readMessage(from: socket, expectedName: "wired.error", maxReads: 10)
    }

    func testAccountsPermissionDeniedForGuestAndAllowedForPrivilegedUser() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let guest = try runtime.connectClient(username: "guest", password: "")
        defer { guest.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: guest)
        _ = try sendLoginAndExpectSuccess(socket: guest, username: "guest", password: "")
        drainMessages(socket: guest)

        let listUsers = P7Message(withName: "wired.account.list_users", spec: guest.spec)
        XCTAssertTrue(guest.write(listUsers))
        _ = try readMessage(from: guest, expectedName: "wired.error", maxReads: 10)

        let admin = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { admin.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: admin)
        _ = try sendLoginAndExpectSuccess(socket: admin, username: "it_admin", password: "secret")
        drainMessages(socket: admin)

        let listUsersAdmin = P7Message(withName: "wired.account.list_users", spec: admin.spec)
        XCTAssertTrue(admin.write(listUsersAdmin))
        _ = try readMessage(from: admin, expectedName: "wired.account.user_list.done", maxReads: 30)

        let readUser = P7Message(withName: "wired.account.read_user", spec: admin.spec)
        readUser.addParameter(field: "wired.account.name", value: "guest")
        XCTAssertTrue(admin.write(readUser))
        _ = try readMessage(from: admin, expectedName: "wired.account.user", maxReads: 20)
    }

    func testBanlistBlocksLoginUntilRemoved() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let admin = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { admin.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: admin)
        _ = try sendLoginAndExpectSuccess(socket: admin, username: "it_admin", password: "secret")
        drainMessages(socket: admin)

        let addBan = P7Message(withName: "wired.banlist.add_ban", spec: admin.spec)
        addBan.addParameter(field: "wired.banlist.ip", value: "127.0.0.1")
        XCTAssertTrue(admin.write(addBan))
        _ = try readMessage(from: admin, expectedName: "wired.okay", maxReads: 10)

        let blocked = try runtime.connectClient(username: "guest", password: "")
        defer { blocked.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: blocked)
        let denied = try sendLoginAndExpectError(socket: blocked, username: "guest", password: "")
        XCTAssertEqual(denied.name, "wired.banned")

        let deleteBan = P7Message(withName: "wired.banlist.delete_ban", spec: admin.spec)
        deleteBan.addParameter(field: "wired.banlist.ip", value: "127.0.0.1")
        XCTAssertTrue(admin.write(deleteBan))
        _ = try readMessage(from: admin, expectedName: "wired.okay", maxReads: 10)
    }

    func testEventAndLogCoverageWithSubscribeAndHistoryFetch() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let triggerEvent = P7Message(withName: "wired.account.list_users", spec: socket.spec)
        XCTAssertTrue(socket.write(triggerEvent))
        _ = try readMessage(from: socket, expectedName: "wired.account.user_list.done", maxReads: 60, timeout: 1)

        let getEvents = P7Message(withName: "wired.event.get_events", spec: socket.spec)
        getEvents.addParameter(field: "wired.event.last_event_count", value: UInt32(10))
        XCTAssertTrue(socket.write(getEvents))

        var sawEventList = false
        var sawEventListDone = false
        for _ in 0..<80 {
            let message = try socket.readMessage(timeout: 0.5, enforceDeadline: true)
            if message.name == "wired.event.event_list" {
                sawEventList = true
            }
            if message.name == "wired.event.event_list.done" {
                sawEventListDone = true
                break
            }
        }
        XCTAssertTrue(sawEventList)
        XCTAssertTrue(sawEventListDone)

        let marker = "integration-log-\(UUID().uuidString)"
        Logger.info(marker)

        let getLog = P7Message(withName: "wired.log.get_log", spec: socket.spec)
        XCTAssertTrue(socket.write(getLog))

        var sawMarker = false
        var sawLogDone = false
        for _ in 0..<160 {
            let message = try socket.readMessage(timeout: 0.5, enforceDeadline: true)
            if message.name == "wired.log.list",
               message.string(forField: "wired.log.message")?.contains(marker) == true {
                sawMarker = true
            }
            if message.name == "wired.log.list.done" {
                sawLogDone = true
                break
            }
        }
        XCTAssertTrue(sawLogDone)
        XCTAssertTrue(sawMarker)
    }
}
